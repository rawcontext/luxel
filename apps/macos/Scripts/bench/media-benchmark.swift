// Local media benchmark for Luxel's export and transcription pipeline.
// Run via Scripts/benchmark-media.sh (or `bun run bench:media` in apps/macos).
//
// Generates a deterministic 15s 1080p60 screen-content fixture, exports it
// through luxel-cli across every codec family, validates the outputs, and
// compares wall-clock times against .bench/baseline.json. Exits non-zero if
// any case regresses more than the threshold.

import AVFoundation
import CoreText
import Foundation

// MARK: - Configuration

let regressionThreshold = 1.25  // fail when current time > baseline * threshold
let fixtureDuration = 15.0
let fixtureFPS = 30
let fixtureSize = (width: 1920, height: 1080)

let arguments = CommandLine.arguments
let updateBaseline = arguments.contains("--update-baseline")
let runs =
    arguments.firstIndex(of: "--runs").flatMap { index in
        arguments.indices.contains(index + 1) ? Int(arguments[index + 1]) : nil
    } ?? 2

guard let cliPath = ProcessInfo.processInfo.environment["LUXEL_CLI"] else {
    fatalError("Set LUXEL_CLI to the luxel-cli binary path (benchmark-media.sh does this).")
}

let benchDirectory = URL(
    fileURLWithPath: ProcessInfo.processInfo.environment["BENCH_DIR"] ?? ".bench")
let fixtureDirectory = benchDirectory.appendingPathComponent("fixtures")
let outputDirectory = benchDirectory.appendingPathComponent("out")
let baselineURL = benchDirectory.appendingPathComponent("baseline.json")
let sourceFixtureURL = fixtureDirectory.appendingPathComponent("master-1080p.mp4")
let speechURL = fixtureDirectory.appendingPathComponent("speech.wav")
try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

// MARK: - Fixture generation (deterministic screen-content clip + speech)

func runProcess(_ launchPath: String, _ processArguments: [String]) throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = processArguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    return process.terminationStatus
}

func makeSpeechFixture() throws {
    let sentence =
        "Welcome to the Luxel benchmark recording. This audio track exists so that we can "
        + "measure transcription speed and audio encoding performance. Luxel is a screen recorder for "
        + "the Mac, built to export video in modern formats like A V one and Web M. "
    let text = String(repeating: sentence, count: 6)
    let status = try runProcess(
        "/usr/bin/say",
        ["-o", speechURL.path, "--data-format=LEF32@48000", text])
    guard status == 0 else { fatalError("`say` failed to synthesize the speech fixture") }
}

func makeCodeImage() -> CGImage {
    let lines = (0..<400).map { index in
        "let frame\(index) = pipeline.encode(sample: buffer[\(index % 97)], keyframe: \(index % 150 == 0))"
    }
    let text = lines.joined(separator: "\n")
    let width = fixtureSize.width
    let height = 12_000
    let context = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
            | CGImageByteOrderInfo.order32Little.rawValue)!
    context.setFillColor(CGColor(srgbRed: 0.067, green: 0.067, blue: 0.106, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let attributed = NSAttributedString(
        string: text,
        attributes: [
            kCTFontAttributeName as NSAttributedString.Key:
                CTFontCreateWithName("Menlo" as CFString, 22, nil),
            kCTForegroundColorAttributeName as NSAttributedString.Key:
                CGColor(srgbRed: 0.804, green: 0.839, blue: 0.957, alpha: 1)
        ])
    let framesetter = CTFramesetterCreateWithAttributedString(attributed)
    let path = CGPath(
        rect: CGRect(x: 60, y: 20, width: width - 120, height: height - 40), transform: nil)
    let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
    CTFrameDraw(frame, context)
    return context.makeImage()!
}

struct FixtureWriterContext {
    let writer: AVAssetWriter
    let videoInput: AVAssetWriterInput
    let adaptor: AVAssetWriterInputPixelBufferAdaptor
    let audioInput: AVAssetWriterInput
}

func makeFixtureWriter() throws -> FixtureWriterContext {
    let writer = try AVAssetWriter(outputURL: sourceFixtureURL, fileType: .mp4)
    let videoInput = AVAssetWriterInput(
        mediaType: .video,
        outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: fixtureSize.width,
            AVVideoHeightKey: fixtureSize.height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 20_000_000]
        ])
    videoInput.expectsMediaDataInRealTime = true
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: videoInput,
        sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: fixtureSize.width,
            kCVPixelBufferHeightKey as String: fixtureSize.height
        ])
    let audioInput = AVAssetWriterInput(
        mediaType: .audio,
        outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 192_000
        ])
    audioInput.expectsMediaDataInRealTime = true
    writer.add(videoInput)
    writer.add(audioInput)
    return FixtureWriterContext(
        writer: writer,
        videoInput: videoInput,
        adaptor: adaptor,
        audioInput: audioInput
    )
}

func appendVideoFrames(
    to adaptor: AVAssetWriterInputPixelBufferAdaptor,
    videoInput: AVAssetWriterInput
) {
    let codeImage = makeCodeImage()
    let frameCount = Int(fixtureDuration) * fixtureFPS
    for frame in 0..<frameCount {
        while !videoInput.isReadyForMoreMediaData { usleep(2000) }
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pixelBuffer)
        guard let buffer = pixelBuffer else { fatalError("pixel buffer allocation failed") }
        CVPixelBufferLockBaseAddress(buffer, [])
        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: fixtureSize.width, height: fixtureSize.height,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGImageByteOrderInfo.order32Little.rawValue)!
        let time = Double(frame) / Double(fixtureFPS)
        let scroll = (time * 90).truncatingRemainder(dividingBy: 10_000)
        context.draw(
            codeImage,
            in: CGRect(
                x: 0, y: -12_000 + Double(fixtureSize.height) + scroll,
                width: Double(fixtureSize.width), height: 12_000))
        context.setFillColor(CGColor(srgbRed: 0.537, green: 0.706, blue: 0.980, alpha: 1))
        context.fill(
            CGRect(
                x: 820 + 500 * sin(time * 1.3), y: 420 + 320 * cos(time * 0.9),
                width: 280, height: 160))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        adaptor.append(
            buffer,
            withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fixtureFPS)))
    }
    videoInput.markAsFinished()
}

func appendAudioSamples(
    from readerOutput: AVAssetReaderTrackOutput,
    to audioInput: AVAssetWriterInput
) {
    let cutoff = CMTime(seconds: fixtureDuration, preferredTimescale: 48_000)
    while let sample = readerOutput.copyNextSampleBuffer() {
        while !audioInput.isReadyForMoreMediaData { usleep(2000) }
        if CMSampleBufferGetPresentationTimeStamp(sample) >= cutoff { break }
        audioInput.append(sample)
    }
    audioInput.markAsFinished()
}

func makeSourceFixture() async throws {
    let context = try makeFixtureWriter()

    let speechAsset = AVURLAsset(url: speechURL)
    let reader = try AVAssetReader(asset: speechAsset)
    let speechTrack = try await speechAsset.loadTracks(withMediaType: .audio).first!
    let readerOutput = AVAssetReaderTrackOutput(
        track: speechTrack,
        outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2
        ])
    reader.add(readerOutput)

    context.writer.startWriting()
    reader.startReading()
    context.writer.startSession(atSourceTime: .zero)
    appendVideoFrames(to: context.adaptor, videoInput: context.videoInput)
    appendAudioSamples(from: readerOutput, to: context.audioInput)
    reader.cancelReading()
    await context.writer.finishWriting()
    guard context.writer.status == .completed else {
        fatalError("fixture writer failed: \(String(describing: context.writer.error))")
    }
}

if !FileManager.default.fileExists(atPath: speechURL.path) {
    print("Generating speech fixture…")
    try makeSpeechFixture()
}
if !FileManager.default.fileExists(atPath: sourceFixtureURL.path) {
    print("Generating master video fixture…")
    try await makeSourceFixture()
}

// MARK: - Benchmark cases

struct BenchCase {
    let name: String
    let outputFile: String
    let arguments: [String]
    /// Expected media duration for AVFoundation-readable outputs; nil skips the check.
    let expectedDuration: Double?
}

let cases: [BenchCase] = [
    BenchCase(
        name: "mp4-h264-balanced", outputFile: "h264.mp4",
        arguments: ["--format", "mp4", "--quality", "balanced"], expectedDuration: fixtureDuration),
    BenchCase(
        name: "hevc-balanced", outputFile: "hevc.mp4",
        arguments: ["--format", "hevc", "--quality", "balanced"], expectedDuration: fixtureDuration),
    BenchCase(
        name: "av1-balanced", outputFile: "av1-balanced.mp4",
        arguments: ["--format", "av1", "--quality", "balanced"], expectedDuration: fixtureDuration),
    BenchCase(
        name: "av1-high", outputFile: "av1-high.mp4",
        arguments: ["--format", "av1", "--quality", "high"], expectedDuration: fixtureDuration),
    BenchCase(
        name: "webm-vp9-balanced", outputFile: "vp9-balanced.webm",
        arguments: ["--format", "webm", "--quality", "balanced"], expectedDuration: nil),
    BenchCase(
        name: "webm-vp9-high", outputFile: "vp9-high.webm",
        arguments: ["--format", "webm", "--quality", "high"], expectedDuration: nil),
    BenchCase(
        name: "gif-5s-540p", outputFile: "clip.gif",
        arguments: [
            "--format", "gif", "--duration", "5", "--fps", "15",
            "--width", "960", "--height", "540"
        ], expectedDuration: nil),
    BenchCase(
        name: "m4a-audio", outputFile: "audio.m4a",
        arguments: ["--format", "m4a"], expectedDuration: fixtureDuration)
]

func timeCommand(_ commandArguments: [String]) throws -> (seconds: Double, status: Int32) {
    let clock = ContinuousClock()
    let start = clock.now
    let status = try runProcess(cliPath, commandArguments)
    let elapsed = clock.now - start
    let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    return (seconds, status)
}

func pad(_ name: String) -> String {
    name.padding(toLength: max(24, name.count), withPad: " ", startingAt: 0)
}

func validate(_ benchCase: BenchCase, at url: URL) async throws {
    let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    guard size > 0 else { fatalError("\(benchCase.name): empty output") }
    if let expected = benchCase.expectedDuration {
        let duration = try await AVURLAsset(url: url).load(.duration).seconds
        guard abs(duration - expected) < 1.0 else {
            fatalError("\(benchCase.name): duration \(duration)s, expected ~\(expected)s")
        }
    }
}

struct Result: Codable {
    let seconds: Double
    let bytes: Int
}

var results: [String: Result] = [:]

for benchCase in cases {
    let outputURL = outputDirectory.appendingPathComponent(benchCase.outputFile)
    var best = Double.greatestFiniteMagnitude
    for _ in 0..<max(runs, 1) {
        try? FileManager.default.removeItem(at: outputURL)
        let run = try timeCommand(
            ["convert", sourceFixtureURL.path, outputURL.path] + benchCase.arguments
                + ["--overwrite", "--quiet"])
        guard run.status == 0 else { fatalError("luxel-cli convert failed for \(benchCase.name)") }
        best = min(best, run.seconds)
    }
    try await validate(benchCase, at: outputURL)
    let bytes = (try FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int) ?? 0
    results[benchCase.name] = Result(seconds: best, bytes: bytes)
    print("  \(pad(benchCase.name))" + String(format: "%6.2fs  %8d bytes", best, bytes))
}

// Transcription: single run (it is the longest case). Skipped, not failed, when
// speech authorization is missing — see AppleSpeechRecognitionAuthorizationService.
let transcriptURL = outputDirectory.appendingPathComponent("transcript.txt")
try? FileManager.default.removeItem(at: transcriptURL)
let transcribeRun = try timeCommand(
    ["transcribe", speechURL.path, "--output", transcriptURL.path, "--overwrite"])
if transcribeRun.status == 0 {
    let transcript = (try? String(contentsOf: transcriptURL, encoding: .utf8)) ?? ""
    guard transcript.localizedCaseInsensitiveContains("luxel") else {
        fatalError("transcription output missing expected content: \(transcript.prefix(200))")
    }
    results["transcribe-107s-speech"] = Result(
        seconds: transcribeRun.seconds, bytes: transcript.utf8.count)
    print(
        "  \(pad("transcribe-107s-speech"))"
            + String(format: "%6.2fs  %8d bytes", transcribeRun.seconds, transcript.utf8.count))
} else {
    print(
        "  \(pad("transcribe-107s-speech")) SKIPPED (speech recognition not authorized for this terminal)"
    )
}

// MARK: - Baseline comparison

struct Baseline: Codable {
    let machine: String
    let cases: [String: Result]
}

func currentMachine() -> String {
    var size = 0
    sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
    var brand = [CChar](repeating: 0, count: size)
    sysctlbyname("machdep.cpu.brand_string", &brand, &size, nil, 0)
    return String(cString: brand)
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

if updateBaseline || !FileManager.default.fileExists(atPath: baselineURL.path) {
    let baseline = Baseline(machine: currentMachine(), cases: results)
    try encoder.encode(baseline).write(to: baselineURL)
    print("\nBaseline written to \(baselineURL.path)")
    exit(0)
}

let baseline = try JSONDecoder().decode(Baseline.self, from: Data(contentsOf: baselineURL))
if baseline.machine != currentMachine() {
    print(
        "\nWARNING: baseline was recorded on \"\(baseline.machine)\", this is \"\(currentMachine())\".")
}

print("\nvs baseline (fail threshold: +\(Int((regressionThreshold - 1) * 100))%):")
var regressions: [String] = []
for (name, result) in results.sorted(by: { $0.key < $1.key }) {
    guard let base = baseline.cases[name] else {
        print("  \(pad(name))" + String(format: "%6.2fs  (new case, no baseline)", result.seconds))
        continue
    }
    let delta = (result.seconds / base.seconds - 1) * 100
    let flag = result.seconds > base.seconds * regressionThreshold ? "  << REGRESSION" : ""
    print(
        "  \(pad(name))"
            + String(format: "%6.2fs  baseline %6.2fs  %+5.1f%%", result.seconds, base.seconds, delta)
            + flag)
    if !flag.isEmpty { regressions.append(name) }
}

if regressions.isEmpty {
    print("\nOK — no regressions.")
} else {
    print("\nFAILED — regressed: \(regressions.joined(separator: ", "))")
    print("If this slowdown is expected, rerun with --update-baseline.")
    exit(1)
}
