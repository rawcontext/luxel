import AVFoundation
import CoreMedia
import Foundation
import Speech

public struct AppleSpeechTranscriptExtractor: TimedSpeechTranscriber {
    private let temporaryDirectory: URL
    private let speechAuthorizationStatus: @Sendable () async -> SFSpeechRecognizerAuthorizationStatus

    public init(temporaryDirectory: URL = FileManager.default.temporaryDirectory) {
        self.init(
            temporaryDirectory: temporaryDirectory,
            speechAuthorizationStatus: Self.currentSpeechAuthorization
        )
    }

    public init(
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        speechAuthorizationStatus: @escaping @Sendable () async -> SFSpeechRecognizerAuthorizationStatus
    ) {
        self.temporaryDirectory = temporaryDirectory
        self.speechAuthorizationStatus = speechAuthorizationStatus
    }

    public func transcribe(_ request: TimedSpeechTranscriptionRequest) async throws
    -> [TimedTranscriptSpan] {
        try await ensureSpeechAuthorization()
        guard Speech.SpeechTranscriber.isAvailable else {
            throw AppleSpeechTranscriptError.unavailable
        }
        guard let locale = await Speech.SpeechTranscriber.supportedLocale(equivalentTo: request.locale)
        else {
            throw AppleSpeechTranscriptError.unsupportedLocale
        }

        let transcriber = Speech.SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange, .transcriptionConfidence]
        )
        try await ensureAssetsInstalled(for: [transcriber])

        let preparedAudioURL: URL
        if let audioTrackIndex = request.audioTrackIndex {
            preparedAudioURL = try await isolatedAudioURL(
                from: request.audioURL,
                audioTrackIndex: audioTrackIndex
            )
        } else {
            preparedAudioURL = request.audioURL
        }
        defer {
            if preparedAudioURL != request.audioURL {
                try? FileManager.default.removeItem(at: preparedAudioURL)
            }
        }

        let audioFile = try AVAudioFile(forReading: preparedAudioURL)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let collectionTask = Task {
            try await Self.collectSpans(
                from: transcriber,
                source: request.source
            )
        }

        do {
            try await analyzer.prepareToAnalyze(in: audioFile.processingFormat)
            _ = try await analyzer.analyzeSequence(from: audioFile)
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            return try await collectionTask.value
        } catch {
            collectionTask.cancel()
            throw error
        }
    }

    private func ensureSpeechAuthorization() async throws {
        guard await speechAuthorizationStatus() == .authorized else {
            throw AppleSpeechTranscriptError.authorizationDenied
        }
    }

    private static func currentSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }

    private func ensureAssetsInstalled(for modules: [any Speech.SpeechModule]) async throws {
        switch await Speech.AssetInventory.status(forModules: modules) {
        case .installed:
            return
        case .supported, .downloading:
            if let request = try await Speech.AssetInventory.assetInstallationRequest(supporting: modules) {
                try await request.downloadAndInstall()
            }

            if await Speech.AssetInventory.status(forModules: modules) == .installed {
                return
            }

            throw AppleSpeechTranscriptError.assetsUnavailable
        case .unsupported:
            throw AppleSpeechTranscriptError.assetsUnavailable
        @unknown default:
            throw AppleSpeechTranscriptError.assetsUnavailable
        }
    }

    private func isolatedAudioURL(from audioURL: URL, audioTrackIndex: Int) async throws -> URL {
        let asset = AVURLAsset(url: audioURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard audioTracks.indices.contains(audioTrackIndex) else {
            throw AppleSpeechTranscriptError.missingAudioTrack
        }

        let composition = AVMutableComposition()
        guard
            let compositionTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else {
            throw AppleSpeechTranscriptError.trackIsolationFailed
        }

        let duration = try await asset.load(.duration)
        try compositionTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            of: audioTracks[audioTrackIndex],
            at: .zero
        )

        let outputURL =
            temporaryDirectory
            .appending(path: "LuxelTranscript-\(UUID().uuidString).m4a")
        try? FileManager.default.removeItem(at: outputURL)
        guard
            let exportSession = AVAssetExportSession(
                asset: composition,
                presetName: AVAssetExportPresetAppleM4A
            )
        else {
            throw AppleSpeechTranscriptError.trackIsolationFailed
        }
        guard exportSession.supportedFileTypes.contains(.m4a) else {
            throw AppleSpeechTranscriptError.trackIsolationFailed
        }

        do {
            try await exportSession.export(to: outputURL, as: .m4a)
            return outputURL
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }

    private static func collectSpans(
        from transcriber: Speech.SpeechTranscriber,
        source: TranscriptSourceLabel?
    ) async throws -> [TimedTranscriptSpan] {
        var resultSpans: [TimedTranscriptSpan] = []

        for try await result in transcriber.results {
            guard result.isFinal else {
                continue
            }

            resultSpans.append(contentsOf: try spans(from: result, source: source))
        }

        return resultSpans
    }

    private static func spans(
        from result: Speech.SpeechTranscriber.Result,
        source: TranscriptSourceLabel?
    ) throws -> [TimedTranscriptSpan] {
        let attributedText = result.text
        var spans: [TimedTranscriptSpan] = []

        for run in attributedText.runs {
            let text = String(attributedText[run.range].characters)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, let timeRange = run.audioTimeRange else {
                continue
            }

            let start = timeRange.start.seconds
            let end = timeRange.end.seconds
            guard start.isFinite, end.isFinite, end > start else {
                continue
            }

            spans.append(
                try TimedTranscriptSpan(
                    id: "speech-\(spans.count)",
                    text: text,
                    start: start,
                    end: end,
                    confidence: run.transcriptionConfidence,
                    source: source
                ))
        }

        if spans.isEmpty {
            let fallbackText = String(attributedText.characters)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let start = result.range.start.seconds
            let end = result.range.end.seconds
            if !fallbackText.isEmpty, start.isFinite, end.isFinite, end > start {
                spans.append(
                    try TimedTranscriptSpan(
                        id: "speech-result",
                        text: fallbackText,
                        start: start,
                        end: end,
                        source: source
                    ))
            }
        }

        return spans
    }
}

public enum AppleSpeechTranscriptError: Error, Equatable, Sendable {
    case authorizationDenied
    case unavailable
    case unsupportedLocale
    case assetsUnavailable
    case missingAudioTrack
    case trackIsolationFailed
}
