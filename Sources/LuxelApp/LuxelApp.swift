import AppKit
import LuxelCore
import LuxelPresentation
import Observation
import SwiftUI
import UniformTypeIdentifiers

@main
struct LuxelApp: App {
    @State private var model = LuxelMenuModel()
    @State private var editorModel = LuxelEditorModel()
    @State private var cropperPanelController = LuxelCropperPanelController()
    @State private var shortcutController = LuxelShortcutController()

    var body: some Scene {
        MenuBarExtra {
            LuxelMenu(
                model: model,
                editorModel: editorModel,
                cropperPanelController: cropperPanelController,
                shortcutController: shortcutController
            )
        } label: {
            LuxelMenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        WindowGroup(id: LuxelEditorScene.id) {
            LuxelEditorView(model: editorModel)
        }

        Settings {
            LuxelSettingsView(
                model: model,
                editorModel: editorModel,
                cropperPanelController: cropperPanelController,
                shortcutController: shortcutController
            )
        }
    }
}

private struct LuxelMenuBarLabel: View {
    @Bindable var model: LuxelMenuModel
    @State private var now = Date()

    var body: some View {
        let presentation = model.recordingPresentation(now: now)

        Image(systemName: presentation.menuBarSystemImage)
            .accessibilityLabel(Text(presentation.accessibilityLabel))
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    now = Date()
                }
            }
    }
}

private struct LuxelMenu: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var isImportingRecording = false

    @Bindable var model: LuxelMenuModel
    let editorModel: LuxelEditorModel
    let cropperPanelController: LuxelCropperPanelController
    let shortcutController: LuxelShortcutController

    var body: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Luxel")
                        .font(.headline)
                    Spacer()
                    Image(systemName: model.screenRecordingStatus.symbolName)
                        .foregroundStyle(model.screenRecordingStatus.tint)
                }

                if !model.captureTargets.isEmpty {
                    Picker("Target", selection: $model.selectedCaptureTargetID) {
                        ForEach(model.captureTargets) { target in
                            Label(target.menuTitle, systemImage: target.systemImage)
                                .tag(Optional(target.id))
                        }
                    }
                    .pickerStyle(.menu)
                }

                if let captureTargetStatusMessage = model.captureTargetStatusMessage {
                    Text(captureTargetStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Button {
                    Task {
                        if model.hasActiveRecording {
                            if let stopAction = await model.stopRecording() {
                                switch stopAction {
                                case .openEditor(let fileURL):
                                    openRecording(fileURL)
                                case .quickExported:
                                    break
                                }
                            }
                        } else {
                            await model.startRecordingFromSelectedTarget()
                        }
                    }
                } label: {
                    Label(model.recordButtonTitle, systemImage: model.recordButtonSystemImage)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canUseRecordButton)

                Button {
                    Task {
                        await model.startQuickRecordingFromSelectedTarget()
                    }
                } label: {
                    Label("Quick Record", systemImage: "bolt.circle")
                }
                .disabled(!model.canUseQuickRecordButton)

                Button {
                    Task {
                        await model.startRecordingFromLastCapture()
                    }
                } label: {
                    Label("Record Again", systemImage: "arrow.clockwise")
                }
                .disabled(!model.canUseRecordAgainButton)

                Button {
                    Task {
                        await model.startQuickRecordingFromLastCapture()
                    }
                } label: {
                    Label("Quick Record Last", systemImage: "bolt.circle")
                }
                .disabled(!model.canUseQuickRecordLastButton)

                if model.canPauseOrResumeRecording {
                    Button {
                        Task {
                            await model.pauseOrResumeRecording()
                        }
                    } label: {
                        Label(model.pauseResumeButtonTitle, systemImage: model.pauseResumeButtonSystemImage)
                    }
                    .disabled(!model.canUsePauseResumeButton)
                }

                Button {
                    cropperPanelController.show { draft in
                        Task {
                            await model.startRecording(from: draft)
                        }
                    }
                } label: {
                    Label("Select Area", systemImage: "crop")
                }
                .disabled(!model.canSelectArea)

                if let recordingStatusMessage = model.recordingStatusMessage {
                    Text(recordingStatusMessage)
                        .font(.caption)
                        .foregroundStyle(model.recordingStatusTint)
                        .lineLimit(2)
                }

                if let recordingActionErrorMessage = model.recordingActionErrorMessage {
                    Text(recordingActionErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }

                if let quickExportStatusMessage = model.quickExportStatusMessage {
                    Text(quickExportStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let recoveryStatusMessage = model.recoveryStatusMessage {
                    Text(recoveryStatusMessage)
                        .font(.caption)
                        .foregroundStyle(model.recoveryStatusTint)
                        .lineLimit(2)
                }

                Button {
                    isImportingRecording = true
                } label: {
                    Label("Open Recording", systemImage: "folder")
                }

                VStack(alignment: .leading, spacing: 8) {
                    PermissionRow(
                        title: "Screen Recording",
                        status: model.screenRecordingStatus,
                        actionTitle: model.permissionActionTitle(for: .screenRecording)
                    ) {
                        model.presentPermissionPrompt(for: .screenRecording)
                    }

                    PermissionRow(
                        title: "Microphone",
                        status: model.microphoneStatus,
                        actionTitle: model.permissionActionTitle(for: .microphone)
                    ) {
                        model.presentPermissionPrompt(for: .microphone)
                    }
                }

                if !model.recentRecordings.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        ForEach(model.recentRecordings.prefix(5), id: \.fileURL) { recording in
                            Button {
                                openRecording(recording.fileURL)
                            } label: {
                                Label {
                                    Text(recording.name)
                                        .lineLimit(1)
                                } icon: {
                                    Image(systemName: "clock")
                                }
                            }
                            .help(recording.fileURL.path)
                        }
                    }
                }

                Divider()

                Button {
                    openSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "power")
                }
            }
            .frame(width: 260, alignment: .leading)
        }
        .padding(12)
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
            model.refreshRecentRecordings()
            await model.refreshPermissions()
            await model.refreshCaptureTargets()
            if let recoveredRecording = await model.recoverInterruptedRecording() {
                openRecording(recoveredRecording.fileURL)
            }
        }
        .fileImporter(
            isPresented: $isImportingRecording,
            allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: false
        ) { result in
            openWindow(id: LuxelEditorScene.id)

            switch result {
            case .success(let urls):
                guard let url = urls.first else {
                    return
                }

                openRecording(url)
            case .failure(let error):
                editorModel.reportImportFailure(error)
            }
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
        .alert(
            Text(model.recoveryPrompt?.title ?? "Recording Recovery"),
            isPresented: recoveryPromptPresented,
            presenting: model.recoveryPrompt
        ) { prompt in
            Button("Show in Finder") {
                model.revealRecoveredRecording(prompt)
            }

            Button("Copy Error") {
                model.copyRecoveryError(prompt)
            }

            Button("Close", role: .cancel) {
                model.recoveryPrompt = nil
            }
        } message: { prompt in
            Text(prompt.message)
        }
    }

    private func openRecording(_ url: URL) {
        openWindow(id: LuxelEditorScene.id)

        Task {
            await editorModel.open(fileURL: url, outputDirectory: model.settings.recordingsDirectory)
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

    private var recoveryPromptPresented: Binding<Bool> {
        Binding {
            model.recoveryPrompt != nil
        } set: { isPresented in
            if !isPresented {
                model.recoveryPrompt = nil
            }
        }
    }
}

private struct LuxelSettingsView: View {
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
            model.refreshAudioInputDevices()
        }
        .onChange(of: model.settings) {
            model.saveSettings()
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
        }
    }

    private func openRecording(_ url: URL) {
        openWindow(id: LuxelEditorScene.id)

        Task {
            await editorModel.open(fileURL: url, outputDirectory: model.settings.recordingsDirectory)
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let status: PermissionStatus
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: status.symbolName)
                .foregroundStyle(status.tint)
                .frame(width: 18)

            Text(title)
            Spacer()

            if status == .authorized {
                Text(status.title)
                    .foregroundStyle(.secondary)
            } else {
                Button(actionTitle, systemImage: "lock.open", action: action)
                    .labelStyle(.iconOnly)
                    .help(actionTitle)
            }
        }
        .font(.callout)
    }
}

private struct PermissionPrompt: Equatable {
    let permission: SystemPermission
    let guidance: PermissionGuidance
}

private struct LuxelShortcutInstaller: View {
    let model: LuxelMenuModel
    let cropperPanelController: LuxelCropperPanelController
    let shortcutController: LuxelShortcutController
    let openRecording: (URL) -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task {
                configureShortcut()
            }
            .onChange(of: model.settings.enableShortcuts) {
                configureShortcut()
            }
            .onChange(of: model.settings.triggerCropperShortcut) {
                configureShortcut()
            }
            .onChange(of: model.settings.toggleRecordingShortcut) {
                configureShortcut()
            }
            .onChange(of: model.settings.quickRecordLastShortcut) {
                configureShortcut()
            }
    }

    private func configureShortcut() {
        shortcutController.configure(
            enabled: model.settings.enableShortcuts,
            registrations: [
                LuxelShortcutRegistration(rawShortcut: model.settings.triggerCropperShortcut) {
                    guard model.canSelectArea else {
                        return
                    }

                    cropperPanelController.show { draft in
                        Task {
                            await model.startRecording(from: draft)
                        }
                    }
                },
                LuxelShortcutRegistration(rawShortcut: model.settings.toggleRecordingShortcut) {
                    Task {
                        if model.hasActiveRecording {
                            if let stopAction = await model.stopRecording() {
                                switch stopAction {
                                case .openEditor(let fileURL):
                                    openRecording(fileURL)
                                case .quickExported:
                                    break
                                }
                            }
                        } else if model.canUseRecordAgainButton {
                            await model.startRecordingFromLastCapture()
                        }
                    }
                },
                LuxelShortcutRegistration(rawShortcut: model.settings.quickRecordLastShortcut) {
                    guard model.canUseQuickRecordLastButton else {
                        return
                    }

                    Task {
                        await model.startQuickRecordingFromLastCapture()
                    }
                }
            ]
        )
    }
}

@MainActor
@Observable
private final class LuxelMenuModel {
    var settings: AppSettings
    var launchAtLogin: Bool
    var screenRecordingStatus: PermissionStatus = .unknown
    var microphoneStatus: PermissionStatus = .unknown
    var audioInputDevices: [AudioInputDeviceOption] = [.systemDefault]
    var recentRecordings: [PastRecording] = []
    var captureTargets: [CaptureTargetOption] = []
    var selectedCaptureTargetID: String?
    var captureTargetStatusMessage: String?
    var recordingState: RecordingMenuState = .idle
    var recordingActionErrorMessage: String?
    var quickExportStatusMessage: String?
    var recoveryState: RecordingRecoveryMenuState?
    var permissionPrompt: PermissionPrompt?
    var recoveryPrompt: RecoveryPrompt?
    let appMetadata: AppMetadata

    @ObservationIgnored private let settingsStore: any SettingsStore
    @ObservationIgnored private let permissionClient: any PermissionClient
    @ObservationIgnored private let launchAtLoginService: LaunchAtLoginService
    @ObservationIgnored private let recordingHistoryService: RecordingHistoryService
    @ObservationIgnored private let recordingLifecycleService: RecordingLifecycleService
    @ObservationIgnored private let captureTargetService: CaptureTargetService
    @ObservationIgnored private let audioInputDeviceService: AudioInputDeviceService
    @ObservationIgnored private let fileWorkflowService: ExportedFileWorkflowService
    @ObservationIgnored private let quickExportService: QuickExportService
    @ObservationIgnored private let permissionGuidanceService: PermissionGuidanceService
    @ObservationIgnored private let lastCaptureRecordingPlanner: LastCaptureRecordingPlanner

    init(
        settingsStore: any SettingsStore = LuxelCompositionRoot.settingsStore(),
        permissionClient: any PermissionClient = ApplePermissionClient(),
        launchAtLoginService: LaunchAtLoginService = LaunchAtLoginService(
            client: SMAppServiceLaunchAtLoginClient()
        ),
        recordingHistoryService: RecordingHistoryService = LuxelCompositionRoot.recordingHistoryService(),
        captureTargetService: CaptureTargetService = CaptureTargetService(
            catalog: ScreenCaptureKitCaptureTargetCatalog()
        ),
        audioInputDeviceService: AudioInputDeviceService = AudioInputDeviceService(
            catalog: AVFoundationAudioInputDeviceCatalog()
        ),
        fileWorkflowService: ExportedFileWorkflowService = ExportedFileWorkflowService(
            client: AppKitExportedFileActionClient()
        ),
        quickExportService: QuickExportService? = nil,
        permissionGuidanceService: PermissionGuidanceService = PermissionGuidanceService(),
        lastCaptureRecordingPlanner: LastCaptureRecordingPlanner = LastCaptureRecordingPlanner(),
        appMetadata: AppMetadata = LuxelCompositionRoot.appMetadata,
        recorder: any CaptureRecorder = LuxelCompositionRoot.captureRecorder()
    ) {
        self.settingsStore = settingsStore
        self.permissionClient = permissionClient
        self.launchAtLoginService = launchAtLoginService
        self.recordingHistoryService = recordingHistoryService
        self.captureTargetService = captureTargetService
        self.audioInputDeviceService = audioInputDeviceService
        self.fileWorkflowService = fileWorkflowService
        self.quickExportService = quickExportService
            ?? LuxelCompositionRoot.quickExportService(fileWorkflowService: fileWorkflowService)
        self.permissionGuidanceService = permissionGuidanceService
        self.lastCaptureRecordingPlanner = lastCaptureRecordingPlanner
        self.appMetadata = appMetadata
        self.recordingLifecycleService = RecordingLifecycleService(
            recorder: recorder,
            history: recordingHistoryService
        )
        self.settings = (try? settingsStore.load()) ?? LuxelCompositionRoot.defaultSettings
        self.launchAtLogin = launchAtLoginService.isEnabled()
    }

    var hasActiveRecording: Bool {
        switch recordingState {
        case .recording, .pausing, .paused, .resuming, .stopping:
            return true
        case .idle, .starting, .exporting, .failed:
            return false
        }
    }

    var canUseRecordButton: Bool {
        recordingPresentation().canUsePrimaryAction
    }

    var canPauseOrResumeRecording: Bool {
        recordingPresentation().secondaryActionTitle != nil
    }

    var canUsePauseResumeButton: Bool {
        recordingPresentation().canUseSecondaryAction
    }

    var canUseQuickRecordButton: Bool {
        switch recordingState {
        case .idle, .failed:
            canStartRecording && settings.quickExportPresetID != nil
        case .starting, .recording, .pausing, .paused, .resuming, .stopping, .exporting:
            false
        }
    }

    var canUseRecordAgainButton: Bool {
        switch recordingState {
        case .idle, .failed:
            screenRecordingStatus == .authorized && settings.lastCaptureMemory != nil
        case .starting, .recording, .pausing, .paused, .resuming, .stopping, .exporting:
            false
        }
    }

    var canUseQuickRecordLastButton: Bool {
        canUseRecordAgainButton && settings.quickExportPresetID != nil
    }

    var canSelectArea: Bool {
        switch recordingState {
        case .idle, .failed:
            screenRecordingStatus == .authorized
        case .starting, .recording, .pausing, .paused, .resuming, .stopping, .exporting:
            false
        }
    }

    private var selectedCaptureTarget: CaptureTargetOption? {
        guard let selectedCaptureTargetID else {
            return nil
        }

        return captureTargets.first { $0.id == selectedCaptureTargetID }
    }

    private var lastCaptureFallbackDisplay: CaptureTargetOption? {
        captureTargets.first { $0.kind == .display }
    }

    private var canStartRecording: Bool {
        screenRecordingStatus == .authorized && selectedCaptureTarget != nil
    }

    func recordingPresentation(now: Date = Date()) -> RecordingSessionPresentation {
        RecordingSessionPresentation(
            state: recordingState.presentationState(now: now),
            canStartRecording: canStartRecording,
            showElapsedTimeInMenuBar: settings.showTimeInMenuBar
        )
    }

    var recordButtonTitle: String {
        recordingPresentation().primaryActionTitle
    }

    var recordButtonSystemImage: String {
        recordingPresentation().primaryActionSystemImage
    }

    var pauseResumeButtonTitle: String {
        recordingPresentation().secondaryActionTitle ?? "Pause"
    }

    var pauseResumeButtonSystemImage: String {
        recordingPresentation().secondaryActionSystemImage ?? "pause.circle"
    }

    var recordingStatusMessage: String? {
        switch recordingState {
        case .idle:
            nil
        case .starting:
            "Starting recording"
        case .recording(let recording, _):
            recording.name
        case .pausing(let recording, _):
            "Pausing \(recording.name)"
        case .paused(let recording, _):
            "Paused \(recording.name)"
        case .resuming(let recording, _):
            "Resuming \(recording.name)"
        case .stopping:
            "Finishing recording"
        case .exporting(let snapshot):
            snapshot.actionTitle
        case .failed(let message):
            message
        }
    }

    var recordingStatusTint: Color {
        if case .failed = recordingState {
            return .red
        }

        return .secondary
    }

    var recoveryStatusMessage: String? {
        switch recoveryState {
        case .none:
            nil
        case .recovered(let recording):
            "Recovered \(recording.name)"
        case .knownCorrupt(let fileURL, _):
            "Recovered repairable corrupt recording \(fileURL.lastPathComponent)"
        case .unknownCorrupt(let fileURL, _):
            "Recorded diagnostic for corrupt recording \(fileURL.lastPathComponent)"
        }
    }

    var recoveryStatusTint: Color {
        switch recoveryState {
        case .knownCorrupt, .unknownCorrupt:
            .orange
        case .none, .recovered:
            .secondary
        }
    }

    var recordingsDirectorySummary: String {
        let name = settings.recordingsDirectory.lastPathComponent
        return name.isEmpty ? settings.recordingsDirectory.path : name
    }

    func refreshPermissions() async {
        screenRecordingStatus = await permissionClient.status(for: .screenRecording)
        microphoneStatus = await permissionClient.status(for: .microphone)
    }

    func permissionActionTitle(for permission: SystemPermission) -> String {
        permissionGuidance(for: permission).actionTitle
    }

    func presentPermissionPrompt(for permission: SystemPermission) {
        permissionPrompt = PermissionPrompt(
            permission: permission,
            guidance: permissionGuidance(for: permission)
        )
    }

    func performPermissionAction(_ prompt: PermissionPrompt) async {
        switch prompt.guidance.action {
        case .request:
            _ = await permissionClient.request(prompt.permission)
        case .openSettings:
            await permissionClient.openSettings(for: prompt.permission)
        }

        permissionPrompt = nil
        await refreshPermissions()

        if prompt.permission == .screenRecording {
            await refreshCaptureTargets()
        }
    }

    func saveSettings() {
        try? settingsStore.save(settings)
    }

    func chooseRecordingsDirectory() {
        guard let directory = fileWorkflowService.chooseOutputDirectory(
            currentDirectory: settings.recordingsDirectory
        ) else {
            return
        }

        settings.recordingsDirectory = directory
        saveSettings()
    }

    func refreshAudioInputDevices() {
        audioInputDevices = audioInputDeviceService.availableInputDevices()

        let selectedID = settings.audioInputDeviceID ?? AudioInputDeviceID.systemDefault
        if !audioInputDevices.contains(where: { $0.id == selectedID }) {
            settings.audioInputDeviceID = AudioInputDeviceID.systemDefault
        }
    }

    func refreshRecentRecordings() {
        recentRecordings = Array(recordingHistoryService.getPastRecordings().prefix(5))
    }

    func refreshCaptureTargets() async {
        guard screenRecordingStatus == .authorized else {
            captureTargets = []
            selectedCaptureTargetID = nil
            captureTargetStatusMessage = nil
            return
        }

        do {
            captureTargets = try await captureTargetService.availableTargets()
            if selectedCaptureTarget == nil {
                selectedCaptureTargetID = captureTargets.first?.id
            }
            captureTargetStatusMessage = captureTargets.isEmpty ? "No capture targets found" : nil
        } catch {
            captureTargets = []
            selectedCaptureTargetID = nil
            captureTargetStatusMessage = errorMessage(error)
        }
    }

    func recoverInterruptedRecording() async -> PastRecording? {
        switch await recordingHistoryService.recoverActiveRecording() {
        case .none:
            return nil
        case .playable(let recording):
            recoveryState = .recovered(recording)
            refreshRecentRecordings()
            return recording
        case .knownCorrupt(let fileURL, let reason):
            recoveryState = .knownCorrupt(fileURL: fileURL, reason: reason)
            recoveryPrompt = RecoveryPrompt(fileURL: fileURL, reason: reason, isKnownRepairable: true)
            refreshRecentRecordings()
            return nil
        case .unknownCorrupt(let fileURL, let reason):
            recoveryState = .unknownCorrupt(fileURL: fileURL, reason: reason)
            recoveryPrompt = RecoveryPrompt(fileURL: fileURL, reason: reason, isKnownRepairable: false)
            refreshRecentRecordings()
            return nil
        }
    }

    func revealRecoveredRecording(_ prompt: RecoveryPrompt) {
        fileWorkflowService.revealInFinder(prompt.fileURL)
        recoveryPrompt = nil
    }

    func copyRecoveryError(_ prompt: RecoveryPrompt) {
        fileWorkflowService.copyText(prompt.reason)
        recoveryPrompt = nil
    }

    func startRecording(from draft: CaptureSelectionDraft) async {
        do {
            let target = try draft.captureTarget
            let pixelSize = try draft.pixelSize
            await startRecording(target: target, pixelSize: pixelSize, captureKind: .standard)
        } catch {
            recordingState = .failed(errorMessage(error))
        }
    }

    func startRecordingFromSelectedTarget() async {
        guard let selectedCaptureTarget else {
            recordingState = .failed("No capture target selected")
            return
        }

        await startRecording(
            target: selectedCaptureTarget.target,
            pixelSize: selectedCaptureTarget.pixelSize,
            captureKind: .standard
        )
    }

    func startRecordingFromLastCapture() async {
        await startRecordingFromLastCapture(captureKind: .standard)
    }

    func startQuickRecordingFromLastCapture() async {
        guard let presetID = settings.quickExportPresetID else {
            recordingState = .failed("No quick export preset selected")
            return
        }

        await startRecordingFromLastCapture(captureKind: .quick(presetID: presetID))
    }

    private func startRecordingFromLastCapture(captureKind: QuickCaptureKind) async {
        recordingActionErrorMessage = nil
        quickExportStatusMessage = nil

        do {
            let request = try lastCaptureRecordingPlanner.recordingRequest(
                from: settings.lastCaptureMemory,
                availableTargets: captureTargets,
                fallbackDisplay: lastCaptureFallbackDisplay,
                outputFileURL: try nextRecordingFileURL(now: Date()),
                captureKind: captureKind
            )
            await startRecording(request)
        } catch {
            recordingState = .failed(errorMessage(error))
        }
    }

    func startQuickRecordingFromSelectedTarget() async {
        guard let presetID = settings.quickExportPresetID else {
            recordingState = .failed("No quick export preset selected")
            return
        }

        guard let selectedCaptureTarget else {
            recordingState = .failed("No capture target selected")
            return
        }

        await startRecording(
            target: selectedCaptureTarget.target,
            pixelSize: selectedCaptureTarget.pixelSize,
            captureKind: .quick(presetID: presetID)
        )
    }

    private func startRecording(
        target: CaptureTarget,
        pixelSize: PixelSize,
        captureKind: QuickCaptureKind
    ) async {
        recordingActionErrorMessage = nil
        quickExportStatusMessage = nil

        do {
            let request = try makeRecordingRequest(
                target: target,
                pixelSize: pixelSize,
                captureKind: captureKind
            )
            await startRecording(request)
        } catch {
            recordingState = .failed(errorMessage(error))
        }
    }

    private func startRecording(_ request: RecordingRequest) async {
        recordingActionErrorMessage = nil
        quickExportStatusMessage = nil
        recordingState = .starting

        do {
            let recordingName = request.outputFileURL.deletingPathExtension().lastPathComponent
            let activeRecording = try await recordingLifecycleService.startRecording(
                request,
                name: recordingName
            )
            rememberLastCapture(from: request, capturedAt: activeRecording.date)
            recordingState = .recording(
                activeRecording,
                RecordingMenuClock(startedAt: activeRecording.date)
            )
        } catch {
            recordingState = .failed(errorMessage(error))
        }
    }

    func stopRecording() async -> RecordingStopAction? {
        let previousRecordingState = recordingState
        let captureKind = previousRecordingState.activeRecording?.options.captureKind ?? .standard
        recordingActionErrorMessage = nil
        recordingState = .stopping

        do {
            let recording = try await recordingLifecycleService.stopRecording()
            refreshRecentRecordings()

            switch captureKind {
            case .standard:
                recordingState = .idle
                return .openEditor(recording.fileURL)
            case .quick(let presetID):
                return await runQuickExport(recording: recording, presetID: presetID)
            }
        } catch {
            recordingActionErrorMessage = errorMessage(error)
            recordingState = previousRecordingState
            return nil
        }
    }

    func pauseOrResumeRecording() async {
        switch recordingState {
        case .recording:
            await pauseRecording()
        case .paused:
            await resumeRecording()
        case .idle, .starting, .pausing, .resuming, .stopping, .exporting, .failed:
            return
        }
    }

    private func runQuickExport(recording: PastRecording, presetID: UUID) async -> RecordingStopAction? {
        do {
            let result = try await quickExportService.runQuickExport(
                recording: recording,
                presetID: presetID,
                presets: settings.exportPresets,
                recordingsDirectory: settings.recordingsDirectory
            ) { [weak self] snapshot in
                await MainActor.run {
                    self?.recordingState = .exporting(snapshot)
                }
            }

            recordingState = .idle
            quickExportStatusMessage = "Exported \(result.exportedMedia.fileURL.lastPathComponent)"
            return .quickExported(result.exportedMedia.fileURL)
        } catch {
            recordingState = .idle
            recordingActionErrorMessage = errorMessage(error)
            return nil
        }
    }

    private func pauseRecording() async {
        guard case .recording(let activeRecording, let clock) = recordingState else {
            return
        }

        recordingActionErrorMessage = nil
        recordingState = .pausing(activeRecording, clock)

        do {
            try await recordingLifecycleService.pauseRecording()
            recordingState = .paused(activeRecording, clock.paused(at: Date()))
        } catch {
            recordingActionErrorMessage = errorMessage(error)
            recordingState = .recording(activeRecording, clock)
        }
    }

    private func resumeRecording() async {
        guard case .paused(let activeRecording, let clock) = recordingState else {
            return
        }

        recordingActionErrorMessage = nil
        recordingState = .resuming(activeRecording, clock)

        do {
            try await recordingLifecycleService.resumeRecording()
            recordingState = .recording(activeRecording, clock.resumed(at: Date()))
        } catch {
            recordingActionErrorMessage = errorMessage(error)
            recordingState = .paused(activeRecording, clock)
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLoginService.setEnabled(enabled)
            launchAtLogin = launchAtLoginService.isEnabled()
        } catch {
            launchAtLogin = launchAtLoginService.isEnabled()
        }
    }

    private func makeRecordingRequest(
        target: CaptureTarget,
        pixelSize: PixelSize,
        captureKind: QuickCaptureKind
    ) throws -> RecordingRequest {
        let frameRate = try FrameRate(settings.record60FPS ? 60 : 30)
        let outputFileURL = try nextRecordingFileURL(now: Date())

        return RecordingRequest(
            target: target,
            outputFileURL: outputFileURL,
            pixelSize: pixelSize,
            frameRate: frameRate,
            showCursor: settings.showCursor,
            highlightClicks: settings.highlightClicks,
            audio: recordingAudioMode,
            videoCodec: .h264,
            captureKind: captureKind
        )
    }

    private func rememberLastCapture(from request: RecordingRequest, capturedAt: Date) {
        guard settings.rememberLastCapture else {
            return
        }

        settings.lastCaptureMemory = LastCaptureMemory(request: request, capturedAt: capturedAt)
        saveSettings()
    }

    private var recordingAudioMode: RecordingAudioMode {
        guard settings.recordAudio else {
            return .none
        }

        return .systemAndMicrophone(deviceID: microphoneDeviceID)
    }

    private var microphoneDeviceID: String? {
        guard let audioInputDeviceID = settings.audioInputDeviceID,
              audioInputDeviceID != AudioInputDeviceID.systemDefault
        else {
            return nil
        }

        return audioInputDeviceID
    }

    private func permissionGuidance(for permission: SystemPermission) -> PermissionGuidance {
        permissionGuidanceService.guidance(
            for: permission,
            status: permissionStatus(for: permission)
        )
    }

    private func permissionStatus(for permission: SystemPermission) -> PermissionStatus {
        switch permission {
        case .screenRecording:
            screenRecordingStatus
        case .microphone:
            microphoneStatus
        }
    }

    private func nextRecordingFileURL(now: Date) throws -> URL {
        try FileManager.default.createDirectory(
            at: settings.recordingsDirectory,
            withIntermediateDirectories: true
        )

        let recordingName = RecordingName.timestamped(now: now).value
        return settings.recordingsDirectory
            .appending(path: recordingName)
            .appendingPathExtension("mp4")
    }

    private func errorMessage(_ error: Error) -> String {
        let description = (error as NSError).localizedDescription
        return description.isEmpty ? String(describing: error) : description
    }
}

private enum RecordingMenuState: Equatable {
    case idle
    case starting
    case recording(ActiveRecording, RecordingMenuClock)
    case pausing(ActiveRecording, RecordingMenuClock)
    case paused(ActiveRecording, RecordingMenuClock)
    case resuming(ActiveRecording, RecordingMenuClock)
    case stopping
    case exporting(ExportProgressSnapshot)
    case failed(String)
}

private enum RecordingStopAction {
    case openEditor(URL)
    case quickExported(URL)
}

private struct RecordingMenuClock: Equatable {
    let startedAt: Date
    var pausedAt: Date?
    var accumulatedPausedDuration: TimeInterval

    init(
        startedAt: Date,
        pausedAt: Date? = nil,
        accumulatedPausedDuration: TimeInterval = 0
    ) {
        self.startedAt = startedAt
        self.pausedAt = pausedAt
        self.accumulatedPausedDuration = accumulatedPausedDuration
    }

    func elapsed(at now: Date) -> TimeInterval {
        let endDate = pausedAt ?? now
        return max(0, endDate.timeIntervalSince(startedAt) - accumulatedPausedDuration)
    }

    func paused(at now: Date) -> RecordingMenuClock {
        RecordingMenuClock(
            startedAt: startedAt,
            pausedAt: now,
            accumulatedPausedDuration: accumulatedPausedDuration
        )
    }

    func resumed(at now: Date) -> RecordingMenuClock {
        RecordingMenuClock(
            startedAt: startedAt,
            pausedAt: nil,
            accumulatedPausedDuration: accumulatedPausedDuration + pausedDuration(endingAt: now)
        )
    }

    private func pausedDuration(endingAt now: Date) -> TimeInterval {
        guard let pausedAt else {
            return 0
        }

        return max(0, now.timeIntervalSince(pausedAt))
    }
}

private extension RecordingMenuState {
    func presentationState(now: Date) -> RecordingSessionPresentationState {
        switch self {
        case .idle:
            .idle
        case .starting:
            .starting
        case .recording(_, let clock):
            .recording(elapsed: clock.elapsed(at: now))
        case .pausing(_, let clock):
            .pausing(elapsed: clock.elapsed(at: now))
        case .paused(_, let clock):
            .paused(elapsed: clock.elapsed(at: now))
        case .resuming(_, let clock):
            .resuming(elapsed: clock.elapsed(at: now))
        case .stopping:
            .stopping
        case .exporting(let snapshot):
            .exporting(snapshot)
        case .failed(let message):
            .failed(message)
        }
    }

    var activeRecording: ActiveRecording? {
        switch self {
        case .recording(let recording, _),
             .pausing(let recording, _),
             .paused(let recording, _),
             .resuming(let recording, _):
            recording
        case .idle, .starting, .stopping, .exporting, .failed:
            nil
        }
    }
}

private enum RecordingRecoveryMenuState: Equatable {
    case recovered(PastRecording)
    case knownCorrupt(fileURL: URL, reason: String)
    case unknownCorrupt(fileURL: URL, reason: String)
}

private struct RecoveryPrompt: Equatable {
    let fileURL: URL
    let reason: String
    let isKnownRepairable: Bool

    var title: String {
        isKnownRepairable ? "Repairable Recording Found" : "Corrupt Recording Found"
    }

    var message: String {
        if isKnownRepairable {
            return "Luxel found an interrupted recording with a known corruption signature. The file was left in place so you can inspect it or try a repair workflow later.\n\n\(reason)"
        }

        return "Luxel found an interrupted recording that appears corrupt. A diagnostic was recorded so this failure can be investigated.\n\n\(reason)"
    }
}

private extension CaptureTargetOption {
    var menuTitle: String {
        if let subtitle {
            return "\(title) - \(subtitle)"
        }

        return title
    }

    var systemImage: String {
        switch kind {
        case .display:
            "display"
        case .window:
            "macwindow"
        }
    }
}

enum LuxelCompositionRoot {
    static var appMetadata: AppMetadata {
        BundleAppMetadataReader().read()
    }

    static var defaultSettings: AppSettings {
        AppSettings.defaults(recordingsDirectory: defaultRecordingsDirectory)
    }

    static func settingsStore() -> any SettingsStore {
        UserDefaultsSettingsStore(defaultSettings: defaultSettings)
    }

    static func recordingHistoryService() -> RecordingHistoryService {
        RecordingHistoryService(
            store: recordingHistoryStore(),
            fileSystem: LocalFileSystem(),
            dateProvider: SystemDateProvider(),
            mediaProbe: AVFoundationMediaMetadataReader(),
            diagnosticClient: JSONRecordingDiagnosticClient(fileURL: recordingDiagnosticsFileURL)
        )
    }

    static func recordingHistoryStore() -> any RecordingHistoryStore {
        do {
            return try JSONRecordingHistoryStore(fileURL: recordingHistoryFileURL)
        } catch {
            return InMemoryRecordingHistoryStore()
        }
    }

    static func captureRecorder() -> any CaptureRecorder {
        ScreenCaptureKitRecorder()
    }

    @MainActor
    static func quickExportService(fileWorkflowService: ExportedFileWorkflowService) -> QuickExportService {
        QuickExportService(
            metadataReader: AVFoundationMediaMetadataReader(),
            exportService: ExportService(
                exporter: NativeMediaExporter(),
                fileSystem: LocalFileSystem()
            ),
            fileWorkflowService: fileWorkflowService,
            userNotifier: UserNotificationsNotifier()
        )
    }

    static var defaultRecordingsDirectory: URL {
        let moviesDirectory = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Movies")

        return moviesDirectory.appending(path: "Luxel")
    }

    private static var recordingHistoryFileURL: URL {
        applicationSupportDirectory
            .appending(path: "Luxel")
            .appending(path: "recording-history.json")
    }

    private static var recordingDiagnosticsFileURL: URL {
        applicationSupportDirectory
            .appending(path: "Luxel")
            .appending(path: "corrupt-recordings.jsonl")
    }

    private static var applicationSupportDirectory: URL {
        let applicationSupportDirectory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Application Support")

        return applicationSupportDirectory
    }
}

private extension PermissionStatus {
    var title: String {
        switch self {
        case .notDetermined:
            "Ask"
        case .authorized:
            "Allowed"
        case .denied:
            "Denied"
        case .restricted:
            "Restricted"
        case .unknown:
            "Unknown"
        }
    }

    var symbolName: String {
        switch self {
        case .authorized:
            "checkmark.circle.fill"
        case .denied, .restricted:
            "exclamationmark.triangle.fill"
        case .notDetermined:
            "questionmark.circle"
        case .unknown:
            "circle.dashed"
        }
    }

    var tint: Color {
        switch self {
        case .authorized:
            .green
        case .denied, .restricted:
            .orange
        case .notDetermined, .unknown:
            .secondary
        }
    }
}
