import AppKit
import Foundation
import LuxelCore
import LuxelPresentation
import SwiftUI

struct LuxelSettingsView: View {
    private static let replayBufferLengths: [TimeInterval] = [30, 60, 120, 300]
    private static let replayBufferFrameRates = [24, 30]
    private static let notchAutoCollapseDurations: [TimeInterval] = [0, 3, 6, 10]

    @Environment(\.openWindow) private var openWindow
    @State private var isShowingAcknowledgements = false
    @State private var recordingFrameRateMessage: String?
    @State private var selectedPane: LuxelSettingsPane = .recording

    @Bindable var model: LuxelMenuModel
    let editorModel: LuxelEditorModel
    let cropperPanelController: LuxelCropperPanelController
    let shortcutController: LuxelShortcutController
    private let openEditorWindowOverride: (@MainActor () -> Void)?
    private let shortcutConflictDetector = AppKeyboardShortcutConflictDetector()

    init(
        model: LuxelMenuModel,
        editorModel: LuxelEditorModel,
        cropperPanelController: LuxelCropperPanelController,
        shortcutController: LuxelShortcutController,
        openEditorWindow: (@MainActor () -> Void)? = nil
    ) {
        self.model = model
        self.editorModel = editorModel
        self.cropperPanelController = cropperPanelController
        self.shortcutController = shortcutController
        openEditorWindowOverride = openEditorWindow
    }
}

private enum LuxelSettingsPane: CaseIterable, Identifiable {
    case recording
    case output
    case screenshots
    case presets
    case shortcuts
    case experimental
    case system

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .recording:
            "Recording"
        case .output:
            "Output"
        case .screenshots:
            "Screenshots"
        case .presets:
            "Presets"
        case .shortcuts:
            "Shortcuts"
        case .experimental:
            "Experimental"
        case .system:
            "System"
        }
    }

    var subtitle: String {
        switch self {
        case .recording:
            "Capture, audio, and camera controls for new recordings."
        case .output:
            "Where recordings go and how exports behave."
        case .screenshots:
            "Screenshot format, destinations, thumbnail behavior, and shortcuts."
        case .presets:
            "Reusable export presets and cropper size presets."
        case .shortcuts:
            "Keyboard shortcuts and URL automation."
        case .experimental:
            "Preview features that are still being built out."
        case .system:
            "App startup, updates, menu bar behavior, and acknowledgements."
        }
    }

    var systemImage: String {
        switch self {
        case .recording:
            "record.circle"
        case .output:
            "tray.and.arrow.down"
        case .screenshots:
            "camera.viewfinder"
        case .presets:
            "slider.horizontal.3"
        case .shortcuts:
            "keyboard"
        case .experimental:
            "sparkles"
        case .system:
            "gearshape"
        }
    }

    var tint: Color {
        switch self {
        case .recording:
            .blue
        case .output:
            .green
        case .screenshots:
            .cyan
        case .presets:
            .purple
        case .shortcuts:
            .indigo
        case .experimental:
            .orange
        case .system:
            .gray
        }
    }
}

private struct ExperimentalBadge: View {
    var body: some View {
        Text("Experimental")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.orange.opacity(0.14), in: Capsule())
    }
}

private struct SettingsSidebarSelectionBackground: View {
    let isSelected: Bool
    let tint: Color

    var body: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.18))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(tint.opacity(0.14), lineWidth: 1)
                }
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.clear)
        }
    }
}

private struct SettingsGlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    let padding: CGFloat
    let tint: Color
    let content: Content

    init(
        cornerRadius: CGFloat,
        padding: CGFloat,
        tint: Color = .clear,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        if #available(macOS 26.0, *) {
            content
                .padding(padding)
                .glassEffect(.regular.tint(tint), in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .padding(padding)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }
        }
    }
}

extension LuxelSettingsView {
    var body: some View {
        settingsShell
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
            await model.watchAudioInputDeviceUpdates()
        }
        .task {
            model.refreshNotchDisplays()
            await model.watchNotchDisplayUpdates()
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

    @ViewBuilder
    private var settingsShell: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 16) {
                settingsChrome
            }
        } else {
            settingsChrome
        }
    }

    private var settingsChrome: some View {
        HStack(spacing: 0) {
            settingsSidebar

            Divider()

            settingsDetail
        }
        .frame(minWidth: 840, minHeight: 660)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsSidebarHeader

            VStack(alignment: .leading, spacing: 6) {
                ForEach(LuxelSettingsPane.allCases) { pane in
                    settingsSidebarButton(pane)
                }
            }

            Spacer(minLength: 24)

            SettingsGlassCard(cornerRadius: 14, padding: 12, tint: .blue.opacity(0.08)) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.appMetadata.displayName)
                        .font(.caption.weight(.semibold))
                    Text(model.appMetadata.versionSummary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 22)
        .padding(.bottom, 16)
        .frame(width: 232)
        .background(.regularMaterial)
    }

    private var settingsSidebarHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.blue.opacity(0.18))
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.blue)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text("Luxel")
                    .font(.headline.weight(.semibold))
                Text("Settings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 2)
    }

    private func settingsSidebarButton(_ pane: LuxelSettingsPane) -> some View {
        let isSelected = selectedPane == pane

        return Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                selectedPane = pane
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: pane.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? pane.tint : .secondary)
                    .frame(width: 22)

                Text(pane.title)
                    .font(.callout.weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                if pane == .experimental {
                    Text("Beta")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.orange.opacity(0.14), in: Capsule())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .background {
                SettingsSidebarSelectionBackground(isSelected: isSelected, tint: pane.tint)
            }
        }
        .buttonStyle(.plain)
        .help(pane.subtitle)
    }

    private var settingsDetail: some View {
        Form {
            selectedPaneForm
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
    }

    @ViewBuilder
    private var selectedPaneForm: some View {
        switch selectedPane {
        case .recording:
            recordingSettingsForm
        case .output:
            outputSettingsForm
        case .screenshots:
            screenshotSettingsForm
        case .presets:
            presetSettingsForm
        case .shortcuts:
            shortcutSettingsForm
        case .experimental:
            experimentalSettingsForm
        case .system:
            systemSettingsForm
        }
    }

    @ViewBuilder
    private var recordingSettingsForm: some View {
        Section {
            Toggle("Show Cursor", isOn: $model.settings.showCursor)
            Toggle("Highlight Clicks", isOn: $model.settings.highlightClicks)
                .disabled(!model.settings.showCursor)

            recordingFrameRateSettings
        } header: {
            Text("Capture")
        } footer: {
            Text("Cursor and frame rate apply to new recordings.")
        }

        Section {
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
        } header: {
            Text("Audio")
        }

        Section {
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
        } header: {
            Text("Camera")
        } footer: {
            Text("Camera controls are available after you choose a camera.")
        }
    }

    @ViewBuilder
    private var outputSettingsForm: some View {
        Section {
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
        } header: {
            Text("Recordings")
        } footer: {
            Text("Choose where Luxel saves recordings and how the editor behaves after export.")
        }
    }

    @ViewBuilder
    private var screenshotSettingsForm: some View {
        Section {
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
        } header: {
            Text("Capture")
        } footer: {
            Text("At least one screenshot destination stays enabled.")
        }

        Section("Shortcuts") {
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
    }

    @ViewBuilder
    private var presetSettingsForm: some View {
        ExportPresetSettingsSection(settings: $model.settings)

        Section("Cropper") {
            Toggle("Always Show Loupe", isOn: $model.settings.loupeAlwaysOn)
            Toggle("Dim Other Displays", isOn: $model.settings.dimOtherDisplays)
            Toggle("Restore Last Selection", isOn: $model.settings.restoreLastSelection)
        }

        CaptureSizePresetSettingsSection(settings: $model.settings)
    }

    @ViewBuilder
    private var shortcutSettingsForm: some View {
        Section {
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
        } header: {
            Text("Recording Shortcuts")
        } footer: {
            Text("Shortcut conflicts are shown inline when a system shortcut uses the same keys.")
        }

        Section("Automation") {
            Toggle("Allow URL Automation", isOn: $model.settings.allowURLAutomation)
        }
    }

    @ViewBuilder
    private var experimentalSettingsForm: some View {
        Section {
            let isConfigured = model.settings.replayBufferConfiguration != nil

            LabeledContent("Status", value: "Engine Coming Soon")
            Toggle("Enable Replay Buffer", isOn: replayBufferEnabled)

            Picker("Length", selection: replayBufferLengthSelection) {
                ForEach(Self.replayBufferLengths, id: \.self) { seconds in
                    Text(replayBufferLengthLabel(seconds)).tag(seconds)
                }
            }
            .pickerStyle(.menu)
            .disabled(!isConfigured)

            LabeledContent("Source", value: "Display with Cursor")

            Picker("Frame Rate", selection: replayBufferFrameRateSelection) {
                ForEach(Self.replayBufferFrameRates, id: \.self) { frameRate in
                    Text("\(frameRate) FPS").tag(frameRate)
                }
            }
            .pickerStyle(.menu)
            .disabled(!isConfigured)

            Toggle("Include System Audio", isOn: replayBufferSystemAudioSelection)
                .disabled(!isConfigured)

            Toggle("Resume on Launch", isOn: $model.settings.replayBufferResumeOnLaunch)
                .disabled(!isConfigured)

            Picker("Clip Opens In", selection: $model.settings.replayClipDestination) {
                ForEach(ReplayClipDestination.allCases) { destination in
                    Text(destination.label).tag(destination)
                }
            }
            .pickerStyle(.menu)
            .disabled(!isConfigured)

            shortcutPicker(
                "Clip Shortcut",
                selection: $model.settings.clipReplayBufferShortcut,
                presets: AppKeyboardShortcutPresets.clipReplayBuffer
            )
        } header: {
            HStack(spacing: 6) {
                Text("Replay Buffer")
                ExperimentalBadge()
            }
        } footer: {
            Text("Replay buffer capture is not active until the engine lands.")
        }

        Section {
            let notchStatus = model.notchSurfaceStatusPresentation

            LabeledContent("Status", value: notchStatus.statusText)
            Text(notchStatus.detailText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Enable Notch Surface", isOn: notchSurfaceEnabled)
            Toggle("Idle Quick Actions", isOn: notchIdleHoverActionsEnabled)
                .disabled(!model.settings.notchSurfaceSettings.isEnabled)
            Toggle("Recording Waveform", isOn: notchWaveformEnabled)
                .disabled(!model.settings.notchSurfaceSettings.isEnabled)

            Picker("Auto Collapse", selection: notchAutoCollapseSecondsSelection) {
                ForEach(Self.notchAutoCollapseDurations, id: \.self) { seconds in
                    Text(notchAutoCollapseLabel(seconds)).tag(seconds)
                }
            }
            .pickerStyle(.menu)
            .disabled(!model.settings.notchSurfaceSettings.isEnabled)

            Toggle("Recent Shelf", isOn: notchRecentShelfEnabled)
                .disabled(!model.settings.notchSurfaceSettings.isEnabled)
            Toggle("Floating HUD Fallback", isOn: notchFloatingHUDFallbackEnabled)
                .disabled(!model.settings.notchSurfaceSettings.isEnabled)
        } header: {
            HStack(spacing: 6) {
                Text("Notch Surface")
                ExperimentalBadge()
            }
        }
    }

    @ViewBuilder
    private var systemSettingsForm: some View {
        Section("Menu Bar") {
            Toggle("Show Time in Menu Bar", isOn: $model.settings.showTimeInMenuBar)
            Toggle("Remind About Notifications", isOn: $model.settings.notificationReminder)
        }

        Section("Startup") {
            Toggle("Launch at Login", isOn: $model.launchAtLogin)
        }

        if AppDistribution.current.capabilities.allowsCommandLineToolInstaller {
            Section("Command Line Tool") {
                LabeledContent("Install Location") {
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
        }

        Section("Updates") {
            let updatePresentation = updateSettingsPresentation

            LabeledContent("Current Version", value: model.appMetadata.versionSummary)
            LabeledContent("Status", value: updatePresentation.statusText)

            if updatePresentation.showsDeveloperIDUpdateControls {
                Toggle("Check Automatically", isOn: $model.settings.updatePreferences.automaticallyCheckForUpdates)

                Toggle(
                    "Install Automatically",
                    isOn: $model.settings.updatePreferences.automaticallyDownloadAndInstall
                )
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

    @ViewBuilder
    private var recordingFrameRateSettings: some View {
        LabeledContent("Frame Rate") {
            HStack(spacing: 8) {
                TextField(
                    "FPS",
                    value: recordingFrameRateSelection,
                    formatter: recordingFrameRateFormatter
                )
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 56)

                Text("FPS")
                    .foregroundStyle(.secondary)
            }
        }

        if let recordingFrameRateMessage {
            Text(recordingFrameRateMessage)
                .font(.caption)
                .foregroundStyle(.red)
        } else {
            Text("Use a whole number from 1 to 60 FPS.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var replayBufferEnabled: Binding<Bool> {
        Binding {
            model.settings.replayBufferConfiguration != nil
        } set: { isEnabled in
            model.settings.replayBufferConfiguration = isEnabled ? ReplayBufferConfiguration.defaults : nil
        }
    }

    private var recordingFrameRateSelection: Binding<Int> {
        Binding {
            model.settings.recordingFrameRate.framesPerSecond
        } set: { frameRate in
            do {
                try model.settings.setRecordingFrameRate(frameRate)
                recordingFrameRateMessage = nil
            } catch {
                recordingFrameRateMessage = "Use a whole number from 1 to 60 FPS."
            }
        }
    }

    private var recordingFrameRateFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.allowsFloats = false
        formatter.minimum = 1
        formatter.maximum = 60
        return formatter
    }

    private var replayBufferLengthSelection: Binding<TimeInterval> {
        Binding {
            model.settings.replayBufferConfiguration?.bufferLength
                ?? ReplayBufferConfiguration.defaults.bufferLength
        } set: { bufferLength in
            updateReplayBufferConfiguration(bufferLength: bufferLength)
        }
    }

    private var replayBufferFrameRateSelection: Binding<Int> {
        Binding {
            model.settings.replayBufferConfiguration?.frameRate.framesPerSecond
                ?? ReplayBufferConfiguration.defaults.frameRate.framesPerSecond
        } set: { frameRate in
            updateReplayBufferConfiguration(frameRate: frameRate)
        }
    }

    private var replayBufferSystemAudioSelection: Binding<Bool> {
        Binding {
            model.settings.replayBufferConfiguration?.includeSystemAudio
                ?? ReplayBufferConfiguration.defaults.includeSystemAudio
        } set: { includeSystemAudio in
            updateReplayBufferConfiguration(includeSystemAudio: includeSystemAudio)
        }
    }

    private var notchSurfaceEnabled: Binding<Bool> {
        notchSurfaceSettingsBinding(\.isEnabled) { settings, isEnabled in
            try settings.replacing(isEnabled: isEnabled)
        }
    }

    private var notchIdleHoverActionsEnabled: Binding<Bool> {
        notchSurfaceSettingsBinding(\.idleHoverActionsEnabled) { settings, isEnabled in
            try settings.replacing(idleHoverActionsEnabled: isEnabled)
        }
    }

    private var notchWaveformEnabled: Binding<Bool> {
        notchSurfaceSettingsBinding(\.showsWaveform) { settings, isEnabled in
            try settings.replacing(showsWaveform: isEnabled)
        }
    }

    private var notchAutoCollapseSecondsSelection: Binding<TimeInterval> {
        Binding {
            model.settings.notchSurfaceSettings.autoCollapseSeconds
        } set: { seconds in
            updateNotchSurfaceSettings { settings in
                try settings.replacing(autoCollapseSeconds: seconds)
            }
        }
    }

    private var notchRecentShelfEnabled: Binding<Bool> {
        notchSurfaceSettingsBinding(\.showsRecentShelf) { settings, isEnabled in
            try settings.replacing(showsRecentShelf: isEnabled)
        }
    }

    private var notchFloatingHUDFallbackEnabled: Binding<Bool> {
        notchSurfaceSettingsBinding(\.fallbackToFloatingHUDWhenUnavailable) { settings, isEnabled in
            try settings.replacing(fallbackToFloatingHUDWhenUnavailable: isEnabled)
        }
    }

    private func notchSurfaceSettingsBinding(
        _ keyPath: KeyPath<NotchSurfaceSettings, Bool>,
        update: @escaping (NotchSurfaceSettings, Bool) throws -> NotchSurfaceSettings
    ) -> Binding<Bool> {
        Binding {
            model.settings.notchSurfaceSettings[keyPath: keyPath]
        } set: { value in
            updateNotchSurfaceSettings { settings in
                try update(settings, value)
            }
        }
    }

    private func updateNotchSurfaceSettings(
        _ update: (NotchSurfaceSettings) throws -> NotchSurfaceSettings
    ) {
        guard let settings = try? update(model.settings.notchSurfaceSettings) else {
            return
        }

        model.settings.notchSurfaceSettings = settings
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

    private func updateReplayBufferConfiguration(
        bufferLength: TimeInterval? = nil,
        frameRate: Int? = nil,
        includeSystemAudio: Bool? = nil
    ) {
        let configuration = model.settings.replayBufferConfiguration ?? ReplayBufferConfiguration.defaults
        guard let updatedFrameRate = try? FrameRate(frameRate ?? configuration.frameRate.framesPerSecond),
              let updatedConfiguration = try? ReplayBufferConfiguration(
                bufferLength: bufferLength ?? configuration.bufferLength,
                source: configuration.source,
                frameRate: updatedFrameRate,
                includeSystemAudio: includeSystemAudio ?? configuration.includeSystemAudio,
                quality: configuration.quality
              ) else {
            return
        }

        model.settings.replayBufferConfiguration = updatedConfiguration
    }

    private func replayBufferLengthLabel(_ seconds: TimeInterval) -> String {
        switch Int(seconds) {
        case 30:
            "30 Seconds"
        case 60:
            "1 Minute"
        case 120:
            "2 Minutes"
        case 300:
            "5 Minutes"
        default:
            "\(Int(seconds)) Seconds"
        }
    }

    private func notchAutoCollapseLabel(_ seconds: TimeInterval) -> String {
        switch Int(seconds) {
        case 0:
            "Immediately"
        case 3:
            "3 Seconds"
        case 6:
            "6 Seconds"
        case 10:
            "10 Seconds"
        default:
            "\(Int(seconds)) Seconds"
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
        openEditorWindow()

        Task {
            model.configureEditor(editorModel)
            await editorModel.open(fileURL: url, outputDirectory: model.settings.recordingsDirectory)
        }
    }

    private func openEditorWindow() {
        if let openEditorWindowOverride {
            openEditorWindowOverride()
        } else {
            openWindow(id: LuxelEditorScene.id)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}
