import Foundation

public final class TranscriptTitleTrigger: @unchecked Sendable {
    private struct Track {
        let spans: [TimedTranscriptSpan]
        let completed: Bool
    }

    private let lock = NSLock()
    private let trackIDs: Set<Int>
    private let localeIdentifier: String
    private let onReady: @Sendable (String) -> Void
    private var tracks: [Int: Track] = [:]
    private var emitted = false

    public init(trackIDs: [Int?], localeIdentifier: String, onReady: @escaping @Sendable (String) -> Void) {
        self.trackIDs = Set(trackIDs.map { $0 ?? -1 })
        self.localeIdentifier = localeIdentifier
        self.onReady = onReady
    }

    public func receive(trackID: Int?, spans: [TimedTranscriptSpan], completed: Bool) {
        let text = lock.withLock { () -> String? in
            guard !emitted else { return nil }
            tracks[trackID ?? -1] = Track(spans: spans, completed: completed)
            guard trackIDs.allSatisfy({ tracks[$0] != nil }) else { return nil }
            let ordered = trackIDs.sorted().compactMap { tracks[$0] }
            let finished = ordered.allSatisfy(\.completed)
            let frontier = ordered.map { $0.completed ? Double.infinity : ($0.spans.last?.end ?? 0) }.min() ?? 0
            let ready = ordered.flatMap(\.spans).filter { $0.end <= frontier }.sorted { $0.start < $1.start }
            let unique = CrossSourceEchoTranscriptFilter.removingEcho(from: ready)
            let prefix = RecordingTitlePolicy.prefix(spans: unique, localeIdentifier: localeIdentifier)
            guard prefix.wordCount >= RecordingTitlePolicy.maximumWords || finished else { return nil }
            emitted = true
            return prefix.text
        }
        if let text { onReady(text) }
    }
}
