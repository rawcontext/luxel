import Foundation
import Testing

@Suite("Architecture rules")
struct ArchitectureTests {
    @Test("Domain and application do not import macOS framework adapters")
    func coreLayersDoNotImportOuterFrameworks() throws {
        let packageRoot = try packageRootURL()
        let checkedDirectories = [
            packageRoot.appending(path: "Sources/LuxelCore/Domain"),
            packageRoot.appending(path: "Sources/LuxelCore/Application")
        ]
        let forbiddenImports = [
            "import AppKit",
            "import SwiftUI",
            "import ScreenCaptureKit",
            "import AVFoundation",
            "import AVKit",
            "import ImageIO",
            "import VideoToolbox",
            "import StoreKit",
            "import ServiceManagement"
        ]

        for directory in checkedDirectories {
            for fileURL in try swiftFiles(under: directory) {
                let contents = try String(contentsOf: fileURL, encoding: .utf8)
                for forbiddenImport in forbiddenImports {
                    #expect(!contents.contains(forbiddenImport), "\(fileURL.path) contains \(forbiddenImport)")
                }
            }
        }
    }

    @Test("recording session UX avoids media-key and system-state hacks")
    func recordingSessionUXAvoidsSystemStateHacks() throws {
        let sourceDirectory = try packageRootURL().appending(path: "Sources")
        let forbiddenSnippets = [
            "import MediaPlayer",
            "MPRemoteCommandCenter",
            "MPRemoteCommand",
            "MPNowPlayingInfoCenter",
            "remoteCommandCenter",
            "NX_KEYTYPE",
            "systemDefined",
            "com.apple.finder",
            "CreateDesktop",
            "killall Finder",
            "DoNotDisturb",
            "doNotDisturb",
            "com.apple.notificationcenterui"
        ]

        for fileURL in try swiftFiles(under: sourceDirectory) {
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            for forbiddenSnippet in forbiddenSnippets {
                #expect(!contents.contains(forbiddenSnippet), "\(fileURL.path) contains \(forbiddenSnippet)")
            }
        }
    }

    @Test("menu bar status is owned by one AppKit status item")
    func menuBarStatusIsOwnedByOneAppKitStatusItem() throws {
        let sourceDirectory = try packageRootURL().appending(path: "Sources/LuxelApp")
        var statusItemOccurrences = 0

        for fileURL in try swiftFiles(under: sourceDirectory) {
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            #expect(!contents.contains("MenuBarExtra"), "\(fileURL.path) reintroduces a second menu bar owner")
            statusItemOccurrences += contents.components(separatedBy: "NSStatusBar.system.statusItem").count - 1
        }

        #expect(statusItemOccurrences == 1)
    }

    @Test("menu bar status click stops active recording before opening popover")
    func menuBarStatusClickStopsActiveRecordingBeforeOpeningPopover() throws {
        let source = try String(
            contentsOf: packageRootURL().appending(path: "Sources/LuxelApp/App/LuxelStatusItemController.swift"),
            encoding: .utf8
        )

        #expect(source.contains("button.action = #selector(handleStatusItemClick)"))
        #expect(source.contains("if model.hasActiveRecording"))
        #expect(source.contains("stopRecordingFromStatusItem()"))
        #expect(source.contains("handleStatusItemStopWatchdog()"))
        #expect(source.contains("recoverInterruptedRecording()"))
        #expect(source.contains("windowPresenter.openEditor(fileURL: fileURL)"))
    }

    @Test("full display recording frame follows screen edge corners")
    func fullDisplayRecordingFrameFollowsScreenEdgeCorners() throws {
        let source = try String(
            contentsOf: packageRootURL().appending(path: "Sources/LuxelApp/Recording/RecordingFramePanelController.swift"),
            encoding: .utf8
        )

        #expect(source.contains("case fullDisplay(cornerRadii: RecordingFrameCornerRadii)"))
        #expect(source.contains("case .area where screen.map({ frame.matches($0.frame) }) == true"))
        #expect(source.contains("fullDisplayTopCornerRadius(screen: screen)"))
        #expect(source.contains("screen.auxiliaryTopLeftArea?.height"))
        #expect(source.contains("screen.auxiliaryTopRightArea?.height"))
        #expect(source.contains("RecordingFrameCornerRadii(top: topCornerRadius, bottom: bottomCornerRadius)"))
        #expect(source.contains("screen.safeAreaInsets.top"))
        #expect(source.contains("RecordingFrameDrawingView(style: style)"))
        #expect(source.contains("bounds.insetBy(dx: strokeWidth / 2, dy: strokeWidth / 2)"))
        #expect(source.contains("let topRadius = clampedRadius(cornerRadii.top, in: rect)"))
        #expect(source.contains("let bottomRadius = clampedRadius(cornerRadii.bottom, in: rect)"))
        #expect(source.contains("path.appendArc("))
    }

    @Test("cropper supports local selection undo and redo")
    func cropperSupportsLocalSelectionUndoAndRedo() throws {
        let packageRoot = try packageRootURL()
        let modelSource = try String(
            contentsOf: packageRoot.appending(path: "Sources/LuxelApp/Cropper/LuxelCropperModel.swift"),
            encoding: .utf8
        )
        let viewSource = try String(
            contentsOf: packageRoot.appending(path: "Sources/LuxelApp/Cropper/LuxelCropperView.swift"),
            encoding: .utf8
        )

        #expect(modelSource.contains("UndoStack<CropperUndoState>"))
        #expect(modelSource.contains("selection: CaptureRect?"))
        #expect(modelSource.contains("aspectRatioPreset: CaptureAspectRatioPreset"))
        #expect(modelSource.contains("customAspectRatio: CaptureAspectRatio?"))
        #expect(modelSource.contains("mode: LuxelCropperMode"))
        #expect(modelSource.contains("pushUndoState(coalescingToken: selectionDragCoalescingToken)"))
        #expect(modelSource.contains("pushUndoState(coalescingToken: resizeDragCoalescingToken)"))
        #expect(modelSource.contains("func applyCustomAspectRatio() -> Bool"))
        #expect(modelSource.contains("func undoSelectionChange()"))
        #expect(modelSource.contains("func redoSelectionChange()"))
        #expect(viewSource.contains("model.finishUpdateSelection()"))
        #expect(viewSource.contains("Picker(\"Mode\", selection: cropperMode)"))
        #expect(viewSource.contains("TextField(\"Custom W\", text: customAspectRatioWidthText)"))
        #expect(viewSource.contains("TextField(\"Custom H\", text: customAspectRatioHeightText)"))
        #expect(viewSource.contains("applyCustomAspectRatio()"))
        #expect(viewSource.contains("model.undoSelectionChange()"))
        #expect(viewSource.contains("model.redoSelectionChange()"))
        #expect(viewSource.contains(".keyboardShortcut(\"z\", modifiers: .command)"))
        #expect(viewSource.contains(".keyboardShortcut(\"z\", modifiers: [.command, .shift])"))
    }

    @Test("cropper renders snap guides while drawing selections")
    func cropperRendersSnapGuidesWhileDrawingSelections() throws {
        let packageRoot = try packageRootURL()
        let modelSource = try String(
            contentsOf: packageRoot.appending(path: "Sources/LuxelApp/Cropper/LuxelCropperModel.swift"),
            encoding: .utf8
        )
        let controllerSource = try String(
            contentsOf: packageRoot.appending(path: "Sources/LuxelApp/Cropper/LuxelCropperPanelController.swift"),
            encoding: .utf8
        )
        let viewSource = try String(
            contentsOf: packageRoot.appending(path: "Sources/LuxelApp/Cropper/LuxelCropperView.swift"),
            encoding: .utf8
        )

        #expect(modelSource.contains("var snapGuides: [CaptureSnapGuide]"))
        #expect(modelSource.contains("let windowSnapFrames: [CaptureRect]"))
        #expect(modelSource.contains("SnapResolver.resolve("))
        #expect(modelSource.contains("windowFrames: windowSnapFrames"))
        #expect(modelSource.contains("screenFrames: [try displaySnapFrame]"))
        #expect(modelSource.contains("snapGuides = snapResult.guides"))
        #expect(modelSource.contains("snapGuides = []"))
        #expect(controllerSource.contains("let targets = try await targetService.availableTargets()"))
        #expect(controllerSource.contains("CaptureWindowSnapFrameResolver.windowFrames("))
        #expect(viewSource.contains("snapGuidesOverlay(viewSize: geometry.size)"))
        #expect(viewSource.contains("ForEach(Array(model.snapGuides.enumerated())"))
        #expect(viewSource.contains("NSEvent.modifierFlags.contains(.command)"))
    }

    @Test("cropper restores last area selection when enabled")
    func cropperRestoresLastAreaSelectionWhenEnabled() throws {
        let packageRoot = try packageRootURL()
        let modelSource = try String(
            contentsOf: packageRoot.appending(path: "Sources/LuxelApp/Cropper/LuxelCropperModel.swift"),
            encoding: .utf8
        )
        let controllerSource = try String(
            contentsOf: packageRoot.appending(path: "Sources/LuxelApp/Cropper/LuxelCropperPanelController.swift"),
            encoding: .utf8
        )
        let controlsSource = try String(
            contentsOf: packageRoot.appending(path: "Sources/LuxelApp/MenuBar/LuxelRecordingControls.swift"),
            encoding: .utf8
        )
        let shortcutsSource = try String(
            contentsOf: packageRoot.appending(path: "Sources/LuxelApp/Shortcuts/LuxelShortcutInstaller.swift"),
            encoding: .utf8
        )
        let presentationSource = try String(
            contentsOf: packageRoot.appending(path: "Sources/LuxelApp/MenuBar/Model/LuxelMenuModel+Presentation.swift"),
            encoding: .utf8
        )

        #expect(modelSource.contains("struct CropperRestoreSelectionConfiguration"))
        #expect(modelSource.contains("memory?.restoredTopLeftSelection(in: display)"))
        #expect(modelSource.contains("initialSelection: CaptureRect? = nil"))
        #expect(modelSource.contains("selection: resolvedInitialSelection"))
        #expect(controllerSource.contains("restoreSelectionConfiguration: CropperRestoreSelectionConfiguration = .disabled"))
        #expect(controllerSource.contains("initialSelection: restoreSelectionConfiguration.selection(for: display)"))
        #expect(presentationSource.contains("isEnabled: settings.restoreLastSelection"))
        #expect(presentationSource.contains("memory: settings.lastCaptureMemory"))
        #expect(controlsSource.contains("restoreSelectionConfiguration: model.cropperRestoreSelectionConfiguration()"))
        #expect(shortcutsSource.contains("restoreSelectionConfiguration: model.cropperRestoreSelectionConfiguration()"))
    }

    @Test("cropper dims inactive displays when configured")
    func cropperDimsInactiveDisplaysWhenConfigured() throws {
        let packageRoot = try packageRootURL()
        let modelSource = try String(
            contentsOf: packageRoot.appending(path: "Sources/LuxelApp/Cropper/LuxelCropperModel.swift"),
            encoding: .utf8
        )
        let controllerSource = try String(
            contentsOf: packageRoot.appending(path: "Sources/LuxelApp/Cropper/LuxelCropperPanelController.swift"),
            encoding: .utf8
        )
        let viewSource = try String(
            contentsOf: packageRoot.appending(path: "Sources/LuxelApp/Cropper/LuxelCropperView.swift"),
            encoding: .utf8
        )
        let controlsSource = try String(
            contentsOf: packageRoot.appending(path: "Sources/LuxelApp/MenuBar/LuxelRecordingControls.swift"),
            encoding: .utf8
        )
        let shortcutsSource = try String(
            contentsOf: packageRoot.appending(path: "Sources/LuxelApp/Shortcuts/LuxelShortcutInstaller.swift"),
            encoding: .utf8
        )

        #expect(modelSource.contains("final class CropperDisplayFocus"))
        #expect(modelSource.contains("func dimsDisplay(_ displayID: DisplayID, dimOtherDisplays: Bool) -> Bool"))
        #expect(modelSource.contains("var isDimmedByOtherDisplay: Bool"))
        #expect(modelSource.contains("displayFocus.activate(display.id)"))
        #expect(modelSource.contains("displayFocus.clear(ifMatching: display.id)"))
        #expect(controllerSource.contains("let displayFocus = CropperDisplayFocus()"))
        #expect(controllerSource.contains("dimOtherDisplays: dimOtherDisplays"))
        #expect(viewSource.contains("Color.black.opacity(model.isDimmedByOtherDisplay ? 0.20 : 0.38)"))
        #expect(viewSource.contains("if let selection = model.selection, !model.isDimmedByOtherDisplay"))
        #expect(controlsSource.contains("dimOtherDisplays: model.settings.dimOtherDisplays"))
        #expect(shortcutsSource.contains("dimOtherDisplays: model.settings.dimOtherDisplays"))
    }

    @Test("recording FPS settings accept direct numeric entry")
    func recordingFPSSettingsAcceptDirectNumericEntry() throws {
        let packageRoot = try packageRootURL()
        let settingsSource = try String(
            contentsOf: packageRoot.appending(path: "Sources/LuxelApp/Settings/LuxelSettingsView.swift"),
            encoding: .utf8
        )
        let requestSource = try String(
            contentsOf: packageRoot.appending(path: "Sources/LuxelApp/MenuBar/Model/LuxelMenuModel+RecordingRequests.swift"),
            encoding: .utf8
        )

        #expect(settingsSource.contains("TextField("))
        #expect(settingsSource.contains("value: recordingFrameRateSelection"))
        #expect(settingsSource.contains("formatter: recordingFrameRateFormatter"))
        #expect(settingsSource.contains("try model.settings.setRecordingFrameRate(frameRate)"))
        #expect(settingsSource.contains("Use a whole number from 1 to 60 FPS."))
        #expect(requestSource.contains("let frameRate = settings.recordingFrameRate"))
        #expect(!requestSource.contains("settings.record60FPS ? 60 : 30"))
    }

    @Test("update settings milestone does not link Sparkle yet")
    func updateSettingsMilestoneDoesNotLinkSparkleYet() throws {
        let packageRoot = try packageRootURL()
        let checkedURLs = [packageRoot.appending(path: "Package.swift")]
            + (try swiftFiles(under: packageRoot.appending(path: "Sources")))
        let forbiddenSnippets = [
            ".package(url: \"https://github.com/sparkle-project/Sparkle\"",
            "import Sparkle",
            "SPUUpdater",
            "SPUStandardUpdaterController",
            "SUUpdater"
        ]

        for fileURL in checkedURLs {
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            for forbiddenSnippet in forbiddenSnippets {
                #expect(!contents.contains(forbiddenSnippet), "\(fileURL.path) contains \(forbiddenSnippet)")
            }
        }
    }

    private func swiftFiles(under directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            return []
        }

        return try enumerator.compactMap { item in
            let url = try #require(item as? URL)
            guard url.pathExtension == "swift" else {
                return nil
            }

            return url
        }
    }

    private func packageRootURL() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "Tests" {
            let next = url.deletingLastPathComponent()
            try #require(next.path != url.path)
            url = next
        }

        return url.deletingLastPathComponent()
    }
}
