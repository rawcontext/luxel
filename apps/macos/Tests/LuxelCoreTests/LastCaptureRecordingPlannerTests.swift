import Foundation
import LuxelCore
import Testing

@Suite("Last capture recording planner")
struct LastCaptureRecordingPlannerTests {
    private let planner = LastCaptureRecordingPlanner()

    @Test("missing memory throws missing last capture")
    func missingMemoryThrowsMissingLastCapture() throws {
        #expect(throws: LastCaptureRecordingPlannerError.missingLastCapture) {
            try planner.recordingRequest(
                from: nil,
                availableTargets: [],
                outputFileURL: URL(fileURLWithPath: "/tmp/repeat.mp4")
            )
        }
    }

    @Test("unavailable target throws target unavailable")
    func unavailableTargetThrowsTargetUnavailable() throws {
        let memory = try makeMemory(
            target: .display(DisplayID(99)),
            pixelSize: PixelSize(width: 1920, height: 1080)
        )

        #expect(throws: LastCaptureRecordingPlannerError.targetUnavailable) {
            try planner.recordingRequest(
                from: memory,
                availableTargets: [],
                outputFileURL: URL(fileURLWithPath: "/tmp/repeat.mp4")
            )
        }
    }

    @Test("area target keeps previous options when display is still available")
    func areaTargetKeepsPreviousOptionsWhenDisplayIsStillAvailable() throws {
        let displayID = DisplayID(3)
        let rect = try CaptureRect(x: 10, y: 20, width: 640, height: 480)
        let outputFileURL = URL(fileURLWithPath: "/tmp/repeat.mp4")
        let camera = CameraRecordingOptions(
            deviceID: "camera-1",
            isEnabled: true,
            recordsSeparateTrack: false,
            previewStyle: CameraPreviewStyle(shape: .cutout, size: .small, isMirrored: false)
        )
        let memory = LastCaptureMemory(
            target: .area(displayID: displayID, rect: rect),
            pixelSize: try PixelSize(width: 640, height: 480),
            options: RecordingOptions(
                frameRate: 60,
                captureRect: rect,
                showCursor: false,
                highlightClicks: true,
                captureKeystrokes: true,
                camera: camera,
                displayID: displayID,
                audio: .systemAndMicrophone(deviceID: "mic-1"),
                videoCodec: .hevc
            ),
            capturedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        let request = try planner.recordingRequest(
            from: memory,
            availableTargets: [try makeDisplayOption(id: displayID.rawValue)],
            outputFileURL: outputFileURL
        )

        #expect(request.target == memory.target)
        #expect(request.outputFileURL == outputFileURL)
        #expect(request.pixelSize == memory.pixelSize)
        #expect(request.frameRate.framesPerSecond == 60)
        #expect(!request.showCursor)
        #expect(request.highlightClicks)
        #expect(request.captureKeystrokes)
        #expect(request.camera == camera)
        #expect(request.audio == .systemAndMicrophone(deviceID: "mic-1"))
        #expect(request.videoCodec == .hevc)
        #expect(request.captureKind == .standard)
    }

    @Test("quick repeat overrides capture kind")
    func quickRepeatOverridesCaptureKind() throws {
        let presetID = UUID(uuidString: "00000000-0000-0000-0000-000000000401")!
        let display = try makeDisplayOption(id: 1)
        let memory = try makeMemory(target: display.target, pixelSize: display.pixelSize)

        let request = try planner.recordingRequest(
            from: memory,
            availableTargets: [display],
            outputFileURL: URL(fileURLWithPath: "/tmp/repeat.mp4"),
            captureKind: .quick(presetID: presetID)
        )

        #expect(request.captureKind == .quick(presetID: presetID))
        #expect(request.recordingOptions.captureKind == .quick(presetID: presetID))
    }

    @Test("stale window uses fallback window before display")
    func staleWindowUsesFallbackWindowBeforeDisplay() throws {
        let fallbackWindow = try makeWindowOption(id: 7)
        let fallbackDisplay = try makeDisplayOption(id: 1)
        let memory = try makeMemory(
            target: .window(id: 99),
            pixelSize: PixelSize(width: 800, height: 600)
        )

        let request = try planner.recordingRequest(
            from: memory,
            availableTargets: [fallbackDisplay],
            fallbackWindow: fallbackWindow,
            fallbackDisplay: fallbackDisplay,
            outputFileURL: URL(fileURLWithPath: "/tmp/repeat.mp4")
        )

        #expect(request.target == fallbackWindow.target)
        #expect(request.pixelSize == fallbackWindow.pixelSize)
    }

    @Test("stale display uses fallback display")
    func staleDisplayUsesFallbackDisplay() throws {
        let fallbackDisplay = try makeDisplayOption(id: 1)
        let memory = try makeMemory(
            target: .display(DisplayID(99)),
            pixelSize: PixelSize(width: 1920, height: 1080)
        )

        let request = try planner.recordingRequest(
            from: memory,
            availableTargets: [fallbackDisplay],
            fallbackDisplay: fallbackDisplay,
            outputFileURL: URL(fileURLWithPath: "/tmp/repeat.mp4")
        )

        #expect(request.target == fallbackDisplay.target)
        #expect(request.pixelSize == fallbackDisplay.pixelSize)
    }

    private func makeMemory(
        target: CaptureTarget,
        pixelSize: PixelSize
    ) throws -> LastCaptureMemory {
        LastCaptureMemory(
            target: target,
            pixelSize: pixelSize,
            options: RecordingOptions(frameRate: 30),
            capturedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    private func makeWindowOption(id: UInt32) throws -> CaptureTargetOption {
        try CaptureTargetOption(
            id: "window-\(id)",
            kind: .window,
            title: "Window \(id)",
            target: .window(id: id),
            pixelSize: PixelSize(width: 800, height: 600),
            frame: CaptureRect(x: 0, y: 0, width: 800, height: 600)
        )
    }

    private func makeDisplayOption(id: UInt32) throws -> CaptureTargetOption {
        try CaptureTargetOption(
            id: "display-\(id)",
            kind: .display,
            title: "Display \(id)",
            target: .display(DisplayID(id)),
            pixelSize: PixelSize(width: 1920, height: 1080),
            frame: CaptureRect(x: 0, y: 0, width: 1920, height: 1080)
        )
    }
}
