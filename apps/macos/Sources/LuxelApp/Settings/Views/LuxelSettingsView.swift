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
    @State private var editingShortcutCommandID: String?
    @State private var shortcutSearchText = ""
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
                Task {
                    await model.refreshNotchSurface()
                }
            }
            .onChange(of: model.settings.enableShortcuts) {
                if !model.settings.enableShortcuts {
                    editingShortcutCommandID = nil
                }
            }
            .onChange(of: selectedPane) {
                if selectedPane != .shortcuts {
                    editingShortcutCommandID = nil
                }
            }
            .onChange(of: model.launchAtLogin) {
                model.setLaunchAtLogin(model.launchAtLogin)
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
            VStack(alignment: .leading, spacing: 6) {
                ForEach(LuxelSettingsPane.allCases) { pane in
                    settingsSidebarButton(pane)
                }
            }

            Spacer(minLength: 24)
        }
        .padding(.horizontal, 16)
        .padding(.top, 22)
        .padding(.bottom, 16)
        .frame(width: 232)
        .background(.regularMaterial)
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
                    .foregroundStyle(.secondary)
                    .frame(width: 22)

                Text(pane.title)
                    .font(.callout.weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .background {
                SettingsSidebarSelectionBackground(isSelected: isSelected)
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
        case .presets:
            presetSettingsForm
        case .shortcuts:
            shortcutSettingsForm
        case .notch:
            notchSettingsForm
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
                .help("Include the pointer in new recordings.")
            Toggle("Highlight Clicks", isOn: $model.settings.highlightClicks)
                .disabled(!model.settings.showCursor)
                .help("Show a visual ring when clicks happen.")

            recordingFrameRateSettings
        } header: {
            Text("Capture")
        } footer: {
            Text("Cursor and frame rate apply to new recordings.")
        }

        Section {
            Toggle("Record System Audio", isOn: $model.settings.recordSystemAudio)
                .help("Capture sound playing from your Mac.")
            Toggle("Record Microphone", isOn: $model.settings.recordAudio)
                .help("Capture audio from the selected microphone.")
            Picker("Microphone", selection: audioInputDeviceSelection) {
                ForEach(model.audioInputDevices) { device in
                    Text(device.name).tag(device.id)
                }
            }
            .disabled(!model.settings.recordAudio)
            .help("Choose which microphone Luxel records.")

            Picker("Audio-Only Format", selection: $model.settings.audioOnlyFormat) {
                ForEach(AudioRecordingFormat.allCases, id: \.self) { format in
                    Text(format.label).tag(format)
                }
            }
            .pickerStyle(.menu)
            .help("Choose the file format for audio-only recordings.")
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
            .help("Choose the camera overlay for recordings.")

            Picker("Shape", selection: cameraPreviewShapeSelection) {
                ForEach(CameraOverlayShape.allCases, id: \.self) { shape in
                    Text(shape.settingsLabel).tag(shape)
                }
            }
            .pickerStyle(.segmented)
            .disabled(model.settings.cameraDeviceID == nil)
            .help("Choose the shape of the camera overlay.")

            Picker("Size", selection: cameraPreviewSizeSelection) {
                ForEach(CameraPreviewSize.allCases, id: \.self) { size in
                    Text(size.settingsLabel).tag(size)
                }
            }
            .pickerStyle(.segmented)
            .disabled(model.settings.cameraDeviceID == nil)
            .help("Choose the size of the camera overlay.")

            Toggle("Mirror Preview", isOn: cameraPreviewMirroredSelection)
                .disabled(model.settings.cameraDeviceID == nil)
                .help("Flip the camera preview horizontally.")
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
                .help(
                    "Choose where new recordings are saved. Current: \(model.settings.recordingsDirectory.path)"
                )
            }

            Toggle("Loop Exports", isOn: $model.settings.loopExports)
                .help("Make exported videos loop when the format supports it.")
            Toggle("Confirm Discard", isOn: $model.settings.confirmDiscard)
                .help("Ask before closing an editor with unsaved changes.")
        } header: {
            Text("Recordings")
        } footer: {
            Text("Choose where Luxel saves recordings and how the editor behaves after export.")
        }

        Section {
            Toggle(
                "Segment Transcript Turns",
                isOn: $model.settings.transcriptTurnSegmentationEnabled
            )
            .help("Use Apple Intelligence to group audio transcripts into display turns.")
        } header: {
            Text("Transcripts")
        } footer: {
            Text("Turn this off for faster raw transcripts on long audio recordings.")
        }
    }

    @ViewBuilder
    private var presetSettingsForm: some View {
        ExportPresetSettingsSection(settings: $model.settings)

        Section("Cropper") {
            Toggle("Always Show Loupe", isOn: $model.settings.loupeAlwaysOn)
                .help("Keep the precision loupe visible while selecting an area.")
            Toggle("Dim Other Displays", isOn: $model.settings.dimOtherDisplays)
                .help("Darken inactive displays while choosing a capture area.")
            Toggle("Restore Last Selection", isOn: $model.settings.restoreLastSelection)
                .help("Start area selection from your previous capture region.")
        }

        CaptureSizePresetSettingsSection(settings: $model.settings)
    }

    @ViewBuilder
    private var shortcutSettingsForm: some View {
        Section {
            Toggle("Keyboard Shortcuts", isOn: $model.settings.enableShortcuts)
                .help("Enable Luxel's global recording shortcuts.")
        } header: {
            Text("Keyboard")
        }

        Section {
            LuxelShortcutSearchField(text: $shortcutSearchText)
                .padding(.bottom, 6)
                .help("Filter shortcuts by command name or group.")

            LuxelShortcutSettingsTable(
                commands: visibleShortcutCommands,
                allCommands: shortcutCommands,
                isEnabled: model.settings.enableShortcuts,
                conflictDetector: shortcutConflictDetector,
                editingCommandID: $editingShortcutCommandID
            )
            .help("Edit, clear, or reset Luxel keyboard shortcuts.")
        } header: {
            Text("Commands")
        } footer: {
            Text("Shortcut conflicts are shown inline when a system shortcut uses the same keys.")
        }
    }

    @ViewBuilder
    private var experimentalSettingsForm: some View {
        Section {
            let isConfigured = model.settings.replayBufferConfiguration != nil

            LabeledContent("Status", value: "Engine Coming Soon")
                .help("Replay buffer capture is not implemented yet.")
            Toggle("Enable Replay Buffer", isOn: replayBufferEnabled)
                .help("Prepare settings for saving recent recording history.")

            Picker("Length", selection: replayBufferLengthSelection) {
                ForEach(Self.replayBufferLengths, id: \.self) { seconds in
                    Text(replayBufferLengthLabel(seconds)).tag(seconds)
                }
            }
            .pickerStyle(.menu)
            .disabled(!isConfigured)
            .help("Choose how much recent recording history to keep.")

            LabeledContent("Source", value: "Display with Cursor")
                .help("Replay buffer will capture the display and cursor.")

            Picker("Frame Rate", selection: replayBufferFrameRateSelection) {
                ForEach(Self.replayBufferFrameRates, id: \.self) { frameRate in
                    Text("\(frameRate) FPS").tag(frameRate)
                }
            }
            .pickerStyle(.menu)
            .disabled(!isConfigured)
            .help("Choose the frame rate for replay buffer clips.")

            Toggle("Include System Audio", isOn: replayBufferSystemAudioSelection)
                .disabled(!isConfigured)
                .help("Include Mac audio in replay buffer clips.")

            Toggle("Resume on Launch", isOn: $model.settings.replayBufferResumeOnLaunch)
                .disabled(!isConfigured)
                .help("Restart the replay buffer when Luxel opens.")

            Picker("Clip Opens In", selection: $model.settings.replayClipDestination) {
                ForEach(ReplayClipDestination.allCases) { destination in
                    Text(destination.label).tag(destination)
                }
            }
            .pickerStyle(.menu)
            .disabled(!isConfigured)
            .help("Choose what happens after saving a replay clip.")

        } header: {
            HStack(spacing: 6) {
                Text("Replay Buffer")
                ExperimentalBadge()
            }
        } footer: {
            Text("Replay buffer capture is not active until the engine lands.")
        }

    }

    @ViewBuilder
    private var notchSettingsForm: some View {
        Section("Notch Surface") {
            let notchStatus = model.notchSurfaceStatusPresentation

            if notchStatus.showsStatus {
                LabeledContent("Status", value: notchStatus.statusText)
                    .help("Shows whether the notch surface is available.")
                Text(notchStatus.detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle("Enable Notch Surface", isOn: notchSurfaceEnabled)
                .help("Show recording controls around the built-in notch.")
            Toggle("Idle Quick Actions", isOn: notchIdleHoverActionsEnabled)
                .disabled(!model.settings.notchSurfaceSettings.isEnabled)
                .help("Show quick actions when hovering near the notch while idle.")
            Toggle("Recording Waveform", isOn: notchWaveformEnabled)
                .disabled(!model.settings.notchSurfaceSettings.isEnabled)
                .help("Show an audio waveform on the notch surface while recording.")

            Picker("Auto Collapse", selection: notchAutoCollapseSecondsSelection) {
                ForEach(Self.notchAutoCollapseDurations, id: \.self) { seconds in
                    Text(notchAutoCollapseLabel(seconds)).tag(seconds)
                }
            }
            .pickerStyle(.menu)
            .disabled(!model.settings.notchSurfaceSettings.isEnabled)
            .help("Choose how quickly expanded notch controls collapse.")

            Toggle("Floating HUD Fallback", isOn: notchFloatingHUDFallbackEnabled)
                .disabled(!model.settings.notchSurfaceSettings.isEnabled)
                .help("Use a floating HUD when notch controls are unavailable.")
        }
    }

    @ViewBuilder
    private var systemSettingsForm: some View {
        Section("Menu Bar") {
            Toggle("Show Time in Menu Bar", isOn: $model.settings.showTimeInMenuBar)
                .help("Show elapsed recording time in the menu bar.")
            if model.settings.notchSurfaceSettings.isEnabled {
                Toggle("Hide Menu Bar Icon", isOn: $model.settings.hideMenuBarIcon)
                    .help("Hide Luxel from the menu bar while the notch surface is enabled.")
            }
            Toggle("Remind About Notifications", isOn: $model.settings.notificationReminder)
                .help("Remind you to silence notifications before recording.")
        }

        Section("Startup") {
            Toggle("Launch at Login", isOn: $model.launchAtLogin)
                .help("Open Luxel automatically when you sign in.")
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
                .help("Install the command line helper for terminal automation.")

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
                .help("Shows the installed Luxel version.")
            LabeledContent("Status", value: updatePresentation.statusText)
                .help("Shows the current update availability.")

            if updatePresentation.showsDeveloperIDUpdateControls {
                Toggle(
                    "Check Automatically",
                    isOn: $model.settings.updatePreferences.automaticallyCheckForUpdates
                )
                .help("Let Luxel periodically check for updates.")

                Toggle(
                    "Install Automatically",
                    isOn: $model.settings.updatePreferences.automaticallyDownloadAndInstall
                )
                .disabled(!updatePresentation.automaticInstallToggleEnabled)
                .help("Download and install updates without asking.")

                Picker("Channel", selection: $model.settings.updatePreferences.channel) {
                    ForEach(UpdateChannel.allCases) { channel in
                        Text(channel.label).tag(channel)
                    }
                }
                .pickerStyle(.menu)
                .help("Choose which update channel Luxel checks.")

                Button {
                } label: {
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
                .help("Shows the application name.")
            LabeledContent("Version", value: model.appMetadata.versionSummary)
                .help("Shows the installed version and build.")

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
            .help("View third-party codec acknowledgements.")
        }
    }

    private var unavailableCameraDeviceID: String? {
        guard let cameraDeviceID = model.settings.cameraDeviceID,
              !model.cameraDevices.contains(where: { $0.id == cameraDeviceID })
        else {
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

    private var visibleShortcutCommands: [LuxelShortcutSettingsCommand] {
        let searchText = shortcutSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return shortcutCommands.filter { $0.matchesSearch(searchText) }
    }

    private var shortcutCommands: [LuxelShortcutSettingsCommand] {
        [
            shortcutCommand(
                id: "select-area",
                title: "Select Area",
                detail: "Choose a screen area to record.",
                group: "Recording",
                selection: $model.settings.triggerCropperShortcut,
                presets: AppKeyboardShortcutPresets.capture
            ),
            shortcutCommand(
                id: "toggle-recording",
                title: "Toggle Recording",
                detail: "Start or stop recording.",
                group: "Recording",
                selection: $model.settings.toggleRecordingShortcut,
                presets: AppKeyboardShortcutPresets.toggleRecording
            ),
            shortcutCommand(
                id: "record-active-window",
                title: "Record Active Window",
                detail: "Record the frontmost window.",
                group: "Recording",
                selection: $model.settings.recordActiveWindowShortcut,
                presets: AppKeyboardShortcutPresets.recordActiveWindow
            ),
            shortcutCommand(
                id: "record-fullscreen",
                title: "Record Fullscreen",
                detail: "Record the current display.",
                group: "Recording",
                selection: $model.settings.recordFullscreenShortcut,
                presets: AppKeyboardShortcutPresets.recordFullscreen
            ),
            shortcutCommand(
                id: "audio-only",
                title: "Audio Only",
                detail: "Start an audio-only recording.",
                group: "Recording",
                selection: $model.settings.audioOnlyRecordingShortcut,
                presets: AppKeyboardShortcutPresets.audioOnlyRecording
            ),
            shortcutCommand(
                id: "quick-record-last",
                title: "Quick Record Last",
                detail: "Record the previous capture target with quick export settings.",
                group: "Recording",
                selection: $model.settings.quickRecordLastShortcut,
                presets: AppKeyboardShortcutPresets.quickRecordLast
            ),
            shortcutCommand(
                id: "clip-replay-buffer",
                title: "Clip Replay Buffer",
                detail: "Save the recent replay buffer.",
                group: "Replay Buffer",
                selection: $model.settings.clipReplayBufferShortcut,
                presets: AppKeyboardShortcutPresets.clipReplayBuffer
            )
        ]
    }

    private func shortcutCommand(
        id: String,
        title: String,
        detail: String,
        group: String,
        selection: Binding<String>,
        presets: [AppKeyboardShortcut]
    ) -> LuxelShortcutSettingsCommand {
        LuxelShortcutSettingsCommand(
            id: id,
            title: title,
            detail: detail,
            searchGroup: group,
            selection: selection,
            defaultRawValue: presets.first?.rawValue ?? ""
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
                .help("Choose the recording frame rate from 1 to 60 FPS.")

                Text("FPS")
                    .foregroundStyle(.secondary)
            }
        }
        .help("Choose how many frames per second new recordings use.")

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
            model.settings.replayBufferConfiguration =
                isEnabled ? ReplayBufferConfiguration.defaults : nil
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
            model.settings.audioInputDeviceName =
                model.audioInputDevices
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
        let configuration =
            model.settings.replayBufferConfiguration ?? ReplayBufferConfiguration.defaults
        guard
            let updatedFrameRate = try? FrameRate(frameRate ?? configuration.frameRate.framesPerSecond),
            let updatedConfiguration = try? ReplayBufferConfiguration(
                bufferLength: bufferLength ?? configuration.bufferLength,
                source: configuration.source,
                frameRate: updatedFrameRate,
                includeSystemAudio: includeSystemAudio ?? configuration.includeSystemAudio,
                quality: configuration.quality
            )
        else {
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

    private func openRecording(_ url: URL) {
        openEditorWindow()

        Task {
            model.configureEditor(editorModel)
            await editorModel.open(
                fileURL: url,
                outputDirectory: model.settings.recordingsDirectory,
                outputDirectoryBookmark: model.settings.recordingsDirectoryBookmark,
                transcriptSourceContext: model.transcriptSourceContext(for: url)
            )
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
