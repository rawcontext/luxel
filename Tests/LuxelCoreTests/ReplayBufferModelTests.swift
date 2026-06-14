import Foundation
import LuxelCore
import Testing

@Suite("Replay buffer models")
struct ReplayBufferModelTests {
    @Test("default configuration matches settings plan")
    func defaultConfigurationMatchesSettingsPlan() {
        let configuration = ReplayBufferConfiguration.defaults

        #expect(configuration.bufferLength == 60)
        #expect(configuration.source == .displayWithCursor)
        #expect(configuration.frameRate.framesPerSecond == 30)
        #expect(!configuration.includeSystemAudio)
        #expect(configuration.quality == .balanced)
    }

    @Test("configuration validates buffer length and quality")
    func configurationValidatesBufferLengthAndQuality() throws {
        let frameRate = try FrameRate(30)
        let configuration = try ReplayBufferConfiguration(
            bufferLength: 60,
            source: .displayWithCursor,
            frameRate: frameRate,
            includeSystemAudio: true,
            quality: .high
        )

        #expect(configuration.bufferLength == 60)
        #expect(configuration.source == .displayWithCursor)
        #expect(configuration.frameRate == frameRate)
        #expect(configuration.includeSystemAudio)
        #expect(configuration.quality == .high)

        #expect(throws: ReplayBufferModelError.invalidBufferLength) {
            _ = try ReplayBufferConfiguration(
                bufferLength: 9,
                source: .display(DisplayID(1)),
                frameRate: FrameRate(30)
            )
        }
        #expect(throws: ReplayBufferModelError.invalidBufferLength) {
            _ = try ReplayBufferConfiguration(
                bufferLength: 601,
                source: .displayWithCursor,
                frameRate: FrameRate(30)
            )
        }
        #expect(throws: ReplayBufferModelError.invalidBufferLength) {
            _ = try ReplayBufferConfiguration(
                bufferLength: .infinity,
                source: .displayWithCursor,
                frameRate: FrameRate(30)
            )
        }
        #expect(throws: ReplayBufferModelError.invalidQuality) {
            _ = try ReplayBufferConfiguration(
                bufferLength: 60,
                source: .displayWithCursor,
                frameRate: FrameRate(30),
                quality: .lossless
            )
        }
    }

    @Test("clip destinations expose settings labels")
    func clipDestinationsExposeSettingsLabels() {
        #expect(ReplayClipDestination.editor.label == "Editor")
        #expect(ReplayClipDestination.quickExport.label == "Quick Export")
    }

    @Test("segments validate start and duration")
    func segmentsValidateStartAndDuration() throws {
        let segment = try ReplayBufferSegment(id: "s0", start: 0, duration: 2)

        #expect(segment.id == "s0")
        #expect(segment.start == 0)
        #expect(segment.duration == 2)
        #expect(segment.end == 2)
        #expect(try segment.timeRange == TimeRange(start: 0, end: 2))

        #expect(throws: ReplayBufferModelError.invalidSegmentStart) {
            _ = try ReplayBufferSegment(id: "bad", start: -1, duration: 2)
        }
        #expect(throws: ReplayBufferModelError.invalidSegmentStart) {
            _ = try ReplayBufferSegment(id: "bad", start: .infinity, duration: 2)
        }
        #expect(throws: ReplayBufferModelError.invalidSegmentDuration) {
            _ = try ReplayBufferSegment(id: "bad", start: 0, duration: 0)
        }
        #expect(throws: ReplayBufferModelError.invalidSegmentDuration) {
            _ = try ReplayBufferSegment(id: "bad", start: 0, duration: .infinity)
        }
    }

    @Test("ledger evicts old segments while keeping one segment of slack")
    func ledgerEvictsOldSegmentsWhileKeepingSlack() throws {
        var ledger = try SegmentLedger(bufferLength: 6)

        for index in 0..<6 {
            ledger = try ledger.appending(segment(index, start: TimeInterval(index * 2)))
        }

        #expect(ledger.segments.map(\.id) == ["s2", "s3", "s4", "s5"])
        #expect(ledger.segments.map(\.start) == [4, 6, 8, 10])
    }

    @Test("ledger selects segments covering requested clip and trim offset")
    func ledgerSelectsSegmentsCoveringRequestedClipAndTrimOffset() throws {
        var ledger = try SegmentLedger(bufferLength: 6)
        for index in 0..<6 {
            ledger = try ledger.appending(segment(index, start: TimeInterval(index * 2)))
        }

        let coverage = try ledger.segmentsCovering(lastSeconds: 5)

        #expect(coverage.segments.map(\.id) == ["s3", "s4", "s5"])
        #expect(coverage.requestedDuration == 5)
        #expect(coverage.coveredDuration == 5)
        #expect(coverage.trimStartOffset == 1)
        #expect(try ledger.exactTrimStart(for: 5) == 1)
        #expect(!coverage.isShort)
    }

    @Test("ledger reports short clips when buffer has less media than requested")
    func ledgerReportsShortClipsWhenBufferHasLessMediaThanRequested() throws {
        var ledger = try SegmentLedger(bufferLength: 60)
        ledger = try ledger.appending(segment(0, start: 10))
        ledger = try ledger.appending(segment(1, start: 12))

        let coverage = try ledger.segmentsCovering(lastSeconds: 10)

        #expect(coverage.segments.map(\.id) == ["s0", "s1"])
        #expect(coverage.coveredDuration == 4)
        #expect(coverage.trimStartOffset == 0)
        #expect(coverage.isShort)
    }

    @Test("empty ledger returns empty short coverage")
    func emptyLedgerReturnsEmptyShortCoverage() throws {
        let ledger = try SegmentLedger(bufferLength: 60)

        let coverage = try ledger.segmentsCovering(lastSeconds: 30)

        #expect(coverage.segments.isEmpty)
        #expect(coverage.coveredDuration == 0)
        #expect(coverage.trimStartOffset == nil)
        #expect(coverage.isShort)
        #expect(try ledger.exactTrimStart(for: 30) == nil)
    }

    @Test("ledger rejects invalid clip durations and overlapping segments")
    func ledgerRejectsInvalidClipDurationsAndOverlappingSegments() throws {
        let first = try segment(0, start: 0, duration: 3)
        let overlapping = try segment(1, start: 2, duration: 2)

        #expect(throws: ReplayBufferModelError.invalidSegmentOrder) {
            _ = try SegmentLedger(bufferLength: 6, segments: [first, overlapping])
        }

        let ledger = try SegmentLedger(bufferLength: 6, segments: [first])
        #expect(throws: ReplayBufferModelError.invalidSegmentOrder) {
            _ = try ledger.appending(overlapping)
        }
        #expect(throws: ReplayBufferModelError.invalidClipDuration) {
            _ = try ledger.segmentsCovering(lastSeconds: 0)
        }
        #expect(throws: ReplayBufferModelError.invalidClipDuration) {
            _ = try ledger.segmentsCovering(lastSeconds: .infinity)
        }
    }

    private func segment(
        _ index: Int,
        start: TimeInterval,
        duration: TimeInterval = 2
    ) throws -> ReplayBufferSegment {
        try ReplayBufferSegment(id: "s\(index)", start: start, duration: duration)
    }
}
