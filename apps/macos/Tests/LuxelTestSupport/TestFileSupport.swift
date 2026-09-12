import AVFAudio
import AudioToolbox
import CoreGraphics
import Foundation
import LuxelCore
import Testing

public enum TestFileSupportError: Error {
    case packageRootNotFound(String)
    case audioFormatUnavailable
    case audioBufferUnavailable
    case imageContextUnavailable
    case imageUnavailable
}

public func testPackageRootURL(from filePath: String = #filePath) throws -> URL {
    var url = testSourceFileURL(from: filePath)
    while url.lastPathComponent != "Tests" {
        let parent = url.deletingLastPathComponent()
        guard parent.path != url.path else {
            throw TestFileSupportError.packageRootNotFound(filePath)
        }
        url = parent
    }
    return url.deletingLastPathComponent()
}

public func testFixtureURL(
    _ fileName: String,
    from filePath: String = #filePath
) throws -> URL {
    try testPackageRootURL(from: filePath)
        .appending(path: "Tests/Fixtures")
        .appending(path: fileName)
}

public func temporaryTestFileURL(
    prefix: String = "",
    pathExtension: String
) -> URL {
    FileManager.default.temporaryDirectory
        .appending(path: prefix + UUID().uuidString)
        .appendingPathExtension(pathExtension)
}

public func makeTestImage(
    width: Int,
    height: Int,
    draw: (CGContext) -> Void
) throws -> CGImage {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    guard
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else {
        throw TestFileSupportError.imageContextUnavailable
    }
    draw(context)
    guard let image = context.makeImage() else {
        throw TestFileSupportError.imageUnavailable
    }
    return image
}

public func testAsyncStream<Element: Sendable>(
    _ elements: [Element]
) -> AsyncStream<Element> {
    AsyncStream { continuation in
        for element in elements {
            continuation.yield(element)
        }
        continuation.finish()
    }
}

public struct TestExportRequestExpectation {
    public let format: ExportFormat
    public let timeRange: TimeRange
    public let pixelSize: PixelSize
    public let frameRate: FrameRate
    public let shouldMute: Bool
    public let quality: ExportQuality
    public let speed: PlaybackSpeed

    public init(
        format: ExportFormat,
        timeRange: TimeRange,
        pixelSize: PixelSize,
        frameRate: FrameRate,
        shouldMute: Bool,
        quality: ExportQuality,
        speed: PlaybackSpeed
    ) {
        self.format = format
        self.timeRange = timeRange
        self.pixelSize = pixelSize
        self.frameRate = frameRate
        self.shouldMute = shouldMute
        self.quality = quality
        self.speed = speed
    }
}

public func expectTestExportRequest(
    _ request: ExportRequest?,
    expected: TestExportRequestExpectation
) {
    #expect(request?.format == expected.format)
    #expect(request?.timeRange == expected.timeRange)
    #expect(request?.pixelSize == expected.pixelSize)
    #expect(request?.frameRate == expected.frameRate)
    #expect(request?.outputShouldMute == expected.shouldMute)
    #expect(request?.quality == expected.quality)
    #expect(request?.speed == expected.speed)
}

public func testRecordAutomationInvocation(
    errorCallback: URL? = nil
) -> AutomationInvocation {
    AutomationInvocation(
        command: .record(
            AutomationRecordingOptions(
                target: .display(.main),
                presetName: "Quick GIF",
                countdownSeconds: 3,
                outputDirectory: URL(fileURLWithPath: "/tmp/Luxel Exports")
            )
        ),
        callbacks: AutomationCallbacks(
            success: URL(string: "luxel-callback://done"),
            error: errorCallback
        )
    )
}

public func writeSilentTestPCM(to url: URL, duration: TimeInterval) throws {
    guard
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: false
        )
    else {
        throw TestFileSupportError.audioFormatUnavailable
    }
    let frameCount = AVAudioFrameCount(duration * 48_000)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
        throw TestFileSupportError.audioBufferUnavailable
    }
    buffer.frameLength = frameCount
    let file = try AVAudioFile(
        forWriting: url,
        settings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true
        ],
        commonFormat: .pcmFormatFloat32,
        interleaved: false
    )
    try file.write(from: buffer)
}

public func writeSilentTestAAC(to url: URL, duration: TimeInterval) throws {
    let sampleRate = 44_100.0
    guard
        let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 1
        )
    else {
        throw TestFileSupportError.audioFormatUnavailable
    }
    let frameCount = AVAudioFrameCount(sampleRate * duration)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
        throw TestFileSupportError.audioBufferUnavailable
    }
    buffer.frameLength = frameCount
    let file = try AVAudioFile(
        forWriting: url,
        settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000
        ]
    )
    try file.write(from: buffer)
}

public func testExecutablePath(named name: String) -> String? {
    let searchPaths =
        (ProcessInfo.processInfo.environment["PATH"] ?? "")
        .split(separator: ":")
        .map(String.init) + ["/opt/homebrew/bin", "/usr/local/bin"]
    return
        searchPaths
        .map { URL(fileURLWithPath: $0).appending(path: name).path }
        .first { FileManager.default.isExecutableFile(atPath: $0) }
}

public struct PreparedAudioTestInput: Sendable {
    public let input: MediaExportInput
    public let preparedURL: URL

    public init(input: MediaExportInput, preparedURL: URL) {
        self.input = input
        self.preparedURL = preparedURL
    }
}

public func makePreparedAudioTestInput(
    format: ExportFormat,
    from filePath: String = #filePath
) throws -> PreparedAudioTestInput {
    let preparedURL = temporaryTestFileURL(
        prefix: "prepared-audio-",
        pathExtension: "caf"
    )
    try writeSilentTestPCM(to: preparedURL, duration: 0.3)
    let request = try ExportRequest(
        inputFileURL: testFixtureURL("input.mp4", from: filePath),
        format: format,
        pixelSize: PixelSize(width: 320, height: 180),
        frameRate: FrameRate(10),
        timeRange: TimeRange(start: 1, end: 1.3),
        shouldMute: false,
        studioVoiceEnabled: true,
        shouldCrop: false,
        quality: .compact
    )
    return PreparedAudioTestInput(
        input: MediaExportInput(
            request: request,
            preparedAudio: PreparedAudioAsset(
                fileURL: preparedURL,
                duration: 0.3,
                sampleRate: 48_000,
                channelCount: 2
            )
        ),
        preparedURL: preparedURL
    )
}

public struct TestProcessResult: Sendable {
    public let output: String
    public let error: String
    public let terminationStatus: Int32
}

public func runTestProcess(
    executable: String,
    arguments: [String]
) throws -> TestProcessResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe
    try process.run()
    process.waitUntilExit()
    return TestProcessResult(
        output: String(
            bytes: outputPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? "",
        error: String(
            bytes: errorPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? "",
        terminationStatus: process.terminationStatus
    )
}

public func runTestFFProbe(
    executable: String,
    fileURL: URL
) throws -> TestProcessResult {
    try runTestProcess(
        executable: executable,
        arguments: [
            "-v", "error",
            "-show_format",
            "-show_streams",
            "-of", "json",
            fileURL.path
        ])
}

open class ExistingTestFileSystem: FileSystem, @unchecked Sendable {
    private let existingFiles: Set<URL>

    public init(existingFiles: Set<URL> = []) {
        self.existingFiles = existingFiles
    }

    open func fileExists(at url: URL) -> Bool {
        existingFiles.contains(url)
    }

    public func createDirectory(at url: URL) throws {}
    public func copyFile(from sourceURL: URL, to destinationURL: URL) throws {}
    public func writeData(_ data: Data, to url: URL) throws {}
    public func removeFile(at url: URL) throws {}
    public func trashItem(at url: URL) throws {}
}

public final class AlwaysExistingTestFileSystem: ExistingTestFileSystem, @unchecked Sendable {
    public init() {
        super.init()
    }

    public override func fileExists(at url: URL) -> Bool { true }
}

public struct TestCopiedFile: Equatable, Sendable {
    public let sourceURL: URL
    public let destinationURL: URL

    public init(sourceURL: URL, destinationURL: URL) {
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
    }
}

public final class TestFileSystemSpy: FileSystem, @unchecked Sendable {
    private let lock = NSLock()
    private var capturedCreatedDirectories: [URL] = []
    private var capturedCopiedFiles: [TestCopiedFile] = []
    private var capturedTrashedFiles: [URL] = []
    private let trashError: Error?

    public init(trashError: Error? = nil) {
        self.trashError = trashError
    }

    public var createdDirectories: [URL] {
        lock.withLock { capturedCreatedDirectories }
    }

    public var copiedFiles: [TestCopiedFile] {
        lock.withLock { capturedCopiedFiles }
    }

    public var trashedFiles: [URL] {
        lock.withLock { capturedTrashedFiles }
    }

    public func fileExists(at url: URL) -> Bool { false }

    public func createDirectory(at url: URL) throws {
        lock.withLock { capturedCreatedDirectories.append(url) }
    }

    public func copyFile(from sourceURL: URL, to destinationURL: URL) throws {
        lock.withLock {
            capturedCopiedFiles.append(
                TestCopiedFile(sourceURL: sourceURL, destinationURL: destinationURL)
            )
        }
    }

    public func writeData(_ data: Data, to url: URL) throws {}
    public func removeFile(at url: URL) throws {}

    public func trashItem(at url: URL) throws {
        lock.withLock { capturedTrashedFiles.append(url) }
        if let trashError {
            throw trashError
        }
    }
}
