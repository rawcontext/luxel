import AppKit
import Foundation
import LuxelCore
import LuxelPresentation
import SwiftUI

struct LuxelSettingsView: View {
    @Environment(\.openWindow) private var openWindow
    @State private var isShowingAcknowledgements = false

    @Bindable var model: LuxelMenuModel
    let editorModel: LuxelEditorModel
    let cropperPanelController: LuxelCropperPanelController
    let shortcutController: LuxelShortcutController
    private let shortcutConflictDetector = AppKeyboardShortcutConflictDetector()

    var body: some View {
        Form {
            Section("Capture") {
                Toggle("Show Cursor", isOn: $model.settings.showCursor)
                Toggle("Highlight Clicks", isOn: $model.settings.highlightClicks)
                    .disabled(!model.settings.showCursor)
                Picker("Frame Rate", selection: $model.settings.record60FPS) {
                    Text("30 FPS").tag(false)
                    Text("60 FPS").tag(true)
                }
            }

            Section("Audio") {
                Toggle("Record Audio", isOn: $model.settings.recordAudio)
                Picker("Microphone", selection: audioInputDeviceSelection) {
                    ForEach(model.audioInputDevices) { device in
                        Text(device.name).tag(device.id)
                    }
                }
                .disabled(!model.settings.recordAudio)

                Picker("Audio-Only Format", selection: $model.settings.audioOnlyFormat) {
                    ForEach(AudioRecordingFormat.allCases, id: \.self) { format in
                        Text(format.label).tag(format)
                    }
                }
                .pickerStyle(.menu)

                if model.settings.recordAudio, model.microphoneStatus == .authorized {
                    AudioLevelMeterView(sample: model.audioLevelSample)
                }
            }

            Section("Camera") {
                Picker("Camera", selection: $model.settings.cameraDeviceID) {
                    Text("Off").tag(String?.none)
                    if let unavailableCameraDeviceID {
                        Text("Unavailable Camera").tag(Optional(unavailableCameraDeviceID))
                    }
                    ForEach(model.cameraDevices) { device in
                        Text(device.settingsLabel).tag(Optional(device.id))
                    }
                }
                .pickerStyle(.menu)

                Picker("Shape", selection: cameraPreviewShapeSelection) {
                    ForEach(CameraOverlayShape.allCases, id: \.self) { shape in
                        Text(shape.settingsLabel).tag(shape)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(model.settings.cameraDeviceID == nil)

                Picker("Size", selection: cameraPreviewSizeSelection) {
                    ForEach(CameraPreviewSize.allCases, id: \.self) { size in
                        Text(size.settingsLabel).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(model.settings.cameraDeviceID == nil)

                Toggle("Mirror Preview", isOn: cameraPreviewMirroredSelection)
                    .disabled(model.settings.cameraDeviceID == nil)
            }

            Section("Output") {
                LabeledContent("Folder") {
                    Button {
                        model.chooseRecordingsDirectory()
                    } label: {
                        Label {
                            Text(model.recordingsDirectorySummary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } icon: {
                            Image(systemName: "folder")
                        }
                    }
                    .help(model.settings.recordingsDirectory.path)
                }

                Toggle("Loop Exports", isOn: $model.settings.loopExports)
                Toggle("Confirm Discard", isOn: $model.settings.confirmDiscard)
            }

            Section("Screenshots") {
                Picker("Format", selection: $model.settings.screenshotFormat) {
                    ForEach(ScreenshotFormat.allCases, id: \.self) { format in
                        Text(format.settingsLabel).tag(format)
                    }
                }
                .pickerStyle(.menu)

                Picker("Window Backdrop", selection: $model.settings.screenshotBackdrop) {
                    ForEach(CaptureBackdrop.allCases, id: \.self) { backdrop in
                        Text(backdrop.settingsLabel)
                            .tag(backdrop)
                            .disabled(backdrop.usesAlpha && !model.settings.screenshotFormat.supportsAlpha)
                    }
                }
                .pickerStyle(.menu)

                ForEach(ScreenshotDestination.allCases, id: \.self) { destination in
                    Toggle(destination.settingsLabel, isOn: screenshotDestinationBinding(destination))
                }

                Toggle("Show Thumbnail", isOn: $model.settings.screenshotShowThumbnail)

                shortcutPicker(
                    "Screenshot",
                    selection: $model.settings.captureScreenshotShortcut,
                    presets: AppKeyboardShortcutPresets.captureScreenshot
                )

                shortcutPicker(
                    "Active Window",
                    selection: $model.settings.screenshotActiveWindowShortcut,
                    presets: AppKeyboardShortcutPresets.screenshotActiveWindow
                )

                shortcutPicker(
                    "Fullscreen",
                    selection: $model.settings.screenshotFullscreenShortcut,
                    presets: AppKeyboardShortcutPresets.screenshotFullscreen
                )
            }

            ExportPresetSettingsSection(settings: $model.settings)

            Section("System") {
                Toggle("Show Time in Menu Bar", isOn: $model.settings.showTimeInMenuBar)
                Toggle("Remind About Notifications", isOn: $model.settings.notificationReminder)
                Toggle("Allow URL Automation", isOn: $model.settings.allowURLAutomation)
                if AppDistribution.current.capabilities.allowsCommandLineToolInstaller {
                    LabeledContent("Command Line Tool") {
                        Button {
                            model.installCommandLineTool()
                        } label: {
                            Label("Install luxel", systemImage: "terminal")
                        }
                        .help("Install to \(model.commandLineToolInstallService.defaultDestination.path)")
                    }

                    if let installStatus = model.commandLineToolInstallStatus {
                        Label(installStatus.message, systemImage: installStatus.systemImage)
                            .font(.caption)
                            .foregroundStyle(installStatus.tint)
                    }
                }

                Toggle("Keyboard Shortcuts", isOn: $model.settings.enableShortcuts)
                shortcutPicker(
                    "Select Area",
                    selection: $model.settings.triggerCropperShortcut,
                    presets: AppKeyboardShortcutPresets.capture
                )

                shortcutPicker(
                    "Toggle Recording",
                    selection: $model.settings.toggleRecordingShortcut,
                    presets: AppKeyboardShortcutPresets.toggleRecording
                )

                shortcutPicker(
                    "Record Active Window",
                    selection: $model.settings.recordActiveWindowShortcut,
                    presets: AppKeyboardShortcutPresets.recordActiveWindow
                )

                shortcutPicker(
                    "Record Fullscreen",
                    selection: $model.settings.recordFullscreenShortcut,
                    presets: AppKeyboardShortcutPresets.recordFullscreen
                )

                shortcutPicker(
                    "Audio Only",
                    selection: $model.settings.audioOnlyRecordingShortcut,
                    presets: AppKeyboardShortcutPresets.audioOnlyRecording
                )

                shortcutPicker(
                    "Quick Record Last",
                    selection: $model.settings.quickRecordLastShortcut,
                    presets: AppKeyboardShortcutPresets.quickRecordLast
                )

                Toggle("Launch at Login", isOn: $model.launchAtLogin)
            }

            Section("Updates") {
                let updatePresentation = updateSettingsPresentation

                LabeledContent("Current Version", value: model.appMetadata.versionSummary)
                LabeledContent("Status", value: updatePresentation.statusText)

                if updatePresentation.showsDeveloperIDUpdateControls {
                    Toggle("Check Automatically", isOn: $model.settings.updatePreferences.automaticallyCheckForUpdates)

                    Toggle("Install Automatically", isOn: $model.settings.updatePreferences.automaticallyDownloadAndInstall)
                        .disabled(!updatePresentation.automaticInstallToggleEnabled)

                    Picker("Channel", selection: $model.settings.updatePreferences.channel) {
                        ForEach(UpdateChannel.allCases) { channel in
                            Text(channel.label).tag(channel)
                        }
                    }
                    .pickerStyle(.menu)

                    Button {} label: {
                        Label("Check Now", systemImage: "arrow.clockwise")
                    }
                    .disabled(!updatePresentation.canCheckNow)
                    .help(updatePresentation.checkNowHelp)
                }

                Text(updatePresentation.networkPolicyText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("App", value: model.appMetadata.displayName)
                LabeledContent("Version", value: model.appMetadata.versionSummary)

                if !model.appMetadata.copyright.isEmpty {
                    Text(model.appMetadata.copyright)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    isShowingAcknowledgements = true
                } label: {
                    Label("Acknowledgements", systemImage: "doc.text")
                }
            }
        }
        .formStyle(.grouped)
        .padding(24)
        .frame(width: 460)
        .background {
            LuxelShortcutInstaller(
                model: model,
                cropperPanelController: cropperPanelController,
                shortcutController: shortcutController
            ) { fileURL in
                openRecording(fileURL)
            }
        }
        .task {
            await model.refreshPermissions()
            model.refreshAudioInputDevices()
            model.refreshCameraDevices()
            await model.syncCameraPreviewPanelWithSettings()
            await model.watchAudioInputDeviceUpdates()
        }
        .task(id: model.audioLevelMonitorTaskID) {
            await model.watchAudioLevels()
        }
        .onAppear {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        .onChange(of: model.settings) {
            model.saveSettings()
        }
        .onChange(of: model.settings.screenshotFormat) {
            if model.settings.screenshotBackdrop.usesAlpha,
               !model.settings.screenshotFormat.supportsAlpha {
                model.settings.screenshotBackdrop = .opaque
            }
        }
        .onChange(of: model.settings.cameraDeviceID) {
            Task {
                await model.syncCameraPreviewPanelWithSettings()
            }
        }
        .onChange(of: model.settings.cameraPreviewStyle) {
            Task {
                await model.syncCameraPreviewPanelWithSettings()
            }
        }
        .onChange(of: model.launchAtLogin) {
            model.setLaunchAtLogin(model.launchAtLogin)
        }
        .alert(
            Text(model.permissionPrompt?.guidance.title ?? "Permission"),
            isPresented: permissionPromptPresented,
            presenting: model.permissionPrompt
        ) { prompt in
            Button(prompt.guidance.actionTitle) {
                Task {
                    await model.performPermissionAction(prompt)
                }
            }

            Button("Cancel", role: .cancel) {
                model.permissionPrompt = nil
            }
        } message: { prompt in
            Text(prompt.guidance.message)
        }
        .sheet(isPresented: $isShowingAcknowledgements) {
            CodecAcknowledgementsView(text: CodecAcknowledgementsResource.bundledText())
        }
    }

    private var unavailableCameraDeviceID: String? {
        guard let cameraDeviceID = model.settings.cameraDeviceID,
              !model.cameraDevices.contains(where: { $0.id == cameraDeviceID }) else {
            return nil
        }

        return cameraDeviceID
    }

    private var updateSettingsPresentation: UpdateSettingsPresentation {
        UpdateSettingsPresentation(
            preferences: model.settings.updatePreferences,
            distribution: AppDistribution.current
        )
    }

    private var audioInputDeviceSelection: Binding<String> {
        Binding {
            model.settings.audioInputDeviceID ?? AudioInputDeviceID.systemDefault
        } set: { deviceID in
            model.settings.audioInputDeviceID = deviceID
            model.settings.audioInputDeviceName = model.audioInputDevices
                .first { $0.id == deviceID }?
                .name
        }
    }

    private var cameraPreviewShapeSelection: Binding<CameraOverlayShape> {
        Binding {
            model.settings.cameraPreviewStyle.shape
        } set: { shape in
            let style = model.settings.cameraPreviewStyle
            model.settings.cameraPreviewStyle = CameraPreviewStyle(
                shape: shape,
                size: style.size,
                isMirrored: style.isMirrored
            )
        }
    }

    private var cameraPreviewSizeSelection: Binding<CameraPreviewSize> {
        Binding {
            model.settings.cameraPreviewStyle.size
        } set: { size in
            let style = model.settings.cameraPreviewStyle
            model.settings.cameraPreviewStyle = CameraPreviewStyle(
                shape: style.shape,
                size: size,
                isMirrored: style.isMirrored
            )
        }
    }

    private var cameraPreviewMirroredSelection: Binding<Bool> {
        Binding {
            model.settings.cameraPreviewStyle.isMirrored
        } set: { isMirrored in
            let style = model.settings.cameraPreviewStyle
            model.settings.cameraPreviewStyle = CameraPreviewStyle(
                shape: style.shape,
                size: style.size,
                isMirrored: isMirrored
            )
        }
    }

    @ViewBuilder
    private func shortcutPicker(
        _ title: String,
        selection: Binding<String>,
        presets: [AppKeyboardShortcut]
    ) -> some View {
        Picker(title, selection: selection) {
            Text("None").tag("")
            ForEach(presets) { shortcut in
                Text(shortcut.displayName).tag(shortcut.rawValue)
            }
        }
        .disabled(!model.settings.enableShortcuts)

        if model.settings.enableShortcuts,
           let conflict = shortcutConflictDetector.conflict(forRawValue: selection.wrappedValue) {
            Label(
                "Conflicts with \(conflict.systemAction)",
                systemImage: "exclamationmark.triangle"
            )
            .font(.caption)
            .foregroundStyle(.orange)
        }
    }

    private func screenshotDestinationBinding(_ destination: ScreenshotDestination) -> Binding<Bool> {
        Binding {
            model.settings.screenshotDestinations.contains(destination)
        } set: { isEnabled in
            if isEnabled {
                guard !model.settings.screenshotDestinations.contains(destination) else {
                    return
                }

                model.settings.screenshotDestinations.append(destination)
            } else if model.settings.screenshotDestinations.count > 1 {
                model.settings.screenshotDestinations.removeAll { $0 == destination }
            }
        }
    }

    private var permissionPromptPresented: Binding<Bool> {
        Binding {
            model.permissionPrompt != nil
        } set: { isPresented in
            if !isPresented {
                model.permissionPrompt = nil
            }
        }
    }

    private func openRecording(_ url: URL) {
        openWindow(id: LuxelEditorScene.id)
        NSApplication.shared.activate(ignoringOtherApps: true)

        Task {
            model.configureEditor(editorModel)
            await editorModel.open(fileURL: url, outputDirectory: model.settings.recordingsDirectory)
        }
    }
}

private extension ScreenshotFormat {
    var settingsLabel: String {
        switch self {
        case .png:
            "PNG"
        case .jpeg:
            "JPEG"
        case .heic:
            "HEIC"
        }
    }
}

private extension ScreenshotDestination {
    var settingsLabel: String {
        switch self {
        case .clipboard:
            "Copy to Clipboard"
        case .file:
            "Save File"
        case .preview:
            "Open Preview"
        }
    }
}

private extension CaptureBackdrop {
    var settingsLabel: String {
        switch self {
        case .opaque:
            "Opaque"
        case .transparent:
            "Transparent"
        case .transparentWithShadow:
            "Transparent + Shadow"
        }
    }
}

private extension CommandLineToolInstallStatus {
    var message: String {
        switch self {
        case .installed(let destination):
            "Installed at \(destination.path)"
        case .failed(let message):
            message
        }
    }

    var systemImage: String {
        switch self {
        case .installed:
            "checkmark.circle"
        case .failed:
            "exclamationmark.triangle"
        }
    }

    var tint: Color {
        switch self {
        case .installed:
            .secondary
        case .failed:
            .orange
        }
    }
}
