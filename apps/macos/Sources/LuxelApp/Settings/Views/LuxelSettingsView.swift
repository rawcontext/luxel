import AppKit
import Foundation
import LuxelCore
import LuxelPresentation
import SwiftUI

struct LuxelSettingsView: View {
    static let replayBufferLengths: [TimeInterval] = [30, 60, 120, 300]
    static let replayBufferFrameRates = [24, 30]
    static let notchAutoCollapseDurations: [TimeInterval] = [0, 3, 6, 10]

    @Environment(\.openWindow) private var openWindow
    @State private var isShowingAcknowledgements = false
    @State var recordingFrameRateMessage: String?
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

    private var settingsShell: some View {
        settingsChrome
            .tint(.white)
            .preferredColorScheme(.dark)
            .background {
                LuxelGlassWindowBackground()
                    .overlay(LuxelGlassWindowChromeConfigurator())
            }
    }

    private var settingsChrome: some View {
        HStack(spacing: 0) {
            settingsSidebar

            Rectangle()
                .fill(LuxelGlassTheme.rowDivider)
                .frame(width: 1)

            settingsDetail
        }
        .frame(minWidth: 840, minHeight: 660)
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(visibleSettingsPanes) { pane in
                settingsSidebarButton(pane)
            }

            Spacer(minLength: 18)
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 18)
        .frame(width: 208)
    }

    private var visibleSettingsPanes: [LuxelSettingsPane] {
        LuxelSettingsPane.allCases.filter { pane in
            pane != .commandLine
                || AppDistribution.current.capabilities.allowsCommandLineToolInstaller
        }
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
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 20)

                Text(pane.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))

                Spacer(minLength: 8)
            }
            .foregroundStyle(.white.opacity(isSelected ? 0.95 : 0.55))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .background {
                SettingsSidebarSelectionBackground(isSelected: isSelected)
            }
        }
        .buttonStyle(.plain)
        .help(pane.subtitle)
    }

    private var settingsDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                selectedPaneForm
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.top, 16)
            .padding(.bottom, 26)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        case .replayBuffer:
            replayBufferSettingsForm
        case .transcripts:
            transcriptsSettingsForm
        case .commandLine:
            commandLineToolSettingsForm
        case .system:
            systemSettingsForm
        }
    }

    @ViewBuilder
    private var recordingSettingsForm: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsIslandGroup("Capture") {
                settingsToggleRow("Show Cursor", isOn: $model.settings.showCursor)
                    .help("Include the pointer in new recordings.")

                LuxelGlassRowDivider()

                settingsToggleRow("Highlight Clicks", isOn: $model.settings.highlightClicks)
                    .disabled(!model.settings.showCursor)
                    .help("Show a visual ring when clicks happen.")

                LuxelGlassRowDivider()

                recordingFrameRateSettings
            }

            VStack(alignment: .leading, spacing: 2) {
                if let recordingFrameRateMessage {
                    Text(recordingFrameRateMessage)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.red)
                } else {
                    LuxelGlassSectionFooter("Use a whole number from 1 to 60 FPS.")
                }

                LuxelGlassSectionFooter("Cursor and frame rate apply to new recordings.")
            }
            .padding(.leading, 6)
            .padding(.top, 8)
        }

        SettingsIslandGroup("Audio") {
            settingsToggleRow("Record System Audio", isOn: $model.settings.recordSystemAudio)
                .help("Capture sound playing from your Mac.")

            LuxelGlassRowDivider()

            settingsToggleRow("Record Microphone", isOn: $model.settings.recordAudio)
                .help("Capture audio from the selected microphone.")

            LuxelGlassRowDivider()

            SettingsRow("Microphone") {
                SettingsMenuPicker(
                    selection: audioInputDeviceSelection,
                    options: model.audioInputDevices.map(\.id)
                ) { deviceID in
                    audioInputDeviceLabel(deviceID)
                }
            }
            .disabled(!model.settings.recordAudio)
            .opacity(model.settings.recordAudio ? 1 : 0.45)
            .help("Choose which microphone Luxel records.")

            LuxelGlassRowDivider()

            SettingsRow("Audio-Only Format") {
                SettingsMenuPicker(
                    selection: $model.settings.audioOnlyFormat,
                    options: AudioRecordingFormat.allCases
                ) { format in
                    format.label
                }
            }
            .help("Choose the file format for audio-only recordings.")
        }

        SettingsIslandGroup(
            "Camera",
            footer: "Camera controls are available after you choose a camera."
        ) {
            SettingsRow("Camera") {
                SettingsMenuPicker(
                    selection: $model.settings.cameraDeviceID,
                    options: cameraDeviceOptions
                ) { deviceID in
                    cameraDeviceLabel(deviceID)
                }
            }
            .help("Choose the camera overlay for recordings.")

            LuxelGlassRowDivider()

            SettingsRow("Shape") {
                LuxelGlassSegmentedPicker(
                    selection: cameraPreviewShapeSelection,
                    options: Array(CameraOverlayShape.allCases)
                ) { shape in
                    shape.settingsLabel
                }
            }
            .disabled(model.settings.cameraDeviceID == nil)
            .opacity(model.settings.cameraDeviceID == nil ? 0.45 : 1)
            .help("Choose the shape of the camera overlay.")

            LuxelGlassRowDivider()

            SettingsRow("Size") {
                LuxelGlassSegmentedPicker(
                    selection: cameraPreviewSizeSelection,
                    options: Array(CameraPreviewSize.allCases)
                ) { size in
                    size.settingsLabel
                }
            }
            .disabled(model.settings.cameraDeviceID == nil)
            .opacity(model.settings.cameraDeviceID == nil ? 0.45 : 1)
            .help("Choose the size of the camera overlay.")

            LuxelGlassRowDivider()

            settingsToggleRow("Mirror Preview", isOn: cameraPreviewMirroredSelection)
                .disabled(model.settings.cameraDeviceID == nil)
                .help("Flip the camera preview horizontally.")
        }
    }

    private func settingsToggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .toggleStyle(LuxelGlassSwitchToggleStyle())
            .frame(minHeight: LuxelGlassTheme.settingsRowHeight)
    }

    private var cameraDeviceOptions: [String?] {
        var options: [String?] = [nil]
        if let unavailableCameraDeviceID {
            options.append(unavailableCameraDeviceID)
        }
        options.append(contentsOf: model.cameraDevices.map(\.id))
        return options
    }

    private func cameraDeviceLabel(_ deviceID: String?) -> String {
        guard let deviceID else {
            return "Off"
        }

        guard let device = model.cameraDevices.first(where: { $0.id == deviceID }) else {
            return "Unavailable Camera"
        }

        return device.settingsLabel
    }

    private func audioInputDeviceLabel(_ deviceID: String) -> String {
        model.audioInputDevices.first { $0.id == deviceID }?.name ?? deviceID
    }

    @ViewBuilder
    private var outputSettingsForm: some View {
        SettingsIslandGroup(
            "Recordings",
            footer: "Choose where Luxel saves recordings and how the editor behaves after export."
        ) {
            SettingsRow("Folder") {
                Button {
                    model.chooseRecordingsDirectory()
                } label: {
                    SettingsCapsuleButtonLabel(
                        model.recordingsDirectorySummary,
                        systemImage: "folder"
                    )
                }
                .buttonStyle(.plain)
                .help(
                    "Choose where new recordings are saved. Current: \(model.settings.recordingsDirectory.path)"
                )
            }

            LuxelGlassRowDivider()

            settingsToggleRow("Loop Exports", isOn: $model.settings.loopExports)
                .help("Make exported videos loop when the format supports it.")

            LuxelGlassRowDivider()

            settingsToggleRow("Confirm Discard", isOn: $model.settings.confirmDiscard)
                .help("Ask before closing an editor with unsaved changes.")
        }
    }

    @ViewBuilder
    private var presetSettingsForm: some View {
        ExportPresetSettingsSection(settings: $model.settings)

        SettingsIslandGroup("Cropper") {
            settingsToggleRow("Always Show Loupe", isOn: $model.settings.loupeAlwaysOn)
                .help("Keep the precision loupe visible while selecting an area.")

            LuxelGlassRowDivider()

            settingsToggleRow("Dim Other Displays", isOn: $model.settings.dimOtherDisplays)
                .help("Darken inactive displays while choosing a capture area.")

            LuxelGlassRowDivider()

            settingsToggleRow("Restore Last Selection", isOn: $model.settings.restoreLastSelection)
                .help("Start area selection from your previous capture region.")
        }

        CaptureSizePresetSettingsSection(settings: $model.settings)
    }

    @ViewBuilder
    private var shortcutSettingsForm: some View {
        SettingsIslandGroup("Keyboard") {
            settingsToggleRow("Keyboard Shortcuts", isOn: $model.settings.enableShortcuts)
                .help("Enable Luxel's global recording shortcuts.")
        }

        SettingsIslandGroup(
            "Commands",
            footer: "Shortcut conflicts are shown inline when a system shortcut uses the same keys."
        ) {
            LuxelShortcutSearchField(text: $shortcutSearchText)
                .padding(.top, 12)
                .padding(.bottom, 6)
                .help("Filter shortcuts by command name or group.")

            LuxelShortcutSettingsTable(
                commands: visibleShortcutCommands,
                allCommands: shortcutCommands,
                isEnabled: model.settings.enableShortcuts,
                conflictDetector: shortcutConflictDetector,
                editingCommandID: $editingShortcutCommandID
            )
            .padding(.bottom, 12)
            .help("Edit, clear, or reset Luxel keyboard shortcuts.")
        }
    }

    @ViewBuilder
    private var replayBufferSettingsForm: some View {
        let isConfigured = model.settings.replayBufferConfiguration != nil

        SettingsIslandGroup(
            "Replay Buffer",
            footer:
                "Replay buffer uses screen capture permission and stays visible in the menu bar while active."
        ) {
            settingsToggleRow("Enable Replay Buffer", isOn: replayBufferEnabled)
                .help("Continuously keep recent screen video available for clipping.")

            LuxelGlassRowDivider()

            settingsToggleRow(
                "Always Show Replay Buffer Island",
                isOn: $model.settings.alwaysShowReplayBufferIsland
            )
            .help("Keep the replay buffer controls visible in the menu even when replay buffer is off.")

            LuxelGlassRowDivider()

            SettingsRow("Length") {
                SettingsMenuPicker(
                    selection: replayBufferLengthSelection,
                    options: Self.replayBufferLengths
                ) { seconds in
                    replayBufferLengthLabel(seconds)
                }
            }
            .disabled(model.replayBufferState == .clipping)
            .help("Choose how much recent recording history to keep.")

            LuxelGlassRowDivider()

            SettingsRow("Source") {
                settingsValueText("Display with Cursor")
            }
            .help("Replay buffer will capture the display and cursor.")

            LuxelGlassRowDivider()

            SettingsRow("Frame Rate") {
                SettingsMenuPicker(
                    selection: replayBufferFrameRateSelection,
                    options: Self.replayBufferFrameRates
                ) { frameRate in
                    "\(frameRate) FPS"
                }
            }
            .disabled(!isConfigured)
            .opacity(isConfigured ? 1 : 0.45)
            .help("Choose the frame rate for replay buffer clips.")

            LuxelGlassRowDivider()

            settingsToggleRow("Include System Audio", isOn: replayBufferSystemAudioSelection)
                .disabled(!isConfigured)
                .help("Include Mac audio in replay buffer clips.")

            LuxelGlassRowDivider()

            settingsToggleRow("Start Replay When Luxel Launches", isOn: replayBufferResumeOnLaunch)
                .help("Start the replay buffer automatically when Luxel opens.")

            LuxelGlassRowDivider()

            SettingsRow("Clip Opens In") {
                SettingsMenuPicker(
                    selection: $model.settings.replayClipDestination,
                    options: Array(ReplayClipDestination.allCases)
                ) { destination in
                    destination.label
                }
            }
            .disabled(!isConfigured)
            .opacity(isConfigured ? 1 : 0.45)
            .help("Choose what happens after saving a replay clip.")
        }
    }

    @ViewBuilder
    private var notchSettingsForm: some View {
        let notchStatus = model.notchSurfaceStatusPresentation

        SettingsIslandGroup(
            "Notch Surface",
            footer: notchStatus.showsStatus ? notchStatus.detailText : nil
        ) {
            if notchStatus.showsStatus {
                SettingsRow("Status") {
                    settingsValueText(notchStatus.statusText)
                }
                .help("Shows whether the notch surface is available.")

                LuxelGlassRowDivider()
            }

            settingsToggleRow("Enable Notch Surface", isOn: notchSurfaceEnabled)
                .help("Show recording controls around the built-in notch.")

            LuxelGlassRowDivider()

            settingsToggleRow("Idle Quick Actions", isOn: notchIdleHoverActionsEnabled)
                .disabled(!model.settings.notchSurfaceSettings.isEnabled)
                .help("Show quick actions when hovering near the notch while idle.")

            LuxelGlassRowDivider()

            settingsToggleRow("Recording Waveform", isOn: notchWaveformEnabled)
                .disabled(!model.settings.notchSurfaceSettings.isEnabled)
                .help("Show an audio waveform on the notch surface while recording.")

            LuxelGlassRowDivider()

            SettingsRow("Auto Collapse") {
                SettingsMenuPicker(
                    selection: notchAutoCollapseSecondsSelection,
                    options: Self.notchAutoCollapseDurations
                ) { seconds in
                    notchAutoCollapseLabel(seconds)
                }
            }
            .disabled(!model.settings.notchSurfaceSettings.isEnabled)
            .opacity(model.settings.notchSurfaceSettings.isEnabled ? 1 : 0.45)
            .help("Choose how quickly expanded notch controls collapse.")

            LuxelGlassRowDivider()

            settingsToggleRow("Floating HUD Fallback", isOn: notchFloatingHUDFallbackEnabled)
                .disabled(!model.settings.notchSurfaceSettings.isEnabled)
                .help("Use a floating HUD when notch controls are unavailable.")
        }
    }

    private func settingsValueText(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(.white.opacity(0.55))
            .lineLimit(1)
            .truncationMode(.middle)
    }

    @ViewBuilder
    private var commandLineToolSettingsForm: some View {
        CommandLineToolSettingsSection(model: model)
    }

    @ViewBuilder
    private var systemSettingsForm: some View {
        SettingsIslandGroup("Menu Bar") {
            settingsToggleRow("Show Time in Menu Bar", isOn: $model.settings.showTimeInMenuBar)
                .help("Show elapsed recording time in the menu bar.")

            if model.settings.notchSurfaceSettings.isEnabled {
                LuxelGlassRowDivider()

                settingsToggleRow("Hide Menu Bar Icon", isOn: $model.settings.hideMenuBarIcon)
                    .help("Hide Luxel from the menu bar while the notch surface is enabled.")
            }

            LuxelGlassRowDivider()

            settingsToggleRow("Remind About Notifications", isOn: $model.settings.notificationReminder)
                .help("Remind you to silence notifications before recording.")
        }

        SettingsIslandGroup("Startup") {
            settingsToggleRow("Launch at Login", isOn: $model.launchAtLogin)
                .help("Open Luxel automatically when you sign in.")
        }

        updatesSettingsGroup

        SettingsIslandGroup("About") {
            SettingsRow("App") {
                settingsValueText(model.appMetadata.displayName)
            }
            .help("Shows the application name.")

            LuxelGlassRowDivider()

            SettingsRow("Version") {
                settingsValueText(model.appMetadata.versionSummary)
            }
            .help("Shows the installed version and build.")

            LuxelGlassRowDivider()

            SettingsRow {
                Button {
                    isShowingAcknowledgements = true
                } label: {
                    SettingsCapsuleButtonLabel("Acknowledgements", systemImage: "doc.text")
                }
                .buttonStyle(.plain)
                .help("View third-party codec acknowledgements.")
            }
        }

        if !model.appMetadata.copyright.isEmpty {
            LuxelGlassSectionFooter(model.appMetadata.copyright)
                .padding(.leading, 6)
        }
    }

    @ViewBuilder
    private var updatesSettingsGroup: some View {
        let updatePresentation = updateSettingsPresentation

        SettingsIslandGroup("Updates", footer: updatePresentation.networkPolicyText) {
            SettingsRow("Current Version") {
                settingsValueText(model.appMetadata.versionSummary)
            }
            .help("Shows the installed Luxel version.")

            LuxelGlassRowDivider()

            SettingsRow("Status") {
                settingsValueText(updatePresentation.statusText)
            }
            .help("Shows the current update availability.")

            if updatePresentation.showsDeveloperIDUpdateControls {
                LuxelGlassRowDivider()

                settingsToggleRow(
                    "Check Automatically",
                    isOn: $model.settings.updatePreferences.automaticallyCheckForUpdates
                )
                .help("Let Luxel periodically check for updates.")

                LuxelGlassRowDivider()

                settingsToggleRow(
                    "Install Automatically",
                    isOn: $model.settings.updatePreferences.automaticallyDownloadAndInstall
                )
                .disabled(!updatePresentation.automaticInstallToggleEnabled)
                .help("Download and install updates without asking.")

                LuxelGlassRowDivider()

                SettingsRow("Channel") {
                    SettingsMenuPicker(
                        selection: $model.settings.updatePreferences.channel,
                        options: Array(UpdateChannel.allCases)
                    ) { channel in
                        channel.label
                    }
                }
                .help("Choose which update channel Luxel checks.")

                LuxelGlassRowDivider()

                SettingsRow {
                    Button {
                    } label: {
                        SettingsCapsuleButtonLabel("Check Now", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .disabled(!updatePresentation.canCheckNow)
                    .opacity(updatePresentation.canCheckNow ? 1 : 0.45)
                    .help(updatePresentation.checkNowHelp)
                }
            }
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
        SettingsRow("Frame Rate") {
            HStack(spacing: 6) {
                TextField(
                    "FPS",
                    value: recordingFrameRateSelection,
                    formatter: recordingFrameRateFormatter
                )
                .textFieldStyle(.plain)
                .labelsHidden()
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(width: 34)
                .help("Choose the recording frame rate from 1 to 60 FPS.")

                Text("FPS")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .luxelGlassFieldBackground(cornerRadius: 13)
        }
        .help("Choose how many frames per second new recordings use.")
    }
    var recordingFrameRateSelection: Binding<Int> {
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

    var recordingFrameRateFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.allowsFloats = false
        formatter.minimum = 1
        formatter.maximum = 60
        return formatter
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
