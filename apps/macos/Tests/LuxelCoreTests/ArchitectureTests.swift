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
            try expectSources(under: directory, omit: forbiddenImports)
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

        try expectSources(under: sourceDirectory, omit: forbiddenSnippets)
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

        try expectSources(under: sourceDirectory, omit: forbiddenSnippets)
    }

    @Test("permission client supports user-initiated capture permission requests")
    func permissionClientSupportsUserInitiatedCapturePermissionRequests() throws {
        let permissionSource = try String(
            contentsOf: packageRootURL().appending(
                path: "Sources/LuxelCore/Infrastructure/System/ApplePermissionClient.swift"),
            encoding: .utf8
        )
        let speechSource = try String(
            contentsOf: packageRootURL().appending(
                path:
                    "Sources/LuxelCore/Infrastructure/Transcripts/AppleSpeechRecognitionAuthorizationService.swift"
            ),
            encoding: .utf8
        )

        #expect(
            permissionSource.contains("CGPreflightScreenCaptureAccess() ? .authorized : .notDetermined"))
        #expect(permissionSource.contains("CGRequestScreenCaptureAccess() ? .authorized"))
        #expect(!permissionSource.contains("CGRequestListenEventAccess"))
        #expect(permissionSource.contains("AVAudioApplication.requestRecordPermission"))
        #expect(permissionSource.contains("AVCaptureDevice.requestAccess"))
        #expect(!permissionSource.contains("SCShareableContent.current"))
        #expect(!speechSource.contains("SFSpeechRecognizer.requestAuthorization"))
    }

    @Test("CGEventTap remains isolated to the keystroke adapter")
    func eventTapRemainsIsolatedToKeystrokeAdapter() throws {
        let sourceDirectory = try packageRootURL().appending(path: "Sources")
        let allowedPath = "Infrastructure/Keystrokes/CGEventTapKeystrokeRecorder.swift"

        for fileURL in try swiftFiles(under: sourceDirectory) {
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            guard contents.contains("CGEvent.tapCreate")
                    || contents.contains(".tapDisabledByTimeout")
                    || contents.contains("CGEvent.tapEnable")
            else {
                continue
            }

            #expect(fileURL.path.hasSuffix(allowedPath), "\(fileURL.path) owns event-tap symbols")
        }
    }

    @Test("keystroke adapter recovers disabled taps and checks secure input")
    func keystrokeAdapterRecoversDisabledTapsAndChecksSecureInput() throws {
        let source = try sourceText(for: [
            "Sources/LuxelCore/Infrastructure/Keystrokes/CGEventTapKeystrokeRecorder.swift"
        ])

        #expect(source.contains("type == .tapDisabledByTimeout"))
        #expect(source.contains("type == .tapDisabledByUserInput"))
        #expect(source.contains("CGEvent.tapEnable(tap: eventTap, enable: true)"))
        #expect(source.contains("IsSecureEventInputEnabled()"))
        #expect(source.contains("Timer.scheduledTimer(withTimeInterval: 1"))
    }

    @Test("keystroke lifecycle and compositor cover every visual export path")
    func keystrokeLifecycleAndCompositorCoverEveryVisualExportPath() throws {
        let lifecycle = try sourceText(for: [
            "Sources/LuxelApp/MenuBar/Models/LuxelMenuModel+RecordingLifecycle.swift"
        ])
        let avFoundation = try sourceText(for: [
            "Sources/LuxelCore/Infrastructure/Media/Export/AVFoundationMediaExporter.swift"
        ])
        let codecs = try sourceText(for: [
            "Sources/LuxelCore/Infrastructure/Media/Readers/AVAssetReaderCodecMediaSource+Composition.swift"
        ])
        let videoComposition = try sourceText(for: [
            "Sources/LuxelCore/Infrastructure/Media/Video/AVFoundationVideoCompositionFactory.swift"
        ])
        let animated = try sourceText(for: [
            "Sources/LuxelCore/Infrastructure/Media/GIF/ImageIOAnimatedMediaExporter.swift"
        ])

        let recorderStart = try #require(lifecycle.range(of: "keystrokeRecordingSession.start()"))
        let captureStart = try #require(
            lifecycle.range(of: "recordingLifecycleService.startRecording("))
        let previewPreparation = try #require(
            lifecycle.range(of: "keystrokeLivePreviewPanelController.prepareForCapture("))
        #expect(previewPreparation.lowerBound < captureStart.lowerBound)
        #expect(captureStart.lowerBound < recorderStart.lowerBound)
        #expect(lifecycle.contains("keystrokeRecordingSession.stopAndSave"))
        #expect(lifecycle.contains("finishAudioRecordingStop"))
        #expect(lifecycle.contains("await finishKeystrokeCapture(for: recording)"))
        #expect(lifecycle.contains("keystrokeRecordingSession.recordingDidPause()"))
        #expect(lifecycle.contains("keystrokeRecordingSession.recordingDidResume()"))
        #expect(avFoundation.contains("request: request"))
        #expect(codecs.contains("request: request"))
        #expect(videoComposition.contains("keystrokeTimeline: try? KeystrokeSidecarFileLoader"))
        #expect(videoComposition.contains("keystrokeTimelineMapper: request.timelineMapper"))
        #expect(videoComposition.contains("timelineMapper.mapSourceRange(chip.timeRange)"))
        #expect(animated.contains("keystrokeCompositor.composite"))
    }

    @Test("status item startup does not enumerate capture targets")
    func statusItemStartupDoesNotEnumerateCaptureTargets() throws {
        let source = try sourceText(
            for: [
                "Sources/LuxelApp/App/LuxelStatusItemController+Actions.swift"
            ],
            encoding: .utf8
        )
        let startupRange = try #require(source.range(of: "func startNotchSurface()"))
        let startupSource = source[startupRange.lowerBound...]

        #expect(startupSource.contains("await model.refreshPermissions()"))
        #expect(!startupSource.contains("refreshCaptureTargets()"))
    }

    @Test("notch idle quick actions can prompt for screen permission")
    func notchIdleQuickActionsCanPromptForScreenPermission() throws {
        let source = try String(
            contentsOf: packageRootURL().appending(
                path: "Sources/LuxelApp/MenuBar/Models/LuxelMenuModel+Notch.swift"),
            encoding: .utf8
        )

        #expect(source.contains("private var canUseScreenDependentNotchAction: Bool"))
        #expect(source.contains("screenRecordingStatus == .authorized"))
        #expect(source.contains("presentPermissionPrompt(forSource: .screenPixels)"))
        #expect(
            source.contains(
                "case .idle:\n"
                    + "            return .idleHover"
            ))
        #expect(
            !source.contains(
                "case .failed(let message):\n"
                    + "            guard screenRecordingStatus == .authorized else {\n"
                    + "                return .dormant\n"
                    + "            }"
            ))
    }

    @Test("notch action icons expose hover tooltips")
    func notchActionIconsExposeHoverTooltips() throws {
        let source = try String(
            contentsOf: packageRootURL().appending(
                path: "Sources/LuxelApp/Notch/Panels/NotchOverlayViews.swift"),
            encoding: .utf8
        )

        #expect(source.contains("@State private var hoveredActionID: NotchActivityActionID?"))
        #expect(
            source.contains(
                "private func notchActionTooltip(for action: NotchActivityActionDescriptor) -> some View"))
        #expect(source.contains(".help(Text(action.title))"))
        #expect(source.contains(".onHover { isHovered in"))
    }

    @Test("notch hover regions track the visible surface")
    func notchHoverRegionsTrackTheVisibleSurface() throws {
        let source = try String(
            contentsOf: packageRootURL().appending(
                path: "Sources/LuxelApp/Notch/Panels/OverlayPanelNotchPresenter.swift"),
            encoding: .utf8
        )

        #expect(source.contains("return [expandedSurfaceHitRect(for: geometry)]"))
        #expect(
            source.contains(
                "private static func collapsedHoverRect(for geometry: NotchGeometry) -> NSRect"))
        #expect(source.contains("housing.maxY - height"))
        #expect(!source.contains("panelFrame(for: geometry).insetBy(dx: -8, dy: -8)"))
        #expect(!source.contains("geometry.cameraHousingRect.nsRect.insetBy(dx: -28, dy: -18)"))
    }

    @Test("system audio footer off state toggles without permission prompt")
    func systemAudioFooterOffStateTogglesWithoutPermissionPrompt() throws {
        let source = try String(
            contentsOf: packageRootURL().appending(
                path: "Sources/LuxelApp/MenuBar/Views/LuxelMenu+Footer.swift"),
            encoding: .utf8
        )
        let handlerRange = try #require(source.range(of: "func handleSystemAudioFooterAction"))
        let nextHandlerRange = try #require(
            source[handlerRange.upperBound...].range(of: "func handleMicrophoneFooterAction"))
        let handlerSource = String(source[handlerRange.lowerBound..<nextHandlerRange.lowerBound])

        #expect(
            handlerSource.contains(
                "case .offByUser:\n"
                    + "            model.settings.recordSystemAudio = true\n"
                    + "            model.saveSettings()"
            ))
        #expect(
            !handlerSource.contains(
                "case .offByUser:\n"
                    + "      presentPermissionPrompt(.systemAudio)"))
    }

    @Test("permission prompts are hosted outside transient SwiftUI menu surfaces")
    func permissionPromptsAreHostedOutsideTransientSwiftUIMenuSurfaces() throws {
        let packageRoot = try packageRootURL()
        let statusItemSource = try sourceText(
            for: [
                "Sources/LuxelApp/App/LuxelStatusItemController.swift",
                "Sources/LuxelApp/App/LuxelStatusItemController+Actions.swift"
            ]
        )
        let menuSource = try String(
            contentsOf: packageRoot.appending(path: "Sources/LuxelApp/MenuBar/Views/LuxelMenu.swift"),
            encoding: .utf8
        )
        let settingsSource = try String(
            contentsOf: packageRoot.appending(
                path: "Sources/LuxelApp/Settings/Views/LuxelSettingsView.swift"),
            encoding: .utf8
        )

        #expect(statusItemSource.contains("func presentPendingPermissionPromptIfNeeded()"))
        #expect(statusItemSource.contains("let alert = NSAlert()"))
        #expect(
            statusItemSource.contains(
                "let primaryButton = alert.addButton(withTitle: prompt.guidance.actionTitle)"))
        #expect(statusItemSource.contains("primaryButton.keyEquivalent = \"\\r\""))
        #expect(
            statusItemSource.contains(
                "presentPermissionPrompt(model.makePermissionPrompt(forSource: source))"))
        #expect(statusItemSource.contains("if prompt.guidance.action == .request"))
        #expect(statusItemSource.contains("await model.performPermissionAction(prompt)"))
        #expect(!menuSource.contains("isPresented: permissionPromptPresented"))
        #expect(!settingsSource.contains("isPresented: permissionPromptPresented"))
    }

    @Test("permission actions separate native requests from settings recovery")
    func permissionActionsSeparateNativeRequestsFromSettingsRecovery() throws {
        let source = try String(
            contentsOf: packageRootURL().appending(
                path: "Sources/LuxelApp/MenuBar/Models/LuxelMenuModel+Permissions.swift"),
            encoding: .utf8
        )
        let handlerRange = try #require(source.range(of: "func performPermissionAction"))
        let nextRange = try #require(
            source[handlerRange.upperBound...].range(of: "func sourcePermissionPresentation"))
        let handlerSource = String(source[handlerRange.lowerBound..<nextRange.lowerBound])

        #expect(handlerSource.contains("permissionClient.request(prompt.permission)"))
        #expect(handlerSource.contains("await permissionClient.openSettings(for: prompt.permission)"))
        #expect(!handlerSource.contains("openSettingsAfterDeniedRequest"))
    }

}
