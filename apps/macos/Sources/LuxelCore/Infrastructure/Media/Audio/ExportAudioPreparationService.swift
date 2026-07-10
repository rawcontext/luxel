import AVFAudio
import AVFoundation
import AudioToolbox
import CoreMedia
import Foundation

public struct ExportAudioPreparationService: ExportAudioPreparing, Sendable {
    public static let sampleRate = 48_000
    public static let channelCount = 2

    private let enhancer: any StudioVoiceEnhancing
    private let temporaryRootURL: URL
    private let windowFrameCount: Int
    private let overlapFrameCount: Int

    public init(
        enhancer: any StudioVoiceEnhancing,
        temporaryRootURL: URL = FileManager.default.temporaryDirectory
            .appending(path: "Luxel/StudioVoice", directoryHint: .isDirectory),
        windowDuration: TimeInterval = 45,
        overlapDuration: TimeInterval = 0.5
    ) {
        self.enhancer = enhancer
        self.temporaryRootURL = temporaryRootURL
        windowFrameCount = max(2, Int(windowDuration * Double(Self.sampleRate)))
        overlapFrameCount = max(
            1,
            min(
                Int(overlapDuration * Double(Self.sampleRate)),
                windowFrameCount / 2 - 1
            )
        )
    }

    public func prepareAudio(
        for requests: [ExportRequest],
        progress: ExportAudioPreparationProgressHandler?
    ) async throws -> PreparedExportAudioSet {
        let groups = Dictionary(grouping: requests.indices.filter {
            requests[$0].requiresAudioPreparation
        }) { index in
            AudioPreparationKey(request: requests[index])
        }
        guard !groups.isEmpty else {
            return PreparedExportAudioSet()
        }

        let directoryURL = temporaryRootURL.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let cleanup = PreparedExportAudioSet(
            assetsByRequestIndex: [:],
            directoryURL: directoryURL
        )
        do {
            return try await prepareGroups(
                groups,
                requests: requests,
                directoryURL: directoryURL,
                cleanup: cleanup,
                progress: progress
            )
        } catch {
            cleanup.removeTemporaryFiles()
            throw error
        }
    }

    private func prepareGroups(
        _ groups: [AudioPreparationKey: [Int]],
        requests: [ExportRequest],
        directoryURL: URL,
        cleanup: PreparedExportAudioSet,
        progress: ExportAudioPreparationProgressHandler?
    ) async throws -> PreparedExportAudioSet {
        let worker = ExportAudioPreparationWorker(
            enhancer: enhancer,
            directoryURL: directoryURL,
            windowFrameCount: windowFrameCount,
            overlapFrameCount: overlapFrameCount
        )
        var assetsByRequestIndex: [Int: PreparedAudioAsset] = [:]
        return try await withTaskCancellationHandler {
            for (groupIndex, group) in groups.enumerated() {
                try Task.checkCancellation()
                guard let representativeIndex = group.value.first else {
                    continue
                }
                let requestIndices = group.value.sorted()
                let asset = try await worker.prepare(
                    request: requests[representativeIndex],
                    fileStem: "prepared-\(groupIndex)",
                    progress: { value in
                        await progress?(
                            ExportAudioPreparationProgress(
                                requestIndices: requestIndices,
                                progress: value
                            )
                        )
                    }
                )
                for requestIndex in requestIndices {
                    assetsByRequestIndex[requestIndex] = asset
                }
            }
            return PreparedExportAudioSet(
                assetsByRequestIndex: assetsByRequestIndex,
                directoryURL: directoryURL
            )
        } onCancel: {
            worker.cancel()
            cleanup.removeTemporaryFiles()
        }
    }
}

private struct AudioPreparationKey: Hashable {
    struct Track: Hashable {
        let kind: AudioTrackKind
        let volume: Double
        let isMuted: Bool
    }

    let sourceURL: URL
    let trimStart: TimeInterval
    let trimEnd: TimeInterval
    let tracks: [Track]
    let normalizesPeak: Bool
    let studioVoiceEnabled: Bool

    init(request: ExportRequest) {
        sourceURL = request.inputFileURL.standardizedFileURL
        trimStart = request.timeRange.start
        trimEnd = request.timeRange.end
        tracks = request.audioMix?.tracks.map {
            Track(kind: $0.kind, volume: $0.volume, isMuted: $0.isMuted)
        } ?? []
        normalizesPeak = request.audioMix?.normalizePeak == true
        studioVoiceEnabled = request.shouldApplyStudioVoice
    }
}

final class ExportAudioPreparationWorker: @unchecked Sendable {
    static let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: Double(ExportAudioPreparationService.sampleRate),
        channels: AVAudioChannelCount(ExportAudioPreparationService.channelCount),
        interleaved: false
    )!

    let enhancer: any StudioVoiceEnhancing
    let directoryURL: URL
    let windowFrameCount: Int
    let overlapFrameCount: Int
    let lock = NSLock()
    var activeReader: AVAssetReader?

    init(
        enhancer: any StudioVoiceEnhancing,
        directoryURL: URL,
        windowFrameCount: Int,
        overlapFrameCount: Int
    ) {
        self.enhancer = enhancer
        self.directoryURL = directoryURL
        self.windowFrameCount = windowFrameCount
        self.overlapFrameCount = overlapFrameCount
    }

    func cancel() {
        lock.lock()
        let reader = activeReader
        lock.unlock()
        reader?.cancelReading()
    }

    func prepare(
        request: ExportRequest,
        fileStem: String,
        progress: StudioVoiceProgressHandler?
    ) async throws -> PreparedAudioAsset {
        let rawURL = directoryURL.appending(path: "\(fileStem)-raw.caf")
        let outputURL = directoryURL.appending(path: "\(fileStem).caf")

        do {
            let peak = try await renderRawPCM(
                request: request,
                outputURL: rawURL,
                progress: progress
            )
            try Task.checkCancellation()

            let resolvedGains = AudioMixResolutionService(
                analyzer: EmptyAudioPeakAnalyzer()
            ).resolvedGains(
                for: request,
                measuredPeaks: [.system: peak]
            )
            let gain = resolvedGains[.system]
                ?? request.audioMix?.mix(for: .system).gain
                ?? 1
            try applyGain(gain, inputURL: rawURL, outputURL: outputURL)
            try? FileManager.default.removeItem(at: rawURL)
            try Task.checkCancellation()

            return PreparedAudioAsset(
                fileURL: outputURL,
                duration: request.timeRange.duration,
                sampleRate: ExportAudioPreparationService.sampleRate,
                channelCount: ExportAudioPreparationService.channelCount
            )
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: rawURL)
            try? FileManager.default.removeItem(at: outputURL)
            throw CancellationError()
        } catch {
            try? FileManager.default.removeItem(at: rawURL)
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }
}
