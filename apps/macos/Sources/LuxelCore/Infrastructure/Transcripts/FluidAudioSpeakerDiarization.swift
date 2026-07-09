import AVFoundation
import FluidAudio
import Foundation

/// Local manifest written next to the installed model so Settings can report
/// accurate identity and disk usage without hitting the network.
struct SpeakerDiarizationModelManifest: Codable, Equatable, Sendable {
    let packageVersion: String
    let repository: String
    let revision: String
    let expectedBytes: Int64?
    let installedBytes: Int64
    let installDate: Date
    let licenseIdentifier: String?
}

public actor FluidAudioSpeakerDiarizationModelStore: SpeakerDiarizationModelStore {
    /// Re-check on every FluidAudio version bump; embeddings and cached diarized
    /// transcripts are keyed by this identity.
    public static let packageVersion = "0.15.5"
    public static let modelRevision = "speaker-diarization-coreml@fluidaudio-\(packageVersion)"

    public enum ModelInstallError: Error, Equatable, Sendable {
        case bundledModelMissing
    }

    private let modelsDirectory: URL
    private let bundledModelDirectory: URL?
    private let catalogInfo: SpeakerDiarizationModelInfo
    private let fileManager: FileManager
    private var failureMessage: String?

    public init(
        modelsDirectory: URL,
        bundledModelDirectory: URL? = nil,
        catalogInfo: SpeakerDiarizationModelInfo = SpeakerModelCatalog.speakerDiarization,
        fileManager: FileManager = .default
    ) {
        self.modelsDirectory = modelsDirectory
        self.bundledModelDirectory = bundledModelDirectory
        self.catalogInfo = catalogInfo
        self.fileManager = fileManager
    }

    public func modelInfo() -> SpeakerDiarizationModelInfo {
        SpeakerDiarizationModelInfo(
            displayName: catalogInfo.displayName,
            repository: catalogInfo.repository,
            revision: loadManifest()?.revision ?? Self.modelRevision,
            expectedDownloadBytes: catalogInfo.expectedDownloadBytes,
            licenseIdentifier: catalogInfo.licenseIdentifier
        )
    }

    public func currentState() -> SpeakerDiarizationModelState {
        if let failureMessage {
            return .failed(
                message: failureMessage,
                expectedBytes: catalogInfo.expectedDownloadBytes
            )
        }
        if let manifest = loadManifest() {
            return .ready(
                installedBytes: installedBytes() ?? manifest.installedBytes,
                modelRevision: manifest.revision
            )
        }

        return .notDownloaded(expectedBytes: catalogInfo.expectedDownloadBytes)
    }

    /// The model ships inside the app bundle; installing is a local copy into
    /// Application Support and never touches the network.
    public func prepareModel() async throws -> SpeakerDiarizationModelState {
        if case .ready = currentState() {
            return currentState()
        }

        guard let bundledModelDirectory,
              fileManager.fileExists(atPath: bundledModelDirectory.path)
        else {
            failureMessage = "The speaker model is missing from the app bundle."
            throw ModelInstallError.bundledModelMissing
        }

        try seedFromBundle(bundledModelDirectory)
        failureMessage = nil
        try writeManifest()
        return currentState()
    }

    public func removeModel() throws {
        failureMessage = nil
        if fileManager.fileExists(atPath: modelsDirectory.path) {
            try fileManager.removeItem(at: modelsDirectory)
        }
    }

    private func seedFromBundle(_ bundledModelDirectory: URL) throws {
        let destination = modelsDirectory.appending(
            path: bundledModelDirectory.lastPathComponent)
        try fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: bundledModelDirectory, to: destination)
    }

    private var manifestURL: URL {
        modelsDirectory.appending(path: "luxel-model-manifest.json")
    }

    private func loadManifest() -> SpeakerDiarizationModelManifest? {
        guard let data = try? Data(contentsOf: manifestURL) else {
            return nil
        }

        return try? JSONDecoder().decode(SpeakerDiarizationModelManifest.self, from: data)
    }

    private func writeManifest() throws {
        let manifest = SpeakerDiarizationModelManifest(
            packageVersion: Self.packageVersion,
            repository: catalogInfo.repository,
            revision: Self.modelRevision,
            expectedBytes: catalogInfo.expectedDownloadBytes,
            installedBytes: installedBytes() ?? 0,
            installDate: Date(),
            licenseIdentifier: catalogInfo.licenseIdentifier
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
    }

    private func installedBytes() -> Int64? {
        guard
            let enumerator = fileManager.enumerator(
                at: modelsDirectory,
                includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]
            )
        else {
            return nil
        }

        var total: Int64 = 0
        var sawFile = false
        for case let fileURL as URL in enumerator {
            guard
                let values = try? fileURL.resourceValues(
                    forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey]),
                values.isRegularFile == true
            else {
                continue
            }

            sawFile = true
            total += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        }

        return sawFile ? total : nil
    }
}

public struct FluidAudioSpeakerDiarizer: SpeakerDiarizer {
    private let modelsDirectory: URL
    private let segmentExporter: AVFoundationAudioSegmentExporter

    public init(
        modelsDirectory: URL,
        segmentExporter: AVFoundationAudioSegmentExporter = AVFoundationAudioSegmentExporter()
    ) {
        self.modelsDirectory = modelsDirectory
        self.segmentExporter = segmentExporter
    }

    public func diarize(_ request: SpeakerDiarizationRequest) async throws
    -> SpeakerDiarizationOutput {
        var audioURL = request.audioURL
        var temporaryURL: URL?
        if let audioTrackIndex = try await isolationTrackIndex(for: request) {
            let isolated = try await segmentExporter.isolatedTrackURL(
                from: request.audioURL,
                audioTrackIndex: audioTrackIndex
            )
            audioURL = isolated
            temporaryURL = isolated
        }
        defer {
            if let temporaryURL {
                try? FileManager.default.removeItem(at: temporaryURL)
            }
        }

        let manager = OfflineDiarizerManager()
        try await manager.prepareModels(directory: modelsDirectory)
        do {
            let result = try await manager.process(audioURL)
            return Self.normalizedOutput(from: result)
        } catch OfflineDiarizationError.noSpeechDetected {
            return SpeakerDiarizationOutput(segments: [])
        }
    }

    /// Videos are diarized from an isolated audio track: FluidAudio's audio
    /// readers target audio files, so movie containers are exported to a
    /// temporary M4A first.
    private func isolationTrackIndex(for request: SpeakerDiarizationRequest) async throws
    -> Int? {
        if let audioTrackIndex = request.audioTrackIndex {
            return audioTrackIndex
        }

        let asset = AVURLAsset(url: request.audioURL)
        let hasVideoTracks = try await !asset.loadTracks(withMediaType: .video).isEmpty
        return hasVideoTracks ? 0 : nil
    }

    /// Maps FluidAudio speaker IDs ("S1", "SPEAKER_00", ...) to stable Luxel-local
    /// IDs ("speaker-0", "speaker-1", ...) in first-seen order.
    static func normalizedOutput(from result: DiarizationResult) -> SpeakerDiarizationOutput {
        let sortedSegments = result.segments.sorted {
            if $0.startTimeSeconds == $1.startTimeSeconds {
                return $0.endTimeSeconds < $1.endTimeSeconds
            }

            return $0.startTimeSeconds < $1.startTimeSeconds
        }

        var idMap: [String: String] = [:]
        var segments: [SpeakerDiarizationSegment] = []
        for segment in sortedSegments {
            let start = TimeInterval(segment.startTimeSeconds)
            let end = TimeInterval(segment.endTimeSeconds)
            guard start.isFinite, end.isFinite, end > start else {
                continue
            }

            let localID: String
            if let existing = idMap[segment.speakerId] {
                localID = existing
            } else {
                localID = "speaker-\(idMap.count)"
                idMap[segment.speakerId] = localID
            }
            segments.append(SpeakerDiarizationSegment(speakerID: localID, start: start, end: end))
        }

        var speakerEmbeddings: [String: [Float]] = [:]
        for (speakerId, embedding) in result.speakerDatabase ?? [:] {
            guard let localID = idMap[speakerId] else {
                continue
            }

            speakerEmbeddings[localID] = embedding
        }

        return SpeakerDiarizationOutput(segments: segments, speakerEmbeddings: speakerEmbeddings)
    }
}
