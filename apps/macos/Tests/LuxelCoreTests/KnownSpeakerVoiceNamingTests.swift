import Foundation
import Testing

@testable import LuxelCore

// MARK: - Voice naming

@Suite("Speaker voice naming service")
struct SpeakerVoiceNamingServiceTests {
    private struct NamingFixture {
        let root: URL
        let audioURL: URL
        let profileID: UUID
        let profileStore: FileKnownSpeakerProfileStore
        let artifactsStore: SpeakerDiarizationArtifactsFileStore
    }

    @Test("attaching a voice to an already matched known speaker merges transcript labels")
    func attachingToExistingKnownSpeakerMergesLabels() async throws {
        let fixture = try makeNamingFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let transcript = try sampleMergeTranscript(profileID: fixture.profileID)
        let service = SpeakerVoiceNamingService(
            artifactsStore: fixture.artifactsStore,
            profileStore: fixture.profileStore
        )

        let updated = try await service.attach(
            speakerID: "speaker-1",
            toProfileWithID: fixture.profileID,
            transcript: transcript,
            audioURL: fixture.audioURL
        )

        #expect(updated.speakers.map(\.id) == ["speaker-0"])
        #expect(updated.speakers.map(\.displayName) == ["Jordan Smith"])
        #expect(updated.spans.map(\.speakerID) == ["speaker-0", "speaker-0"])
        #expect(updated.turns.map(\.speakerID) == ["speaker-0", "speaker-0"])

        let savedProfile = try #require(
            try fixture.profileStore.library().profiles.first { $0.id == fixture.profileID })
        #expect(savedProfile.embeddings.count == 2)

        let voices = service.detectedVoices(transcript: updated, audioURL: fixture.audioURL)
        let voice = try #require(voices.first)
        #expect(voices.count == 1)
        #expect(voice.totalSpeakingTime == 4)
        #expect(voice.turnCount == 2)
    }

    @Test("saving a duplicate name enrolls the voice into the existing profile")
    func savingDuplicateNameReusesExistingProfile() async throws {
        let fixture = try makeNamingFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let service = SpeakerVoiceNamingService(
            artifactsStore: fixture.artifactsStore,
            profileStore: fixture.profileStore
        )
        let result = try await service.saveAsNewKnownSpeaker(
            named: "  jordan   smith ",
            speakerID: "speaker-1",
            transcript: sampleMergeTranscript(profileID: fixture.profileID),
            audioURL: fixture.audioURL
        )

        #expect(result.profile.id == fixture.profileID)
        #expect(result.profile.displayName == "Jordan Smith")
        #expect(result.profile.embeddings.count == 2)
        #expect(result.transcript.speakers.map(\.id) == ["speaker-0"])
        #expect(result.transcript.spans.map(\.speakerID) == ["speaker-0", "speaker-0"])
        #expect(try fixture.profileStore.library().profiles.count == 1)
    }

    private func makeNamingFixture() throws -> NamingFixture {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "LuxelSpeakerNamingTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let audioURL = root.appending(path: "recording.m4a")
        try Data([0x00]).write(to: audioURL)

        let profileStore = FileKnownSpeakerProfileStore(
            directory: root.appending(path: "profiles", directoryHint: .isDirectory)
        )
        let artifactsStore = SpeakerDiarizationArtifactsFileStore(
            directory: root.appending(path: "artifacts", directoryHint: .isDirectory)
        )
        let profileID = UUID()
        try profileStore.save(
            KnownSpeakerProfile(
                id: profileID,
                displayName: "Jordan Smith",
                embeddings: [
                    try SpeakerEmbedding(
                        vector: [1, 0, 0],
                        modelIdentifier: "test-model",
                        backend: .fluidAudioWeSpeaker
                    )
                ]
            ))
        try artifactsStore.save(sampleMergeArtifacts(), audioURL: audioURL)

        return NamingFixture(
            root: root,
            audioURL: audioURL,
            profileID: profileID,
            profileStore: profileStore,
            artifactsStore: artifactsStore
        )
    }

    private func sampleMergeArtifacts() -> SpeakerDiarizationArtifacts {
        SpeakerDiarizationArtifacts(
            modelRevision: "test-model",
            tracks: [
                SpeakerDiarizationArtifacts.Track(
                    source: nil,
                    segments: [
                        SpeakerDiarizationSegment(speakerID: "speaker-0", start: 0, end: 1),
                        SpeakerDiarizationSegment(speakerID: "speaker-0", start: 1, end: 2),
                        SpeakerDiarizationSegment(speakerID: "speaker-1", start: 2, end: 3),
                        SpeakerDiarizationSegment(speakerID: "speaker-1", start: 3, end: 4)
                    ]
                )
            ],
            speakerEmbeddings: [
                "speaker-0": [1, 0, 0],
                "speaker-1": [0.95, 0.1, 0]
            ]
        )
    }

    private func sampleMergeTranscript(profileID: UUID) throws -> TurnSegmentedTranscript {
        try TurnSegmentedTranscript(
            spans: [
                try TimedTranscriptSpan(
                    id: "span-0",
                    text: "Known",
                    start: 0,
                    end: 2,
                    speakerID: "speaker-0"
                ),
                try TimedTranscriptSpan(
                    id: "span-1",
                    text: "Unknown",
                    start: 2,
                    end: 4,
                    speakerID: "speaker-1"
                )
            ],
            turns: [
                try TranscriptTurn(
                    id: "turn-0",
                    spanIDs: ["span-0"],
                    start: 0,
                    end: 2,
                    text: "Known",
                    speakerID: "speaker-0"
                ),
                try TranscriptTurn(
                    id: "turn-1",
                    spanIDs: ["span-1"],
                    start: 2,
                    end: 4,
                    text: "Unknown",
                    speakerID: "speaker-1"
                )
            ],
            localeIdentifier: "en_US",
            speakers: [
                try TranscriptSpeakerLabel(
                    id: "speaker-0",
                    displayName: "Jordan Smith",
                    knownSpeakerID: profileID
                ),
                try TranscriptSpeakerLabel(id: "speaker-1", displayName: "Speaker 2")
            ]
        )
    }
}
