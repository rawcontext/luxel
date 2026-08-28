import Foundation
import LuxelCore

final class KeyedMemoryTranscriptCache: TranscriptCache, @unchecked Sendable {
    private var storage: [String: TurnSegmentedTranscript] = [:]
    private(set) var savedRequests: [AudioTranscriptRequest] = []

    func load(for request: AudioTranscriptRequest) throws -> TurnSegmentedTranscript? {
        storage[key(for: request)]
    }

    func save(_ transcript: TurnSegmentedTranscript, for request: AudioTranscriptRequest) throws {
        savedRequests.append(request)
        storage[key(for: request)] = transcript
    }

    private func key(for request: AudioTranscriptRequest) -> String {
        [
            request.audioURL.path,
            request.locale.identifier,
            request.turnSegmentationMode.rawValue,
            request.speakerDiarizationMode.rawValue,
            request.speakerModelRevision ?? "",
            request.speakerLibraryRevision ?? "",
            request.speakerDiarizationMode == .enabled
                ? request.speakerCountHint.cacheIdentifier : ""
        ].joined(separator: "|")
    }
}
