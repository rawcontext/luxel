import Foundation
import LuxelCore
import Testing

@Suite("Recording schedule")
struct RecordingScheduleTests {
    @Test("schedule validates countdown and recorded duration limits")
    func scheduleValidatesLimits() throws {
        let schedule = try RecordingSchedule(countdown: 3, maxRecordedDuration: 60)

        #expect(schedule.countdown == 3)
        #expect(schedule.maxRecordedDuration == 60)

        #expect(throws: RecordingScheduleError.invalidCountdown) {
            _ = try RecordingSchedule(countdown: 0)
        }
        #expect(throws: RecordingScheduleError.invalidCountdown) {
            _ = try RecordingSchedule(countdown: 61)
        }
        #expect(throws: RecordingScheduleError.invalidMaxRecordedDuration) {
            _ = try RecordingSchedule(maxRecordedDuration: 0)
        }
        #expect(throws: RecordingScheduleError.invalidMaxRecordedDuration) {
            _ = try RecordingSchedule(maxRecordedDuration: 43_201)
        }
    }

    @Test("timelapse options derive capture interval and video duration")
    func timelapseOptionsDeriveTiming() throws {
        let options = try TimelapseOptions(
            speedFactor: 30,
            playbackFrameRate: FrameRate(30)
        )

        #expect(options.captureInterval == 1)
        #expect(options.videoDuration(forWallDuration: 120) == 4)

        #expect(throws: RecordingScheduleError.invalidTimelapseSpeed) {
            _ = try TimelapseOptions(speedFactor: 1.9, playbackFrameRate: FrameRate(30))
        }
        #expect(throws: RecordingScheduleError.invalidTimelapseSpeed) {
            _ = try TimelapseOptions(speedFactor: 240.1, playbackFrameRate: FrameRate(30))
        }
        #expect(throws: RecordingScheduleError.invalidTimelapseSpeed) {
            _ = try TimelapseOptions(speedFactor: .infinity, playbackFrameRate: FrameRate(30))
        }
    }

    @Test("duration text parses stop-after input")
    func durationTextParsesStopAfterInput() throws {
        #expect(try RecordingDurationText.parse("45") == 45)
        #expect(try RecordingDurationText.parse("1:30") == 90)
        #expect(try RecordingDurationText.parse("2:03:04") == 7_384)
        #expect(try RecordingDurationText.parse(" 12:00:00 ") == 43_200)
    }

    @Test("duration text rejects invalid stop-after input")
    func durationTextRejectsInvalidStopAfterInput() {
        #expect(throws: RecordingDurationTextError.invalidFormat) {
            _ = try RecordingDurationText.parse("")
        }
        #expect(throws: RecordingDurationTextError.invalidFormat) {
            _ = try RecordingDurationText.parse("1::00")
        }
        #expect(throws: RecordingDurationTextError.invalidFormat) {
            _ = try RecordingDurationText.parse("1:60")
        }
        #expect(throws: RecordingDurationTextError.invalidFormat) {
            _ = try RecordingDurationText.parse("1:00:60")
        }
        #expect(throws: RecordingDurationTextError.invalidDuration) {
            _ = try RecordingDurationText.parse("0")
        }
        #expect(throws: RecordingDurationTextError.invalidDuration) {
            _ = try RecordingDurationText.parse("12:00:01")
        }
    }

    @Test("duration text formats stop-after input")
    func durationTextFormatsStopAfterInput() {
        #expect(RecordingDurationText.format(45) == "0:45")
        #expect(RecordingDurationText.format(90) == "1:30")
        #expect(RecordingDurationText.format(7_384) == "2:03:04")
    }

    @Test("recording clock excludes paused wall time from elapsed duration")
    func recordingClockExcludesPausedWallTime() {
        let start = Date(timeIntervalSince1970: 1_000)
        let clock = RecordingClock(
            startedAt: start,
            events: [
                .pause(at: start.addingTimeInterval(10)),
                .resume(at: start.addingTimeInterval(25))
            ]
        )

        #expect(clock.elapsedRecordedTime(at: start.addingTimeInterval(40)) == 25)
        #expect(clock.isRecording(at: start.addingTimeInterval(20)) == false)
        #expect(clock.isRecording(at: start.addingTimeInterval(30)))
    }

    @Test("recording clock reports remaining duration and active deadline")
    func recordingClockReportsRemainingDurationAndDeadline() throws {
        let start = Date(timeIntervalSince1970: 2_000)
        let now = start.addingTimeInterval(30)
        let clock = RecordingClock(startedAt: start)
        let schedule = try RecordingSchedule(maxRecordedDuration: 60)

        #expect(clock.remainingRecordedTime(for: schedule, at: now) == 30)
        #expect(clock.timerFireDate(for: schedule, at: now) == now.addingTimeInterval(30))
    }

    @Test("recording clock suspends deadline while paused")
    func recordingClockSuspendsDeadlineWhilePaused() throws {
        let start = Date(timeIntervalSince1970: 3_000)
        let pausedAt = start.addingTimeInterval(50)
        let resumedAt = start.addingTimeInterval(90)
        let schedule = try RecordingSchedule(maxRecordedDuration: 60)
        let pausedClock = RecordingClock(
            startedAt: start,
            events: [
                .pause(at: pausedAt)
            ]
        )
        let resumedClock = RecordingClock(
            startedAt: start,
            events: [
                .pause(at: pausedAt),
                .resume(at: resumedAt)
            ]
        )

        #expect(pausedClock.elapsedRecordedTime(at: start.addingTimeInterval(80)) == 50)
        #expect(
            pausedClock.remainingRecordedTime(for: schedule, at: start.addingTimeInterval(80)) == 10)
        #expect(pausedClock.timerFireDate(for: schedule, at: start.addingTimeInterval(80)) == nil)
        #expect(
            resumedClock.timerFireDate(for: schedule, at: resumedAt) == resumedAt.addingTimeInterval(10))
    }

    @Test("recording clock fires immediately once recorded duration reaches limit")
    func recordingClockFiresImmediatelyAtLimit() throws {
        let start = Date(timeIntervalSince1970: 4_000)
        let now = start.addingTimeInterval(61)
        let clock = RecordingClock(startedAt: start)
        let schedule = try RecordingSchedule(maxRecordedDuration: 60)

        #expect(clock.remainingRecordedTime(for: schedule, at: now) == 0)
        #expect(clock.timerFireDate(for: schedule, at: now) == now)
    }
}
