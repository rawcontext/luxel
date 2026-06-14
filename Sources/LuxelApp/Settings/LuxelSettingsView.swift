import AppKit
import Foundation
import LuxelCore
import LuxelPresentation
import SwiftUI

struct LuxelSettingsView: View {
    @Environment(\.openWindow) private var openWindow

    @Bindable var model: LuxelMenuModel
    let editorModel: LuxelEditorModel
    let cropperPanelController: LuxelCropperPanelController
    let shortcutController: LuxelShortcutController

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

                Picker("Screenshot", selection: $model.settings.captureScreenshotShortcut) {
                    Text("None").tag("")
                    ForEach(AppKeyboardShortcutPresets.captureScreenshot) { shortcut in
                        Text(shortcut.displayName).tag(shortcut.rawValue)
                    }
                }
                .disabled(!model.settings.enableShortcuts)

                Picker("Active Window", selection: $model.settings.screenshotActiveWindowShortcut) {
                    Text("None").tag("")
                    ForEach(AppKeyboardShortcutPresets.screenshotActiveWindow) { shortcut in
                        Text(shortcut.displayName).tag(shortcut.rawValue)
                    }
                }
                .disabled(!model.settings.enableShortcuts)

                Picker("Fullscreen", selection: $model.settings.screenshotFullscreenShortcut) {
                    Text("None").tag("")
                    ForEach(AppKeyboardShortcutPresets.screenshotFullscreen) { shortcut in
                        Text(shortcut.displayName).tag(shortcut.rawValue)
                    }
                }
                .disabled(!model.settings.enableShortcuts)
            }

            Section("Quick Recording") {
                Picker("Quick Preset", selection: $model.settings.quickExportPresetID) {
                    Text("None").tag(Optional<UUID>.none)
                    ForEach(model.settings.exportPresets) { preset in
                        Text(preset.name).tag(Optional(preset.id))
                    }
                }
                .pickerStyle(.menu)

                Toggle("Remember Last Capture", isOn: $model.settings.rememberLastCapture)
            }

            Section("System") {
                Toggle("Show Time in Menu Bar", isOn: $model.settings.showTimeInMenuBar)
                Toggle("Keyboard Shortcuts", isOn: $model.settings.enableShortcuts)
                Picker("Select Area", selection: $model.settings.triggerCropperShortcut) {
                    Text("None").tag("")
                    ForEach(AppKeyboardShortcutPresets.capture) { shortcut in
                        Text(shortcut.displayName).tag(shortcut.rawValue)
                    }
                }
                .disabled(!model.settings.enableShortcuts)

                Picker("Toggle Recording", selection: $model.settings.toggleRecordingShortcut) {
                    Text("None").tag("")
                    ForEach(AppKeyboardShortcutPresets.toggleRecording) { shortcut in
                        Text(shortcut.displayName).tag(shortcut.rawValue)
                    }
                }
                .disabled(!model.settings.enableShortcuts)

                Picker("Record Active Window", selection: $model.settings.recordActiveWindowShortcut) {
                    Text("None").tag("")
                    ForEach(AppKeyboardShortcutPresets.recordActiveWindow) { shortcut in
                        Text(shortcut.displayName).tag(shortcut.rawValue)
                    }
                }
                .disabled(!model.settings.enableShortcuts)

                Picker("Record Fullscreen", selection: $model.settings.recordFullscreenShortcut) {
                    Text("None").tag("")
                    ForEach(AppKeyboardShortcutPresets.recordFullscreen) { shortcut in
                        Text(shortcut.displayName).tag(shortcut.rawValue)
                    }
                }
                .disabled(!model.settings.enableShortcuts)

                Picker("Audio Only", selection: $model.settings.audioOnlyRecordingShortcut) {
                    Text("None").tag("")
                    ForEach(AppKeyboardShortcutPresets.audioOnlyRecording) { shortcut in
                        Text(shortcut.displayName).tag(shortcut.rawValue)
                    }
                }
                .disabled(!model.settings.enableShortcuts)

                Picker("Quick Record Last", selection: $model.settings.quickRecordLastShortcut) {
                    Text("None").tag("")
                    ForEach(AppKeyboardShortcutPresets.quickRecordLast) { shortcut in
                        Text(shortcut.displayName).tag(shortcut.rawValue)
                    }
                }
                .disabled(!model.settings.enableShortcuts)

                Toggle("Launch at Login", isOn: $model.launchAtLogin)
            }

            Section("Updates") {
                Toggle("Check Automatically", isOn: $model.settings.updatePreferences.automaticallyCheckForUpdates)

                Toggle("Install Automatically", isOn: $model.settings.updatePreferences.automaticallyDownloadAndInstall)
                    .disabled(!model.settings.updatePreferences.automaticallyCheckForUpdates)

                Picker("Channel", selection: $model.settings.updatePreferences.channel) {
                    ForEach(UpdateChannel.allCases) { channel in
                        Text(channel.label).tag(channel)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("About") {
                LabeledContent("App", value: model.appMetadata.displayName)
                LabeledContent("Version", value: model.appMetadata.versionSummary)

                if !model.appMetadata.copyright.isEmpty {
                    Text(model.appMetadata.copyright)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        .onChange(of: model.launchAtLogin) {
            model.setLaunchAtLogin(model.launchAtLogin)
        }
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
