import Foundation

public struct SpeakerVoiceExampleRange: Equatable, Hashable, Sendable {
    public let start: TimeInterval
    public let duration: TimeInterval
    public let audioTrackIndex: Int?

    public init(start: TimeInterval, duration: TimeInterval, audioTrackIndex: Int? = nil) {
        self.start = start
        self.duration = duration
        self.audioTrackIndex = audioTrackIndex
    }
}

public struct DetectedSpeakerVoice: Equatable, Identifiable, Sendable {
    public let label: TranscriptSpeakerLabel
    public let totalSpeakingTime: TimeInterval
    public let turnCount: Int
    public let exampleRanges: [SpeakerVoiceExampleRange]
    public let hasEmbedding: Bool

    public var id: String { label.id }

    public init(
        label: TranscriptSpeakerLabel,
        totalSpeakingTime: TimeInterval,
        turnCount: Int,
        exampleRanges: [SpeakerVoiceExampleRange],
        hasEmbedding: Bool
    ) {
        self.label = label
        self.totalSpeakingTime = totalSpeakingTime
        self.turnCount = turnCount
        self.exampleRanges = exampleRanges
        self.hasEmbedding = hasEmbedding
    }
}

/// Editor-facing operations for the detected-voices workflow: summarize the
/// voices in a diarized recording, save or attach them to the local
/// known-speaker library, and reset incorrect matches back to anonymous.
public struct SpeakerVoiceNamingService: Sendable {
    public static let maximumExampleClips = 3
    public static let minimumExampleClipDuration: TimeInterval = 1.5
    public static let maximumExampleClipDuration: TimeInterval = 8

    private let artifactsStore: any SpeakerDiarizationArtifactsStore
    private let profileStore: any KnownSpeakerProfileStore
    private let segmentExporter: AVFoundationAudioSegmentExporter
    private let backend: SpeakerEmbeddingBackend
    private let temporaryDirectory: URL

    public init(
        artifactsStore: any SpeakerDiarizationArtifactsStore,
        profileStore: any KnownSpeakerProfileStore,
        segmentExporter: AVFoundationAudioSegmentExporter = AVFoundationAudioSegmentExporter(),
        backend: SpeakerEmbeddingBackend = .fluidAudioWeSpeaker,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) {
        self.artifactsStore = artifactsStore
        self.profileStore = profileStore
        self.segmentExporter = segmentExporter
        self.backend = backend
        self.temporaryDirectory = temporaryDirectory
    }

    public func knownSpeakers() throws -> KnownSpeakerLibrary {
        try profileStore.library()
    }

    public func detectedVoices(
        transcript: TurnSegmentedTranscript,
        audioURL: URL
    ) -> [DetectedSpeakerVoice] {
        let artifacts = try? artifactsStore.load(audioURL: audioURL)
        return transcript.speakers.map { label in
            let segments = artifacts?.segments(for: label.id) ?? []
            let trackIndex = artifacts?.tracks
                .first { track in track.segments.contains { $0.speakerID == label.id } }?
                .audioTrackIndex
            let turnSpeakingTime = transcript.turns
                .filter { $0.speakerID == label.id }
                .reduce(0) { $0 + ($1.end - $1.start) }
            let artifactSpeakingTime = segments.reduce(0) { $0 + $1.duration }
            let speakingTime =
                segments.isEmpty ? turnSpeakingTime : max(artifactSpeakingTime, turnSpeakingTime)

            return DetectedSpeakerVoice(
                label: label,
                totalSpeakingTime: speakingTime,
                turnCount: transcript.turns.count { $0.speakerID == label.id },
                exampleRanges: Self.exampleRanges(from: segments, audioTrackIndex: trackIndex),
                hasEmbedding: artifacts?.speakerEmbeddings[label.id] != nil
            )
        }
    }

    public func saveAsNewKnownSpeaker(
        named name: String,
        speakerID: String,
        transcript: TurnSegmentedTranscript,
        audioURL: URL
    ) async throws -> (transcript: TurnSegmentedTranscript, profile: KnownSpeakerProfile) {
        let embedding = try enrollmentEmbedding(speakerID: speakerID, audioURL: audioURL)
        let clips = await exampleClips(speakerID: speakerID, audioURL: audioURL)
        let profile = try KnownSpeakerProfile(
            displayName: name,
            embeddings: [embedding],
            exampleClips: clips,
            matchedRecordingCount: 1,
            lastMatchedAt: Date()
        )
        let library = try profileStore.save(profile)
        guard
            let savedProfile = library.profiles.first(where: {
                $0.embeddings.contains { $0.id == embedding.id }
            })
        else {
            throw KnownSpeakerError.profileNotFound(profile.id)
        }

        let updated = try assigning(
            speakerID: speakerID,
            to: savedProfile,
            in: transcript
        )
        return (updated, savedProfile)
    }

    public func attach(
        speakerID: String,
        toProfileWithID profileID: UUID,
        transcript: TurnSegmentedTranscript,
        audioURL: URL
    ) async throws -> TurnSegmentedTranscript {
        guard var profile = try profileStore.library().profiles.first(where: { $0.id == profileID })
        else {
            throw KnownSpeakerError.profileNotFound(profileID)
        }

        // Corrections become additional enrollment examples so matching improves.
        if let embedding = try? enrollmentEmbedding(speakerID: speakerID, audioURL: audioURL) {
            profile.embeddings.append(embedding)
        }
        profile.exampleClips.append(
            contentsOf: await exampleClips(speakerID: speakerID, audioURL: audioURL))
        profile.matchedRecordingCount += 1
        profile.lastMatchedAt = Date()
        profile.updatedAt = Date()
        try profileStore.save(profile)

        return try assigning(speakerID: speakerID, to: profile, in: transcript)
    }

    private func assigning(
        speakerID: String,
        to profile: KnownSpeakerProfile,
        in transcript: TurnSegmentedTranscript
    ) throws -> TurnSegmentedTranscript {
        let updatedLabel = try TranscriptSpeakerLabel(
            id: speakerID,
            displayName: profile.displayName,
            knownSpeakerID: profile.id
        )
        let updatedTranscript = try transcript.replacingSpeakerLabel(updatedLabel)

        guard
            let existingSpeakerID = updatedTranscript.speakers.first(where: {
                $0.id != speakerID && $0.knownSpeakerID == profile.id
            })?.id
        else {
            return updatedTranscript
        }
        return try updatedTranscript.mergingSpeaker(id: speakerID, into: existingSpeakerID)
    }

    public func resetToAnonymous(
        speakerID: String,
        transcript: TurnSegmentedTranscript
    ) throws -> TurnSegmentedTranscript {
        guard let index = transcript.speakers.firstIndex(where: { $0.id == speakerID }) else {
            throw TranscriptModelError.unknownSpeaker(speakerID)
        }

        return try transcript.replacingSpeakerLabel(
            TranscriptSpeakerLabel(
                id: speakerID,
                displayName: LuxelLocalization.format("Speaker %d", index + 1),
                knownSpeakerID: nil
            ))
    }

    private func enrollmentEmbedding(speakerID: String, audioURL: URL) throws -> SpeakerEmbedding {
        guard
            let artifacts = try? artifactsStore.load(audioURL: audioURL),
            let vector = artifacts.speakerEmbeddings[speakerID]
        else {
            throw KnownSpeakerError.invalidEmbedding
        }

        return try SpeakerEmbedding(
            vector: vector,
            modelIdentifier: artifacts.modelRevision ?? "unknown",
            modelRevision: artifacts.modelRevision,
            backend: backend
        )
    }

    private func exampleClips(
        speakerID: String,
        audioURL: URL
    ) async -> [KnownSpeakerExampleClip] {
        guard let artifacts = try? artifactsStore.load(audioURL: audioURL) else {
            return []
        }

        let ranges = Self.exampleRanges(
            from: artifacts.segments(for: speakerID),
            audioTrackIndex: artifacts.tracks
                .first { track in track.segments.contains { $0.speakerID == speakerID } }?
                .audioTrackIndex
        )

        var clips: [KnownSpeakerExampleClip] = []
        for range in ranges {
            let temporaryURL =
                temporaryDirectory
                .appending(path: "LuxelSpeakerClip-\(UUID().uuidString).m4a")
            defer { try? FileManager.default.removeItem(at: temporaryURL) }
            guard
                (try? await segmentExporter.exportSegment(
                    from: audioURL,
                    start: range.start,
                    duration: range.duration,
                    audioTrackIndex: range.audioTrackIndex,
                    to: temporaryURL
                )) != nil,
                let clip = try? profileStore.importExampleClip(
                    from: temporaryURL,
                    duration: range.duration,
                    sourceRecordingURL: audioURL
                )
            else {
                continue
            }

            clips.append(clip)
        }

        return clips
    }

    /// Picks clean, high-confidence example ranges: the longest non-overlapping
    /// diarization segments, clamped to a short audition length.
    static func exampleRanges(
        from segments: [SpeakerDiarizationSegment],
        audioTrackIndex: Int?
    ) -> [SpeakerVoiceExampleRange] {
        segments
            .filter { $0.duration >= minimumExampleClipDuration }
            .sorted { $0.duration > $1.duration }
            .prefix(maximumExampleClips)
            .sorted { $0.start < $1.start }
            .map {
                SpeakerVoiceExampleRange(
                    start: $0.start,
                    duration: min($0.duration, maximumExampleClipDuration),
                    audioTrackIndex: audioTrackIndex
                )
            }
    }
}
