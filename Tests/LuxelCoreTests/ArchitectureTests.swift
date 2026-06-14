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
        #expect(source.contains("top: min(max(screen.safeAreaInsets.top, bottomRadius), 48)"))
        #expect(source.contains("bottom: bottomRadius"))
        #expect(source.contains("screen.safeAreaInsets.top"))
        #expect(source.contains("UnevenRoundedRectangle("))
        #expect(source.contains("topLeadingRadius: cornerRadii.top"))
        #expect(source.contains("bottomLeadingRadius: cornerRadii.bottom"))
        #expect(source.contains(".ignoresSafeArea()"))
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
