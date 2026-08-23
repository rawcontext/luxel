import AppKit
import Foundation
import LuxelCore
import LuxelPresentation
import SwiftUI

struct LuxelSettingsView: View {
    static let replayBufferLengths: [TimeInterval] = [30, 60, 120, 300]
    static let replayBufferFrameRates = [24, 30]
    static let notchAutoCollapseDurations: [TimeInterval] = [0, 3, 6, 10]

    @Environment(\.openWindow) var openWindow
    @State var isShowingAcknowledgements = false
    @State var isShowingSpeechDetectionDisclosure = false
    @State var recordingFrameRateMessage: String?
    @State var editingShortcutCommandID: String?
    @State var shortcutSearchText = ""
    @State var selectedPane: LuxelSettingsPane = .recording
    @Bindable var model: LuxelMenuModel
    let editorModel: LuxelEditorModel
    let cropperPanelController: LuxelCropperPanelController
    let shortcutController: LuxelShortcutController
    let openEditorWindowOverride: (@MainActor () -> Void)?
    let shortcutConflictDetector = AppKeyboardShortcutConflictDetector()

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
                model.scheduleVoiceDetectionReconciliation()
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
            .alert(
                speechDetectionString(
                    "settings.speechDetection.disclosure.title",
                    "Enable Speech Detection Prompts?"
                ),
                isPresented: $isShowingSpeechDetectionDisclosure
            ) {
                Button(speechDetectionString(
                    "settings.speechDetection.disclosure.enable",
                    "Enable"
                )) {
                    Task { await model.approveVoiceDetectionDisclosure() }
                }
                Button(
                    speechDetectionString(
                        "settings.speechDetection.disclosure.cancel",
                        "Cancel"
                    ),
                    role: .cancel
                ) {
                    Task { await model.cancelVoiceDetectionDisclosure() }
                }
            } message: {
                Text(speechDetectionString(
                    "settings.speechDetection.disclosure.body",
                    "Luxel will listen to the selected microphone while it is running and notify "
                        + "you after it detects sustained speech. Detection happens on this Mac, "
                        + "and audio is not saved unless you start recording."
                ))
            }
    }

    var settingsShell: some View {
        settingsChrome
            .tint(.white)
            .preferredColorScheme(.dark)
            .background {
                LuxelGlassWindowBackground()
                    .overlay(LuxelGlassWindowTransparencyConfigurator())
            }
    }

    var settingsChrome: some View {
        HStack(spacing: 0) {
            settingsSidebar

            Rectangle()
                .fill(LuxelGlassTheme.rowDivider)
                .frame(width: 1)

            settingsDetail
        }
        .frame(minWidth: 840, minHeight: 660)
    }

    var settingsSidebar: some View {
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

    var visibleSettingsPanes: [LuxelSettingsPane] {
        LuxelSettingsPane.allCases
    }

    func settingsSidebarButton(_ pane: LuxelSettingsPane) -> some View {
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

    var settingsDetail: some View {
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
    var selectedPaneForm: some View {
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

}
