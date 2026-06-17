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
}

extension ArchitectureTests {
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

    @Test("permission UX avoids private macOS privacy state edits")
    func permissionUXAvoidsPrivatePrivacyStateEdits() throws {
        let sourceDirectory = try packageRootURL().appending(path: "Sources")
        let forbiddenSnippets = [
            "TCC.db",
            "ScreenCaptureApprovals.plist",
            "tccutil reset",
            "systemsetup -setusingnetworktime",
            "systemsetup -setdate",
            "systemsetup -settime",
            "systemstatusd"
        ]

        for fileURL in try swiftFiles(under: sourceDirectory) {
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            for forbiddenSnippet in forbiddenSnippets {
                #expect(!contents.contains(forbiddenSnippet), "\(fileURL.path) contains \(forbiddenSnippet)")
            }
        }
    }

    @Test("screen permission status check does not touch ScreenCaptureKit")
    func screenPermissionStatusCheckDoesNotTouchScreenCaptureKit() throws {
        let source = try String(
            contentsOf: packageRootURL().appending(path: "Sources/LuxelCore/Infrastructure/System/ApplePermissionClient.swift"),
            encoding: .utf8
        )

        #expect(source.contains("CGPreflightScreenCaptureAccess() ? .authorized : .notDetermined"))
        #expect(source.contains("CGRequestScreenCaptureAccess()"))
        #expect(!source.contains("import ScreenCaptureKit"))
        #expect(!source.contains("SCShareableContent.current"))
    }

    @Test("status item startup does not enumerate capture targets")
    func statusItemStartupDoesNotEnumerateCaptureTargets() throws {
        let source = try String(
            contentsOf: packageRootURL().appending(path: "Sources/LuxelApp/App/LuxelStatusItemController.swift"),
            encoding: .utf8
        )
        let startupRange = try #require(source.range(of: "private func startNotchSurface()"))
        let nextFunctionRange = try #require(source[startupRange.upperBound...].range(of: "private func "))
        let startupSource = source[startupRange.lowerBound..<nextFunctionRange.lowerBound]

        #expect(startupSource.contains("await model.refreshPermissions()"))
        #expect(!startupSource.contains("refreshCaptureTargets()"))
    }

    @Test("notch surface stays dormant until screen permission is authorized")
    func notchSurfaceStaysDormantUntilScreenPermissionIsAuthorized() throws {
        let source = try String(
            contentsOf: packageRootURL().appending(path: "Sources/LuxelApp/MenuBar/Models/LuxelMenuModel+Notch.swift"),
            encoding: .utf8
        )

        #expect(source.contains("private var canUseScreenDependentNotchAction: Bool"))
        #expect(source.contains("screenRecordingStatus == .authorized"))
        #expect(source.contains("presentPermissionPrompt(forSource: .screenPixels)"))
        #expect(source.contains(
            "case .idle:\n"
                + "            guard screenRecordingStatus == .authorized else {\n"
                + "                return .dormant\n"
                + "            }"
        ))
        #expect(source.contains(
            "case .failed(let message):\n"
                + "            guard screenRecordingStatus == .authorized else {\n"
                + "                return .dormant\n"
                + "            }"
        ))
    }

    @Test("notch action icons expose hover tooltips")
    func notchActionIconsExposeHoverTooltips() throws {
        let source = try String(
            contentsOf: packageRootURL().appending(path: "Sources/LuxelApp/Notch/Panels/OverlayPanelNotchPresenter.swift"),
            encoding: .utf8
        )

        #expect(source.contains("@State private var hoveredActionID: NotchActivityActionID?"))
        #expect(source.contains("private func notchActionTooltip(for action: NotchActivityActionDescriptor) -> some View"))
        #expect(source.contains(".help(Text(action.title))"))
        #expect(source.contains(".onHover { isHovered in"))
    }

    @Test("system audio footer off state toggles without permission prompt")
    func systemAudioFooterOffStateTogglesWithoutPermissionPrompt() throws {
        let source = try String(
            contentsOf: packageRootURL().appending(path: "Sources/LuxelApp/MenuBar/Views/LuxelMenu.swift"),
            encoding: .utf8
        )
        let handlerRange = try #require(source.range(of: "private func handleSystemAudioFooterAction"))
        let nextHandlerRange = try #require(source[handlerRange.upperBound...].range(of: "private func handleMicrophoneFooterAction"))
        let handlerSource = String(source[handlerRange.lowerBound..<nextHandlerRange.lowerBound])

        #expect(handlerSource.contains("case .offByUser:\n            model.settings.recordSystemAudio = true\n            model.saveSettings()"))
        #expect(!handlerSource.contains("case .offByUser:\n            presentPermissionPrompt(.systemAudio)"))
    }

    @Test("permission prompts are hosted outside transient SwiftUI menu surfaces")
    func permissionPromptsAreHostedOutsideTransientSwiftUIMenuSurfaces() throws {
        let packageRoot = try packageRootURL()
        let statusItemSource = try String(
            contentsOf: packageRoot.appending(path: "Sources/LuxelApp/App/LuxelStatusItemController.swift"),
            encoding: .utf8
        )
        let menuSource = try String(
            contentsOf: packageRoot.appending(path: "Sources/LuxelApp/MenuBar/Views/LuxelMenu.swift"),
            encoding: .utf8
        )
        let settingsSource = try String(
            contentsOf: packageRoot.appending(path: "Sources/LuxelApp/Settings/Views/LuxelSettingsView.swift"),
            encoding: .utf8
        )

        #expect(statusItemSource.contains("private func presentPendingPermissionPromptIfNeeded()"))
        #expect(statusItemSource.contains("let alert = NSAlert()"))
        #expect(statusItemSource.contains("let primaryButton = alert.addButton(withTitle: prompt.guidance.actionTitle)"))
        #expect(statusItemSource.contains("primaryButton.keyEquivalent = \"\\r\""))
        #expect(statusItemSource.contains("presentPermissionPrompt(model.makePermissionPrompt(forSource: source))"))
        #expect(!menuSource.contains("isPresented: permissionPromptPresented"))
        #expect(!settingsSource.contains("isPresented: permissionPromptPresented"))
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

    @Test("app startup exits duplicate menu bar instances")
    func appStartupExitsDuplicateMenuBarInstances() throws {
        let source = try String(
            contentsOf: packageRootURL().appending(path: "Sources/LuxelApp/App/LuxelApp.swift"),
            encoding: .utf8
        )

        #expect(source.contains("LuxelSingleInstanceGuard.exitDuplicateInstanceIfNeeded()"))
        #expect(source.contains("NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)"))
        #expect(source.contains("application.processIdentifier != currentProcessIdentifier"))
        #expect(source.contains("Darwin.exit(0)"))
    }

    @Test("menu bar status click stops active recording before opening popover")
    func menuBarStatusClickStopsActiveRecordingBeforeOpeningPopover() throws {
        let source = try String(
            contentsOf: packageRootURL().appending(path: "Sources/LuxelApp/App/LuxelStatusItemController.swift"),
            encoding: .utf8
        )

        #expect(source.contains("button.action = #selector(handleStatusItemClick)"))
        #expect(source.contains("button.sendAction(on: [.leftMouseDown])"))
        #expect(source.contains("configureStatusItemButton(button)"))
        #expect(source.contains("statusItem.autosaveName"))
        #expect(source.contains("media.luxel.app.statusItem"))
        #expect(source.contains("if model.hasActiveRecording"))
        #expect(source.contains("stopRecordingFromStatusItem()"))
        #expect(source.contains("setStatusItemLength(activeStatusItemWidth"))
        #expect(source.contains("if let button = statusItem.button {\n            configureStatusItemButton(button)"))
        #expect(source.contains("button.accessibilityFrame()"))
        #expect(source.contains("private func activeStatusItemWidth"))
        #expect(source.contains("makeActiveRecordingFrame"))
        #expect(source.contains("watchAudioLevels(onlyWhenRecording: true)"))
        #expect(source.contains("handleStatusItemStopWatchdog()"))
        #expect(source.contains("recoverInterruptedRecording()"))
        #expect(source.contains("windowPresenter.openEditor(fileURL: fileURL)"))
    }

    @Test("recording does not draw a screen border overlay")
    func recordingDoesNotDrawScreenBorderOverlay() throws {
        let source = try String(
            contentsOf: packageRootURL().appending(path: "Sources/LuxelApp/Recording/Panels/RecordingFramePanelController.swift"),
            encoding: .utf8
        )

        #expect(!source.contains("NSPanel"))
        #expect(!source.contains("RecordingFrameDrawingView"))
        #expect(!source.contains("NSColor.red"))
        #expect(!source.contains("path.stroke()"))
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
            contentsOf: packageRoot.appending(path: "Sources/LuxelCore/Infrastructure/Capture/ScreenCaptureKitRecorder.swift"),
            encoding: .utf8
        )
        let writerSource = try String(
            contentsOf: packageRoot.appending(path: "Sources/LuxelCore/Infrastructure/Capture/ScreenCaptureKitRecordingWriter.swift"),
            encoding: .utf8
        )

        #expect(recorderSource.contains("waitForCurrentSegmentToStartWritingIfNeeded()"))
        #expect(recorderSource.contains("initialSampleWaitAttempts"))
        #expect(writerSource.contains("hasStartedCurrentSegmentWriting()"))
        #expect(writerSource.contains("var hasStartedWriting: Bool"))
        #expect(writerSource.contains("[[AnyHashable: Any]]"))
        #expect(writerSource.contains("AnyHashable(SCStreamFrameInfo.status.rawValue)"))
        #expect(writerSource.contains("NSNumber"))
    }

    @Test("cropper supports local selection undo and redo")
    func cropperSupportsLocalSelectionUndoAndRedo() throws {
        let packageRoot = try packageRootURL()
        let modelSource = try String(
            contentsOf: packageRoot.appending(path: "Sources/LuxelApp/Cropper/Models/LuxelCropperModel.swift"),
            encoding: .utf8
        )
        let viewSource = try sourceContents(under: packageRoot.appending(path: "Sources/LuxelApp/Cropper/Views"))

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
            contentsOf: packageRoot.appending(path: "Sources/LuxelApp/Cropper/Models/LuxelCropperModel.swift"),
            encoding: .utf8
        )
        let controllerSource = try String(
            contentsOf: packageRoot.appending(path: "Sources/LuxelApp/Cropper/Panels/LuxelCropperPanelController.swift"),
            encoding: .utf8
        )
        let viewSource = try sourceContents(under: packageRoot.appending(path: "Sources/LuxelApp/Cropper/Views"))

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
        #expect(viewSource.contains("let flags = NSEvent.modifierFlags"))
        #expect(viewSource.contains("flags.contains(.command)"))
    }

    @Test("cropper restores last area selection when enabled")
    func cropperRestoresLastAreaSelectionWhenEnabled() throws {
        let packageRoot = try packageRootURL()
        let modelSource = try String(
            contentsOf: packageRoot.appending(path: "Sources/LuxelApp/Cropper/Models/LuxelCropperModel.swift"),
            encoding: .utf8
        )
        let controllerSource = try String(
            contentsOf: packageRoot.appending(path: "Sources/LuxelApp/Cropper/Panels/LuxelCropperPanelController.swift"),
            encoding: .utf8
        )
        let menuSource = try String(
            contentsOf: packageRoot.appending(path: "Sources/LuxelApp/MenuBar/Views/LuxelMenu.swift"),
            encoding: .utf8
        )
        let shortcutsSource = try String(
            contentsOf: packageRoot.appending(path: "Sources/LuxelApp/Shortcuts/LuxelShortcutInstaller.swift"),
            encoding: .utf8
        )
        let presentationSource = try String(
            contentsOf: packageRoot.appending(path: "Sources/LuxelApp/MenuBar/Models/LuxelMenuModel+Presentation.swift"),
            encoding: .utf8
        )

        #expect(modelSource.contains("struct CropperRestoreSelectionConfiguration"))
        #expect(modelSource.contains("memory?.restoredTopLeftSelection(in: display, availableTargets: targets)"))
        #expect(modelSource.contains("initialSelection: CaptureRect? = nil"))
        #expect(modelSource.contains("selection: resolvedInitialSelection"))
        #expect(controllerSource.contains("restoreSelectionConfiguration: CropperRestoreSelectionConfiguration = .disabled"))
        #expect(
            controllerSource.contains(
                "initialSelection: presentation.restoreSelectionConfiguration.selection(for: display, targets: targets)"
            )
        )
        #expect(presentationSource.contains("isEnabled: settings.restoreLastSelection"))
        #expect(presentationSource.contains("memory: settings.lastCaptureMemory"))
        #expect(menuSource.contains("restoreSelectionConfiguration: model.cropperRestoreSelectionConfiguration()"))
        #expect(shortcutsSource.contains("restoreSelectionConfiguration: model.cropperRestoreSelectionConfiguration()"))
    }

    @Test("cropper dims inactive displays when configured")
    func cropperDimsInactiveDisplaysWhenConfigured() throws {
        let packageRoot = try packageRootURL()
        let modelSource = try String(
            contentsOf: packageRoot.appending(path: "Sources/LuxelApp/Cropper/Models/LuxelCropperModel.swift"),
            encoding: .utf8
        )
        let controllerSource = try String(
            contentsOf: packageRoot.appending(path: "Sources/LuxelApp/Cropper/Panels/LuxelCropperPanelController.swift"),
            encoding: .utf8
        )
        let viewSource = try sourceContents(under: packageRoot.appending(path: "Sources/LuxelApp/Cropper/Views"))
        let menuSource = try String(
            contentsOf: packageRoot.appending(path: "Sources/LuxelApp/MenuBar/Views/LuxelMenu.swift"),
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
        #expect(menuSource.contains("dimOtherDisplays: model.settings.dimOtherDisplays"))
        #expect(shortcutsSource.contains("dimOtherDisplays: model.settings.dimOtherDisplays"))
    }

    @Test("cropper shows loupe during precision selection")
    func cropperShowsLoupeDuringPrecisionSelection() throws {
        let packageRoot = try packageRootURL()
        let modelSource = try String(
            contentsOf: packageRoot.appending(path: "Sources/LuxelApp/Cropper/Models/LuxelCropperModel.swift"),
            encoding: .utf8
        )
        let controllerSource = try String(
            contentsOf: packageRoot.appending(path: "Sources/LuxelApp/Cropper/Panels/LuxelCropperPanelController.swift"),
            encoding: .utf8
        )
        let viewSource = try sourceContents(under: packageRoot.appending(path: "Sources/LuxelApp/Cropper/Views"))
        let menuSource = try String(
            contentsOf: packageRoot.appending(path: "Sources/LuxelApp/MenuBar/Views/LuxelMenu.swift"),
            encoding: .utf8
        )
        let shortcutsSource = try String(
            contentsOf: packageRoot.appending(path: "Sources/LuxelApp/Shortcuts/LuxelShortcutInstaller.swift"),
            encoding: .utf8
        )

        #expect(modelSource.contains("var loupeSample: CaptureLoupeSample?"))
        #expect(modelSource.contains("let loupeAlwaysOn: Bool"))
        #expect(modelSource.contains("CaptureLoupeSampleResolver.sample("))
        #expect(modelSource.contains("loupeSample = nil"))
        #expect(controllerSource.contains("loupeAlwaysOn: Bool = false"))
        #expect(controllerSource.contains("loupeAlwaysOn: loupeAlwaysOn"))
        #expect(viewSource.contains("struct CropperLoupeView"))
        #expect(viewSource.contains("struct CropperLoupeGrid"))
        #expect(viewSource.contains("let isLoupeRequested = flags.contains(.option)"))
        #expect(viewSource.contains("isSnappingDisabled: flags.contains(.command) || isLoupeActive"))
        #expect(menuSource.contains("loupeAlwaysOn: model.settings.loupeAlwaysOn"))
        #expect(shortcutsSource.contains("loupeAlwaysOn: model.settings.loupeAlwaysOn"))
    }

    @Test("recording FPS settings accept direct numeric entry")
    func recordingFPSSettingsAcceptDirectNumericEntry() throws {
        let packageRoot = try packageRootURL()
        let settingsSource = try String(
            contentsOf: packageRoot.appending(path: "Sources/LuxelApp/Settings/Views/LuxelSettingsView.swift"),
            encoding: .utf8
        )
        let requestSource = try String(
            contentsOf: packageRoot.appending(path: "Sources/LuxelApp/MenuBar/Models/LuxelMenuModel+RecordingRequests.swift"),
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

    @Test("settings pane does not activate capture resources")
    func settingsPaneDoesNotActivateCaptureResources() throws {
        let packageRoot = try packageRootURL()
        let settingsSource = try String(
            contentsOf: packageRoot.appending(path: "Sources/LuxelApp/Settings/Views/LuxelSettingsView.swift"),
            encoding: .utf8
        )

        #expect(!settingsSource.contains("watchAudioLevels("))
        #expect(!settingsSource.contains("AudioLevelMeterView("))
        #expect(!settingsSource.contains("syncCameraPreviewPanelWithSettings("))
    }

    @Test("recording lifecycle owns camera preview activation")
    func recordingLifecycleOwnsCameraPreviewActivation() throws {
        let packageRoot = try packageRootURL()
        let recordingSource = try String(
            contentsOf: packageRoot.appending(path: "Sources/LuxelApp/MenuBar/Models/LuxelMenuModel+Recording.swift"),
            encoding: .utf8
        )
        let cameraSource = try String(
            contentsOf: packageRoot.appending(path: "Sources/LuxelApp/MenuBar/Models/LuxelMenuModel+Camera.swift"),
            encoding: .utf8
        )

        let recorderStartRange = try #require(recordingSource.range(of: "recordingLifecycleService.startRecording("))
        let cameraStartRange = try #require(recordingSource.range(of: "await presentCameraPreviewForRecording(request)"))
        let recordingCameraHelperRange = try #require(
            cameraSource.range(of: "func presentCameraPreviewForRecording(_ request: RecordingRequest) async")
        )
        let recordingCameraHelperSource = String(cameraSource[recordingCameraHelperRange.lowerBound...])
        let cameraPreviewPresentCallCount = cameraSource
            .components(separatedBy: "cameraPreviewPanelController.present(")
            .count - 1

        #expect(recorderStartRange.lowerBound < cameraStartRange.lowerBound)
        #expect(recordingSource.contains("closeCameraPreviewForFinishedRecording()"))
        #expect(cameraSource.contains("func presentCameraPreviewForRecording(_ request: RecordingRequest) async"))
        #expect(cameraPreviewPresentCallCount == 1)
        #expect(!cameraSource.contains("syncCameraPreviewPanelWithSettings("))
        #expect(recordingCameraHelperSource.contains("guard let camera = request.camera"))
        #expect(recordingCameraHelperSource.contains("guard cameraStatus == .authorized"))
        #expect(recordingCameraHelperSource.contains("cameraPreviewPanelController.close()"))
        #expect(!recordingCameraHelperSource.contains("permissionClient.request(.camera)"))
        #expect(recordingCameraHelperSource.contains("showsHoverControls: false"))
        #expect(cameraSource.contains("func closeCameraPreviewForFinishedRecording()"))
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
}

private extension ArchitectureTests {
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

    private func sourceContents(under directory: URL) throws -> String {
        try swiftFiles(under: directory)
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
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
