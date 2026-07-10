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
                    #expect(
                        !contents.contains(forbiddenImport), "\(fileURL.path) contains \(forbiddenImport)")
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
                #expect(
                    !contents.contains(forbiddenSnippet), "\(fileURL.path) contains \(forbiddenSnippet)")
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
                #expect(
                    !contents.contains(forbiddenSnippet), "\(fileURL.path) contains \(forbiddenSnippet)")
            }
        }
    }

    @Test("permission client avoids native request prompts")
    func permissionClientAvoidsNativeRequestPrompts() throws {
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
        #expect(!permissionSource.contains("CGRequestScreenCaptureAccess"))
        #expect(!permissionSource.contains("AVAudioApplication.requestRecordPermission"))
        #expect(!permissionSource.contains("AVCaptureDevice.requestAccess"))
        #expect(!permissionSource.contains("SCShareableContent.current"))
        #expect(!speechSource.contains("SFSpeechRecognizer.requestAuthorization"))
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
        #expect(!menuSource.contains("isPresented: permissionPromptPresented"))
        #expect(!settingsSource.contains("isPresented: permissionPromptPresented"))
    }

    @Test("permission actions open settings without native request prompts")
    func permissionActionsOpenSettingsWithoutNativeRequestPrompts() throws {
        let source = try String(
            contentsOf: packageRootURL().appending(
                path: "Sources/LuxelApp/MenuBar/Models/LuxelMenuModel+Permissions.swift"),
            encoding: .utf8
        )
        let handlerRange = try #require(source.range(of: "func performPermissionAction"))
        let nextRange = try #require(
            source[handlerRange.upperBound...].range(of: "func sourcePermissionPresentation"))
        let handlerSource = String(source[handlerRange.lowerBound..<nextRange.lowerBound])

        #expect(!handlerSource.contains("permissionClient.request"))
        #expect(handlerSource.contains("await permissionClient.openSettings(for: prompt.permission)"))
        #expect(handlerSource.contains("permissionStatus(for: prompt.permission) != .authorized"))
    }

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

    @Test("menu bar status click stops active recording before opening popover")
    func menuBarStatusClickStopsActiveRecordingBeforeOpeningPopover() throws {
        let source = try sourceText(
            for: [
                "Sources/LuxelApp/App/LuxelStatusItemController.swift",
                "Sources/LuxelApp/App/LuxelStatusItemController+Rendering.swift",
                "Sources/LuxelApp/App/LuxelStatusItemController+Actions.swift",
                "Sources/LuxelApp/App/LuxelStatusItemController+Popover.swift"
            ],
            encoding: .utf8
        )

        #expect(source.contains("button.action = #selector(handleStatusItemClick)"))
        #expect(source.contains("button.sendAction(on: [.leftMouseUp])"))
        #expect(!source.contains("button.sendAction(on: [.leftMouseDown])"))
        #expect(source.contains("configureStatusItemButton(button)"))
        #expect(source.contains("statusItem.autosaveName"))
        #expect(source.contains("Bundle.main.bundleIdentifier"))
        #expect(source.contains(".statusItem"))
        #expect(source.contains("if model.hasActiveRecording"))
        #expect(source.contains("stopRecordingFromStatusItem()"))
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
        let writerSource = try String(
            contentsOf: packageRoot.appending(
                path: "Sources/LuxelCore/Infrastructure/Capture/ScreenCaptureKitRecordingWriter.swift"),
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
