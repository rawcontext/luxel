import Foundation
import LuxelCore
import Testing

@Suite("Screenshot capture planner")
struct ScreenshotCapturePlannerTests {
    private let planner = ScreenshotCapturePlanner()

    @Test("planner creates file backed screenshot job")
    func plannerCreatesFileBackedScreenshotJob() throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-06-12T15:15:30Z"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: -5 * 60 * 60))

        let job = try planner.captureJob(
            target: .display(DisplayID(42)),
            includeCursor: false,
            format: .heic,
            destinations: [.clipboard, .file],
            outputDirectory: URL(fileURLWithPath: "/tmp/Luxel"),
            now: now,
            calendar: calendar
        )

        #expect(job.request == (try ScreenshotRequest(
            target: .display(DisplayID(42)),
            includeCursor: false,
            format: .heic
        )))
        #expect(job.destinations == [.clipboard, .file])
        #expect(job.outputFileURL == URL(fileURLWithPath: "/tmp/Luxel/Luxel 2026-06-12 at 10.15.30.heic"))
        #expect(job.historyName == "Luxel 2026-06-12 at 10.15.30")
    }

    @Test("planner skips output file for clipboard only screenshots")
    func plannerSkipsOutputFileForClipboardOnlyScreenshots() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))

        let job = try planner.captureJob(
            target: .window(id: 7),
            includeCursor: true,
            format: .png,
            destinations: [.clipboard],
            outputDirectory: URL(fileURLWithPath: "/tmp/Luxel"),
            now: Date(timeIntervalSince1970: 0),
            calendar: calendar,
            scale: .points
        )

        #expect(job.request == (try ScreenshotRequest(
            target: .window(id: 7),
            includeCursor: true,
            scale: .points,
            format: .png
        )))
        #expect(job.outputFileURL == nil)
        #expect(job.historyName == "Luxel 1970-01-01 at 00.00.00")
    }

    @Test("planner keeps area screenshot targets")
    func plannerKeepsAreaScreenshotTargets() throws {
        let rect = try CaptureRect(x: 120, y: 240, width: 640, height: 360)
        let target = CaptureTarget.area(displayID: DisplayID(9), rect: rect)

        let job = try planner.captureJob(
            target: target,
            includeCursor: true,
            format: .png,
            destinations: [.clipboard],
            outputDirectory: URL(fileURLWithPath: "/tmp/Luxel"),
            now: Date(timeIntervalSince1970: 0)
        )

        #expect(job.request.target == target)
    }

    @Test("planner applies configured backdrop only to window screenshots")
    func plannerAppliesConfiguredBackdropOnlyToWindowScreenshots() throws {
        let windowJob = try planner.captureJob(
            target: .window(id: 7),
            includeCursor: true,
            format: .png,
            destinations: [.clipboard],
            outputDirectory: URL(fileURLWithPath: "/tmp/Luxel"),
            now: Date(timeIntervalSince1970: 0),
            backdrop: .transparentWithShadow
        )
        let displayJob = try planner.captureJob(
            target: .display(DisplayID(9)),
            includeCursor: true,
            format: .png,
            destinations: [.clipboard],
            outputDirectory: URL(fileURLWithPath: "/tmp/Luxel"),
            now: Date(timeIntervalSince1970: 0),
            backdrop: .transparentWithShadow
        )

        #expect(windowJob.request.backdrop == .transparentWithShadow)
        #expect(displayJob.request.backdrop == .opaque)
    }
}
