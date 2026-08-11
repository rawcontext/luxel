import Foundation
import Testing

extension ArchitectureTests {
    @Test("menu bar status is owned by one AppKit status item")
    func menuBarStatusIsOwnedByOneAppKitStatusItem() throws {
        let sourceDirectory = try packageRootURL().appending(path: "Sources/LuxelApp")
        var statusItemOccurrences = 0

        for fileURL in try swiftFiles(under: sourceDirectory) {
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            #expect(
                !contents.contains("MenuBarExtra"), "\(fileURL.path) reintroduces a second menu bar owner")
            statusItemOccurrences +=
                contents.components(separatedBy: "NSStatusBar.system.statusItem").count - 1
        }

        #expect(statusItemOccurrences == 1)
    }

    @Test("app startup exits duplicate menu bar instances")
    func appStartupExitsDuplicateMenuBarInstances() throws {
        let source = try String(
            contentsOf: packageRootURL().appending(path: "Sources/LuxelApp/App/LuxelApp.swift"),
            encoding: .utf8
        )

        #expect(source.contains("LuxelSingleInstanceGuard.exitDuplicateInstanceIfNeeded()"))
        #expect(
            source.contains(
                "NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)"))
        #expect(source.contains("application.processIdentifier != currentProcessIdentifier"))
        #expect(source.contains("Darwin.exit(0)"))
    }

    @Test("menu bar status interactions preserve recording stop and quick actions")
    func menuBarStatusInteractionsPreserveRecordingStopAndQuickActions() throws {
        let source = try sourceText(
            for: [
                "Sources/LuxelApp/App/LuxelStatusItemController.swift",
                "Sources/LuxelApp/App/LuxelStatusItemController+Rendering.swift",
                "Sources/LuxelApp/App/LuxelStatusItemController+Actions.swift",
                "Sources/LuxelApp/App/LuxelStatusItemController+Popover.swift",
                "Sources/LuxelApp/App/LuxelStatusItemController+QuickActions.swift"
            ],
            encoding: .utf8
        )

        #expect(source.contains("button.action = #selector(handleStatusItemClick)"))
        #expect(source.contains("button.sendAction(on: [.leftMouseUp, .rightMouseUp])"))
        #expect(!source.contains("button.sendAction(on: [.leftMouseDown])"))
        #expect(source.contains("configureStatusItemButton(button)"))
        #expect(source.contains("statusItem.autosaveName"))
        #expect(source.contains("Bundle.main.bundleIdentifier"))
        #expect(source.contains(".statusItem"))
        #expect(source.contains("if model.hasActiveRecording"))
        #expect(source.contains("stopRecordingFromStatusItem()"))
        #expect(source.contains("NSApp.currentEvent?.type == .rightMouseUp"))
        #expect(source.contains("showStatusItemQuickActionsMenu()"))
        #expect(source.contains("setStatusItemLength(activeStatusItemWidth"))
        #expect(
            source.contains(
                "if let button = statusItem.button {\n"
                    + "                configureStatusItemButton(button)"))
        #expect(source.contains("button.accessibilityFrame()"))
        #expect(source.contains("func activeStatusItemWidth"))
        #expect(source.contains("makeActiveRecordingFrame"))
        #expect(source.contains("watchAudioLevels(onlyWhenRecording: true)"))
        #expect(source.contains("handleStatusItemStopWatchdog()"))
        #expect(source.contains("DispatchQueue.main.async { [weak self]"))
        #expect(source.contains("Task { @MainActor [weak self]"))
        #expect(source.contains("startStatusItemStopTask()"))
        #expect(source.contains("recoverInterruptedRecording()"))
        #expect(source.contains("windowPresenter.openEditor(fileURL: fileURL)"))
    }

    @Test("recording does not draw a screen border overlay")
    func recordingDoesNotDrawScreenBorderOverlay() throws {
        let source = try String(
            contentsOf: packageRootURL().appending(
                path: "Sources/LuxelApp/Recording/Panels/RecordingFramePanelController.swift"),
            encoding: .utf8
        )

        #expect(!source.contains("NSPanel"))
        #expect(!source.contains("RecordingFrameDrawingView"))
        #expect(!source.contains("NSColor.red"))
        #expect(!source.contains("path.stroke()"))
        #expect(source.contains("window.isReleasedWhenClosed = false"))
        #expect(!source.contains("window?.close()"))
    }

    @Test("screen recorder avoids system recording output status item")
    func screenRecorderAvoidsSystemRecordingOutputStatusItem() throws {
        let source = try sourceContents(
            under: packageRootURL().appending(path: "Sources/LuxelCore/Infrastructure/Capture")
        )

        #expect(!source.contains("SCRecordingOutput"))
        #expect(!source.contains("addRecordingOutput"))
        #expect(source.contains("addStreamOutput"))
        #expect(source.contains("AVAssetWriter"))
    }

    @Test("screen recorder waits for the first written sample before stopping")
    func screenRecorderWaitsForFirstWrittenSampleBeforeStopping() throws {
        let packageRoot = try packageRootURL()
        let recorderSource = try String(
            contentsOf: packageRoot.appending(
                path: "Sources/LuxelCore/Infrastructure/Capture/ScreenCaptureKitRecorder.swift"),
            encoding: .utf8
        )
        let writerSource = try sourceText(for: [
            "Sources/LuxelCore/Infrastructure/Capture/ScreenCaptureKitRecordingWriter.swift",
            "Sources/LuxelCore/Infrastructure/Capture/ReplayBufferCaptureSupport.swift"
        ])

        #expect(recorderSource.contains("waitForCurrentSegmentToStartWritingIfNeeded()"))
        #expect(recorderSource.contains("initialSampleWaitAttempts"))
        #expect(writerSource.contains("hasStartedCurrentSegmentWriting()"))
        #expect(writerSource.contains("var hasStartedWriting: Bool"))
        #expect(writerSource.contains("[[AnyHashable: Any]]"))
        #expect(writerSource.contains("AnyHashable(SCStreamFrameInfo.status.rawValue)"))
        #expect(writerSource.contains("NSNumber"))
    }

    @Test("screen recorder retains writer segment through finish completion")
    func screenRecorderRetainsWriterSegmentThroughFinishCompletion() throws {
        let writerSource = try sourceText(for: [
            "Sources/LuxelCore/Infrastructure/Capture/ScreenCaptureKitRecordingWriter.swift",
            "Sources/LuxelCore/Infrastructure/Capture/ScreenCaptureKitRecordingWriterSupport.swift"
        ])

        #expect(
            writerSource.contains(
                "RecordingWriterFinishCompletion(\n"
                    + "            segment: self"))
        #expect(writerSource.contains("private let segment: RecordingWriterSegment"))
        #expect(writerSource.contains("withExtendedLifetime(segment)"))
    }
}
