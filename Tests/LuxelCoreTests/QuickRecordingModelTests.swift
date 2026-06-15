import Foundation
import LuxelCore
import Testing

@Suite("Quick recording models")
struct QuickRecordingModelTests {
    @Test("recording request carries quick capture kind into persisted options")
    func recordingRequestCarriesQuickCaptureKindIntoPersistedOptions() throws {
        let presetID = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
        let request = try RecordingRequest(
            target: .display(DisplayID(5)),
            outputFileURL: URL(fileURLWithPath: "/tmp/luxel.mp4"),
            pixelSize: PixelSize(width: 1280, height: 720),
            frameRate: FrameRate(30),
            captureKind: .quick(presetID: presetID)
        )

        #expect(request.captureKind == .quick(presetID: presetID))
        #expect(request.recordingOptions.captureKind == .quick(presetID: presetID))
    }

    @Test("last capture memory can be created from a recording request")
    func lastCaptureMemoryCanBeCreatedFromRecordingRequest() throws {
        let request = try RecordingRequest(
            target: .area(
                displayID: DisplayID(9),
                rect: CaptureRect(x: 10, y: 20, width: 640, height: 480)
            ),
            outputFileURL: URL(fileURLWithPath: "/tmp/luxel.mp4"),
            pixelSize: PixelSize(width: 640, height: 480),
            frameRate: FrameRate(60),
            showCursor: false,
            highlightClicks: true,
            camera: CameraRecordingOptions(deviceID: "camera-1", isEnabled: true),
            audio: .system
        )
        let capturedAt = Date(timeIntervalSince1970: 1_800_000_000)

        let memory = LastCaptureMemory(request: request, capturedAt: capturedAt)

        #expect(memory.target == request.target)
        #expect(memory.pixelSize == request.pixelSize)
        #expect(memory.options == request.recordingOptions)
        #expect(memory.capturedAt == capturedAt)
    }

    @Test("recording options decode missing capture kind as standard")
    func recordingOptionsDecodeMissingCaptureKindAsStandard() throws {
        let payload = """
        {
            "frameRate": 30
        }
        """.data(using: .utf8)!

        let options = try JSONDecoder().decode(RecordingOptions.self, from: payload)

        #expect(options.captureKind == .standard)
        #expect(!options.captureKeystrokes)
        #expect(options.camera == nil)
    }

    @Test("last capture memory resolves exact window target")
    func lastCaptureMemoryResolvesExactWindowTarget() throws {
        let window = try makeWindowOption(id: 42)
        let memory = LastCaptureMemory(
            target: window.target,
            pixelSize: window.pixelSize,
            options: RecordingOptions(frameRate: 30),
            capturedAt: Date()
        )

        let resolved = memory.resolvedTarget(
            availableTargets: [try makeWindowOption(id: 7), window],
            fallbackDisplay: try makeDisplayOption(id: 1)
        )

        #expect(resolved?.target == window.target)
        #expect(resolved?.pixelSize == window.pixelSize)
    }

    @Test("missing window target falls back to supplied frontmost window then display")
    func missingWindowTargetFallsBackToSuppliedFrontmostWindowThenDisplay() throws {
        let memory = try LastCaptureMemory(
            target: .window(id: 99),
            pixelSize: PixelSize(width: 800, height: 600),
            options: RecordingOptions(frameRate: 30),
            capturedAt: Date()
        )
        let fallbackWindow = try makeWindowOption(id: 7)
        let fallbackDisplay = try makeDisplayOption(id: 1)

        let windowResolution = memory.resolvedTarget(
            availableTargets: [fallbackDisplay],
            fallbackWindow: fallbackWindow,
            fallbackDisplay: fallbackDisplay
        )
        let displayResolution = memory.resolvedTarget(
            availableTargets: [fallbackDisplay],
            fallbackDisplay: fallbackDisplay
        )

        #expect(windowResolution?.target == fallbackWindow.target)
        #expect(windowResolution?.pixelSize == fallbackWindow.pixelSize)
        #expect(displayResolution?.target == fallbackDisplay.target)
        #expect(displayResolution?.pixelSize == fallbackDisplay.pixelSize)
    }

    @Test("area target is preserved while owning display still exists")
    func areaTargetIsPreservedWhileOwningDisplayStillExists() throws {
        let rect = try CaptureRect(x: 10, y: 20, width: 640, height: 480)
        let target = CaptureTarget.area(displayID: DisplayID(3), rect: rect)
        let pixelSize = try PixelSize(width: 640, height: 480)
        let memory = LastCaptureMemory(
            target: target,
            pixelSize: pixelSize,
            options: RecordingOptions(frameRate: 30),
            capturedAt: Date()
        )

        let resolved = memory.resolvedTarget(
            availableTargets: [try makeDisplayOption(id: 3)],
            fallbackDisplay: try makeDisplayOption(id: 1)
        )

        #expect(resolved?.target == target)
        #expect(resolved?.pixelSize == pixelSize)
    }

    @Test("last area memory restores matching display cropper selection")
    func lastAreaMemoryRestoresMatchingDisplayCropperSelection() throws {
        let memory = LastCaptureMemory(
            target: .area(
                displayID: DisplayID(3),
                rect: try CaptureRect(x: 10, y: 20, width: 640, height: 480)
            ),
            pixelSize: try PixelSize(width: 640, height: 480),
            options: RecordingOptions(frameRate: 30),
            capturedAt: Date()
        )
        let display = try DisplayBounds(id: DisplayID(3), x: 0, y: 0, width: 1920, height: 1080)

        let selection = memory.restoredTopLeftSelection(in: display)

        #expect(selection == (try CaptureRect(x: 10, y: 580, width: 640, height: 480)))
    }

    @Test("last display memory restores matching full cropper selection")
    func lastDisplayMemoryRestoresMatchingFullCropperSelection() throws {
        let memory = LastCaptureMemory(
            target: .display(DisplayID(3)),
            pixelSize: try PixelSize(width: 1920, height: 1080),
            options: RecordingOptions(frameRate: 30),
            capturedAt: Date()
        )
        let display = try DisplayBounds(id: DisplayID(3), x: 0, y: 0, width: 1920, height: 1080)

        let selection = memory.restoredTopLeftSelection(in: display)

        #expect(selection == (try CaptureRect(x: 0, y: 0, width: 1920, height: 1080)))
    }

    @Test("last window memory restores matching window cropper selection")
    func lastWindowMemoryRestoresMatchingWindowCropperSelection() throws {
        let windowFrame = try CaptureRect(x: -1600, y: 220, width: 640, height: 480)
        let window = try makeWindowOption(id: 42, frame: windowFrame)
        let memory = LastCaptureMemory(
            target: window.target,
            pixelSize: window.pixelSize,
            options: RecordingOptions(frameRate: 30),
            capturedAt: Date()
        )
        let display = try DisplayBounds(id: DisplayID(3), x: -1728, y: 120, width: 1728, height: 1117)

        let selection = memory.restoredTopLeftSelection(in: display, availableTargets: [window])

        #expect(selection == (try CaptureRect(x: 128, y: 100, width: 640, height: 480)))
    }

    @Test("last nonmatching memory does not restore cropper selection")
    func lastNonmatchingMemoryDoesNotRestoreCropperSelection() throws {
        let display = try DisplayBounds(id: DisplayID(3), x: 0, y: 0, width: 1920, height: 1080)
        let windowMemory = LastCaptureMemory(
            target: .window(id: 42),
            pixelSize: try PixelSize(width: 640, height: 480),
            options: RecordingOptions(frameRate: 30),
            capturedAt: Date()
        )
        let otherDisplayMemory = LastCaptureMemory(
            target: .area(
                displayID: DisplayID(4),
                rect: try CaptureRect(x: 10, y: 20, width: 640, height: 480)
            ),
            pixelSize: try PixelSize(width: 640, height: 480),
            options: RecordingOptions(frameRate: 30),
            capturedAt: Date()
        )

        #expect(windowMemory.restoredTopLeftSelection(in: display) == nil)
        #expect(otherDisplayMemory.restoredTopLeftSelection(in: display) == nil)
    }

    @Test("missing display target falls back to supplied main display")
    func missingDisplayTargetFallsBackToSuppliedMainDisplay() throws {
        let memory = try LastCaptureMemory(
            target: .display(DisplayID(99)),
            pixelSize: PixelSize(width: 1920, height: 1080),
            options: RecordingOptions(frameRate: 30),
            capturedAt: Date()
        )
        let fallbackDisplay = try makeDisplayOption(id: 1)

        let resolved = memory.resolvedTarget(
            availableTargets: [fallbackDisplay],
            fallbackDisplay: fallbackDisplay
        )

        #expect(resolved?.target == fallbackDisplay.target)
        #expect(resolved?.pixelSize == fallbackDisplay.pixelSize)
    }

    @Test("missing target without fallback returns nil")
    func missingTargetWithoutFallbackReturnsNil() throws {
        let memory = try LastCaptureMemory(
            target: .display(DisplayID(99)),
            pixelSize: PixelSize(width: 1920, height: 1080),
            options: RecordingOptions(frameRate: 30),
            capturedAt: Date()
        )

        #expect(memory.resolvedTarget(availableTargets: []) == nil)
    }

    private func makeWindowOption(id: UInt32, frame: CaptureRect? = nil) throws -> CaptureTargetOption {
        let resolvedFrame: CaptureRect
        if let frame {
            resolvedFrame = frame
        } else {
            resolvedFrame = try CaptureRect(x: 0, y: 0, width: 800, height: 600)
        }

        return try CaptureTargetOption(
            id: "window-\(id)",
            kind: .window,
            title: "Window \(id)",
            target: .window(id: id),
            pixelSize: PixelSize(width: resolvedFrame.width, height: resolvedFrame.height),
            frame: resolvedFrame
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
