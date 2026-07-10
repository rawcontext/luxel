import ArgumentParser
import Foundation
import LuxelCodecAV1
import LuxelCodecWebM
import LuxelCore

public struct LuxelHeadlessExportResult: Codable, Equatable, Sendable {
    public let filePath: String
    public let format: String
    public let width: Int
    public let height: Int
    public let shouldMute: Bool
    public let fileSizeBytes: Int64?

    public init(exportedMedia: ExportedMedia) {
        filePath = exportedMedia.fileURL.path
        format = exportedMedia.format.rawValue
        width = exportedMedia.pixelSize.width
        height = exportedMedia.pixelSize.height
        shouldMute = exportedMedia.shouldMute
        fileSizeBytes = exportedMedia.fileSizeBytes
    }
}

struct LuxelHeadlessExportRunner: Sendable {
    func convert(_ command: LuxelConvertCommand) async throws {
        try validateInputFile(command.input.url)
        try prepareOutputFile(command.output.url, overwrite: command.shouldOverwrite)

        let source = try await AVFoundationMediaMetadataReader().readSourceMedia(at: command.input.url)
        let request = try command.exportRequest(for: source)
        let result = try await export(
            request,
            to: command.output.url,
            showProgress: !command.quiet
        )
        try printExportResult(result, json: command.json)
    }

    func `export`(_ command: LuxelExportCommand) async throws {
        try validateInputFile(command.request.url)
        try prepareOutputFile(command.output.url, overwrite: command.overwrite)

        let requestData = try Data(contentsOf: command.request.url)
        let request = try JSONDecoder().decode(ExportRequest.self, from: requestData)
        let result = try await export(
            request,
            to: command.output.url,
            showProgress: !command.quiet
        )
        try printExportResult(result, json: command.json)
    }

    private func export(
        _ request: ExportRequest,
        to outputURL: URL,
        showProgress: Bool
    ) async throws -> LuxelHeadlessExportResult {
        let registry = try CodecAdapterRegistry(registrations: [
            try AV1CodecAdapter.registration(),
            try WebMCodecAdapter.registration()
        ])
        let exporter = registry.mediaExporter(nativeExporter: NativeMediaExporter())
        let exportService = ExportService(
            exporter: exporter,
            audioPreparer: ExportAudioPreparationService(
                enhancer: DeepFilterNetStudioVoiceEnhancer(
                    locator: BundledStudioVoiceModelLocator(
                        modelDirectoryURL: studioVoiceModelDirectory()
                    )
                )
            ),
            fileSystem: LocalFileSystem()
        )
        let progress = LuxelTerminalProgressReporter(
            label: "Exporting \(request.format.prettyName)",
            isEnabled: showProgress && LuxelTerminalProgressReporter.defaultIsEnabled
        )

        progress.start()
        do {
            let exported = try await exportService.export(
                request,
                to: outputURL.deletingLastPathComponent(),
                defaultName: outputURL.deletingPathExtension().lastPathComponent
            ) { snapshot in
                progress.update(snapshot.progress)
            }
            progress.finish()
            return LuxelHeadlessExportResult(
                exportedMedia: exported.withFileSizeBytes(fileSizeBytes(at: outputURL))
            )
        } catch {
            progress.fail()
            throw error
        }
    }

    private func studioVoiceModelDirectory() -> URL? {
        if let resourceURL = Bundle.main.resourceURL {
            let bundled = resourceURL
                .appendingPathComponent("Models", isDirectory: true)
                .appendingPathComponent("studio-voice", isDirectory: true)
            if FileManager.default.fileExists(atPath: bundled.path) {
                return bundled
            }
        }

        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let embedded = executableURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("studio-voice", isDirectory: true)
        return FileManager.default.fileExists(atPath: embedded.path) ? embedded : nil
    }

    private func printExportResult(_ result: LuxelHeadlessExportResult, json: Bool) throws {
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(result).withTrailingNewline())
        } else {
            print(result.filePath)
        }
    }
}

enum LuxelAsync {
    static func run<T: Sendable>(
        _ operation: @escaping @Sendable () async throws -> T
    ) throws -> T {
        let box = LuxelAsyncResultBox<T>()

        Task {
            do {
                box.resolve(.success(try await operation()))
            } catch {
                box.resolve(.failure(error))
            }
        }

        return try box.wait().get()
    }
}

final class LuxelAsyncResultBox<T: Sendable>: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var result: Result<T, any Error>?

    func resolve(_ result: Result<T, any Error>) {
        lock.lock()
        self.result = result
        lock.unlock()
        semaphore.signal()
    }

    func wait() -> Result<T, any Error> {
        semaphore.wait()
        lock.lock()
        defer {
            lock.unlock()
        }

        return result
            ?? .failure(LuxelCLIError.remoteFailure("Async command did not produce a result."))
    }
}

func validateInputFile(_ url: URL) throws {
    var isDirectory = ObjCBool(false)
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
          !isDirectory.boolValue
    else {
        throw LuxelCLIError.fileNotFound(url.path)
    }
}

func prepareOutputFile(_ url: URL, overwrite: Bool) throws {
    var isDirectory = ObjCBool(false)
    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
        guard !isDirectory.boolValue else {
            throw LuxelCLIError.invalidHeadlessExportOptions(
                "Output path is a directory: \(url.path)"
            )
        }
        guard overwrite else {
            throw LuxelCLIError.outputFileExists(url.path)
        }
    }

    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
}

func fileSizeBytes(at url: URL) -> Int64? {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
          let size = attributes[.size] as? NSNumber
    else {
        return nil
    }

    return size.int64Value
}

func validatedNonNegative(_ value: Double, name: String) throws -> Double {
    guard value.isFinite, value >= 0 else {
        throw LuxelCLIError.invalidHeadlessExportOptions("\(name) must be zero or greater.")
    }

    return value
}

func validatedPositive(_ value: Double, name: String) throws -> Double {
    guard value.isFinite, value > 0 else {
        throw LuxelCLIError.invalidHeadlessExportOptions("\(name) must be greater than zero.")
    }

    return value
}

extension Data {
    fileprivate func withTrailingNewline() -> Data {
        guard last != 0x0A else {
            return self
        }

        var data = self
        data.append(0x0A)
        return data
    }
}
