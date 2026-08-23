import Foundation
import Testing

extension ArchitectureTests {
    @Test("recording FPS settings accept direct numeric entry")
    func recordingFPSSettingsAcceptDirectNumericEntry() throws {
        let packageRoot = try packageRootURL()
        let settingsSource = try sourceText(for: [
            "Sources/LuxelApp/Settings/Views/LuxelSettingsView.swift",
            "Sources/LuxelApp/Settings/Views/LuxelSettingsView+Recording.swift",
            "Sources/LuxelApp/Settings/Views/LuxelSettingsView+Support.swift"
        ])
        let requestSource = try String(
            contentsOf: packageRoot.appending(
                path: "Sources/LuxelApp/MenuBar/Models/LuxelMenuModel+RecordingRequests.swift"),
            encoding: .utf8
        )

        #expect(settingsSource.contains("TextField("))
        #expect(settingsSource.contains("value: recordingFrameRateSelection"))
        #expect(settingsSource.contains("formatter: recordingFrameRateFormatter"))
        #expect(settingsSource.contains("try model.settings.setRecordingFrameRate(frameRate)"))
        #expect(settingsSource.contains("Use a whole number from 1 to 120 FPS."))
        #expect(settingsSource.contains("Match Display Refresh Rate"))
        #expect(requestSource.contains("settings.matchDisplayFrameRate ? FrameRate.fps120"))
        #expect(!requestSource.contains("settings.record60FPS ? 60 : 30"))
    }

    @Test("settings pane does not activate capture resources")
    func settingsPaneDoesNotActivateCaptureResources() throws {
        let packageRoot = try packageRootURL()
        let settingsSource = try String(
            contentsOf: packageRoot.appending(
                path: "Sources/LuxelApp/Settings/Views/LuxelSettingsView.swift"),
            encoding: .utf8
        )

        #expect(!settingsSource.contains("watchAudioLevels("))
        #expect(!settingsSource.contains("AudioLevelMeterView("))
        #expect(!settingsSource.contains("syncCameraPreviewPanelWithSettings("))
    }

    @Test("speech detection setting uses the toggle without a redundant status row")
    func speechDetectionSettingOmitsStatusRow() throws {
        let source = try sourceText(for: [
            "Sources/LuxelApp/Settings/Views/LuxelSettingsView+SpeechDetection.swift"
        ])

        #expect(source.contains("settingsToggleRow("))
        #expect(!source.contains("settings.speechDetection.status.label"))
        #expect(!source.contains("speechDetectionStatusText"))
        #expect(!source.contains("speechDetectionRecoveryButton"))
    }

    @Test("recording lifecycle owns camera preview activation")
    func recordingLifecycleOwnsCameraPreviewActivation() throws {
        let recordingSource = try sourceText(for: [
            "Sources/LuxelApp/MenuBar/Models/LuxelMenuModel+RecordingLifecycle.swift"
        ])
        let cameraSource = try sourceText(for: [
            "Sources/LuxelApp/MenuBar/Models/LuxelMenuModel+Camera.swift"
        ])

        let recorderStartRange = try #require(
            recordingSource.range(of: "recordingLifecycleService.startRecording("))
        let cutoutPreparationRange = try #require(
            recordingSource.range(of: "await preparingCameraCutoutIfNeeded(for: request)"))
        let cameraStartRange = try #require(
            recordingSource.range(of: "await presentCameraPreviewForRecording(request)"))
        let recordingCameraHelperRange = try #require(
            cameraSource.range(
                of: "func presentCameraPreviewForRecording(_ request: RecordingRequest) async")
        )
        let stopRecordingRange = try #require(recordingSource.range(of: "func stopRecording() async"))
        let stopRecorderRange = try #require(
            recordingSource[stopRecordingRange.lowerBound...].range(
                of: "recordingLifecycleService.stopRecording()")
        )
        let stopCameraRange = try #require(
            recordingSource[stopRecordingRange.lowerBound...].range(
                of: "await closeCameraPreviewForRecordingStop()")
        )
        let recordingCameraHelperSource = String(
            cameraSource[recordingCameraHelperRange.lowerBound...]
        )
        let cameraPreviewPresentCallCount =
            cameraSource
            .components(separatedBy: "cameraPreviewPanelController.present(")
            .count - 1

        #expect(cutoutPreparationRange.lowerBound < recorderStartRange.lowerBound)
        #expect(recorderStartRange.lowerBound < cameraStartRange.lowerBound)
        #expect(stopCameraRange.lowerBound < stopRecorderRange.lowerBound)
        #expect(recordingSource.contains("closeCameraPreviewForFinishedRecording()"))
        #expect(
            cameraSource.contains(
                "func presentCameraPreviewForRecording(_ request: RecordingRequest) async"))
        #expect(cameraPreviewPresentCallCount == 1)
        #expect(!cameraSource.contains("syncCameraPreviewPanelWithSettings("))
        #expect(recordingCameraHelperSource.contains("guard let camera = request.camera"))
        #expect(recordingCameraHelperSource.contains("guard cameraStatus == .authorized"))
        #expect(recordingCameraHelperSource.contains("cameraPreviewPanelController.close()"))
        #expect(!recordingCameraHelperSource.contains("permissionClient.request(.camera)"))
        #expect(recordingCameraHelperSource.contains("showsHoverControls: false"))
        #expect(cameraSource.contains("func closeCameraPreviewForFinishedRecording()"))
        #expect(cameraSource.contains("try await cameraPreviewPanelController.prepareCutout()"))
        #expect(cameraSource.contains("request.replacingCamera("))
    }

    @Test("update settings milestone does not link Sparkle yet")
    func updateSettingsMilestoneDoesNotLinkSparkleYet() throws {
        let packageRoot = try packageRootURL()
        let checkedURLs =
            [packageRoot.appending(path: "Package.swift")]
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
                #expect(
                    !contents.contains(forbiddenSnippet), "\(fileURL.path) contains \(forbiddenSnippet)")
            }
        }
    }
}
