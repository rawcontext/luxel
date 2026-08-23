@preconcurrency import AVFoundation
import CoreMedia
import Foundation
@preconcurrency import ScreenCaptureKit

final class ScreenCaptureKitAudioOnlyCaptureSession: NSObject, SCStreamOutput,
    @unchecked Sendable
{
    private static let streamStartTimeout: Duration = .seconds(10)
    private static let streamStopTimeout: Duration = .seconds(5)

    private let sampleHandlerQueue = DispatchQueue(
        label: "media.luxel.screen-capture-kit-audio-only-recorder")
    private let stream: SCStream
    private let segment: ScreenCaptureKitAudioOnlyWriterSegment

    static func make(
        request: AudioRecordingRequest,
        audioLevelHandler: (@Sendable (AudioLevelSample) -> Void)?
    ) async throws -> ScreenCaptureKitAudioOnlyCaptureSession {
        let contentFilter = try await defaultDisplayContentFilter()
        return try ScreenCaptureKitAudioOnlyCaptureSession(
            request: request,
            contentFilter: contentFilter,
            fileManager: .default,
            audioLevelHandler: audioLevelHandler
        )
    }

    private init(
        request: AudioRecordingRequest,
        contentFilter: SCContentFilter,
        fileManager: FileManager,
        audioLevelHandler: (@Sendable (AudioLevelSample) -> Void)?
    ) throws {
        try fileManager.createDirectory(
            at: request.outputFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? fileManager.removeItem(at: request.outputFileURL)

        stream = SCStream(
            filter: contentFilter,
            configuration: ScreenCaptureKitAudioOnlyRecorder.makeStreamConfiguration(for: request),
            delegate: nil
        )
        segment = try ScreenCaptureKitAudioOnlyWriterSegment(
            request: request,
            outputFileURL: request.outputFileURL,
            fileManager: fileManager,
            audioLevelHandler: audioLevelHandler
        )
        super.init()

        try addStreamOutputs(for: request)
    }

    func start() async throws {
        try await Self.startStreamCapture(stream)
    }

    func stop() async throws {
        try await Self.stopStreamCapture(stream)
        try await segment.finish(on: sampleHandlerQueue)
    }

    func cancel() async {
        await segment.cancel(on: sampleHandlerQueue)
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        segment.append(sampleBuffer, outputType: type)
    }

    private func addStreamOutputs(for request: AudioRecordingRequest) throws {
        if request.audio.capturesSystemAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleHandlerQueue)
        }

        if request.audio.capturesMicrophone {
            try stream.addStreamOutput(
                self, type: .microphone, sampleHandlerQueue: sampleHandlerQueue)
        }
    }

    private static func defaultDisplayContentFilter() async throws -> SCContentFilter {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
            throw ScreenCaptureKitAudioOnlyRecorderError.missingDisplay
        }

        return SCContentFilter(display: display, excludingWindows: [])
    }

    private static func startStreamCapture(_ stream: SCStream) async throws {
        try await ScreenCaptureKitStreamLifecycle.start(stream, timeout: streamStartTimeout) {
            ScreenCaptureKitAudioOnlyRecorderError.startFailed("Timed out starting capture")
        }
    }

    private static func stopStreamCapture(_ stream: SCStream) async throws {
        try await ScreenCaptureKitStreamLifecycle.stop(stream, timeout: streamStopTimeout)
    }
}
