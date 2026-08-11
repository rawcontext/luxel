import ArgumentParser
import Foundation
import LuxelCore

public struct LuxelFilePath: ExpressibleByArgument, Hashable, Sendable {
    public let url: URL

    public init?(argument: String) {
        let expandedPath = (argument as NSString).expandingTildeInPath
        if let url = URL(string: expandedPath),
           url.scheme != nil {
            guard url.isFileURL else {
                return nil
            }

            self.url = url.standardizedFileURL
        } else {
            self.url = URL(fileURLWithPath: expandedPath).standardizedFileURL
        }
    }

    public static var defaultCompletionKind: CompletionKind {
        .file()
    }
}

public enum LuxelHeadlessExportFormat: String, CaseIterable, ExpressibleByArgument, Sendable {
    case gif
    case hevc
    case mp4
    case av1
    case webm
    case apng
    case proRes422 = "prores422"
    case proRes4444 = "prores4444"
    case m4a
    case alac
    case wav
    case caf
    case flac

    public static var allValueStrings: [String] {
        allCases.map(\.rawValue)
    }

    public var domainValue: ExportFormat {
        switch self {
        case .gif:
            .gif
        case .hevc:
            .hevc
        case .mp4:
            .mp4
        case .av1:
            .av1
        case .webm:
            .webm
        case .apng:
            .apng
        case .proRes422:
            .proRes422
        case .proRes4444:
            .proRes4444
        case .m4a:
            .m4a
        case .alac:
            .alac
        case .wav:
            .wav
        case .caf:
            .caf
        case .flac:
            .flac
        }
    }

    public static func resolve(
        explicit: LuxelHeadlessExportFormat?,
        outputURL: URL
    ) throws -> LuxelHeadlessExportFormat {
        if let explicit {
            try validateOutputExtension(outputURL, format: explicit)
            return explicit
        }

        let outputExtension = outputURL.pathExtension.lowercased()
        if let inferred = inferredFormatsByExtension[outputExtension] {
            return inferred
        }
        switch outputExtension {
        case "mov":
            throw LuxelCLIError.invalidHeadlessExportOptions(
                "Use --format prores422 or --format prores4444 for .mov output."
            )
        case "m4a":
            throw LuxelCLIError.invalidHeadlessExportOptions(
                "Use --format m4a or --format alac for .m4a output."
            )
        case "":
            throw LuxelCLIError.invalidHeadlessExportOptions(
                "Output path must include a file extension."
            )
        default:
            throw LuxelCLIError.invalidHeadlessExportOptions(
                "Unsupported output extension .\(outputExtension). Use --format with a supported extension."
            )
        }
    }

    private static let inferredFormatsByExtension: [String: LuxelHeadlessExportFormat] = [
        "gif": .gif,
        "mp4": .mp4,
        "webm": .webm,
        "apng": .apng,
        "wav": .wav,
        "caf": .caf,
        "flac": .flac
    ]

    private static func validateOutputExtension(
        _ outputURL: URL,
        format: LuxelHeadlessExportFormat
    ) throws {
        let expectedExtension = format.domainValue.fileExtension
        guard outputURL.pathExtension.lowercased() == expectedExtension else {
            throw LuxelCLIError.invalidHeadlessExportOptions(
                "--format \(format.rawValue) requires .\(expectedExtension) output."
            )
        }
    }
}

public enum LuxelExportQualityArgument: String, CaseIterable, ExpressibleByArgument, Sendable {
    case compact
    case balanced
    case high
    case lossless

    public static var allValueStrings: [String] {
        allCases.map(\.rawValue)
    }

    public var domainValue: ExportQuality {
        switch self {
        case .compact:
            .compact
        case .balanced:
            .balanced
        case .high:
            .high
        case .lossless:
            .lossless
        }
    }
}

public struct LuxelCropRectArgument: ExpressibleByArgument, Equatable, Sendable {
    public let domainValue: CaptureRect

    public init?(argument: String) {
        let components = argument.split(separator: ",").map {
            String($0).trimmingCharacters(in: .whitespaces)
        }
        guard components.count == 4,
              let originX = Int(components[0]),
              let originY = Int(components[1]),
              let width = Int(components[2]),
              let height = Int(components[3]),
              let rect = try? CaptureRect(x: originX, y: originY, width: width, height: height)
        else {
            return nil
        }

        domainValue = rect
    }
}

public struct LuxelVideoSizeArgument: ExpressibleByArgument, Equatable, Sendable {
    public let domainValue: PixelSize

    public var width: Int {
        domainValue.width
    }

    public var height: Int {
        domainValue.height
    }

    public init?(argument: String) {
        let components = argument.split { character in
            character == "x" || character == "X"
        }
        guard components.count == 2,
              let width = Int(components[0]),
              let height = Int(components[1]),
              let size = try? PixelSize(width: width, height: height)
        else {
            return nil
        }

        domainValue = size
    }
}

public protocol LuxelEditorOpener: Sendable {
    func openEditor(fileURL: URL) throws
}

public struct SystemLuxelEditorOpener: LuxelEditorOpener {
    public init() {}

    public func openEditor(fileURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = openArguments(fileURL: fileURL)
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw LuxelCLIError.openFailed(process.terminationStatus)
        }
    }

    public func openArguments(fileURL: URL) -> [String] {
        if let appBundleURL = Self.containingAppBundleURL() {
            return ["-a", appBundleURL.path, fileURL.path]
        }

        return ["-b", "com.rawcontext.luxel", fileURL.path]
    }

    public static func containingAppBundleURL(
        executableURL: URL? = CurrentProcessExecutable.url
    ) -> URL? {
        guard var directory = executableURL?.resolvingSymlinksInPath().deletingLastPathComponent()
        else {
            return nil
        }

        for _ in 0..<8 {
            if directory.pathExtension == "app" {
                return directory
            }

            let parent = directory.deletingLastPathComponent()
            guard parent.path != directory.path else {
                return nil
            }
            directory = parent
        }

        return nil
    }
}
