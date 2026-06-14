import AppKit
import LuxelPresentation
import SwiftUI
import UniformTypeIdentifiers

struct LuxelMenu: View {
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
                LuxelMenuHeader(model: model)
                LuxelCaptureTargetPicker(model: model)
                LuxelRecordingControls(
                    model: model,
                    cropperPanelController: cropperPanelController,
                    openRecording: openRecording
                )
                LuxelRecordingStatusMessages(model: model)

                Button {
                    isImportingRecording = true
                } label: {
                    Label("Open Recording", systemImage: "folder")
                }

                LuxelPermissionSummary(model: model)
                LuxelRecentRecordings(model: model, openRecording: openRecording)

                Divider()

                Button {
                    openSettings()
                    NSApplication.shared.activate(ignoringOtherApps: true)
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
        .onAppear {
            Task {
                await refreshMenuState()
            }
        }
        .onOpenURL { url in
            Task {
                await model.handleAutomationURL(
                    url,
                    openSettings: openLuxelSettings,
                    openRecording: openRecording
                )
            }
        }
        .task {
            await refreshMenuState()
            if let recoveredRecording = await model.recoverInterruptedRecording() {
                openRecording(recoveredRecording.fileURL)
            }
        }
        .task(id: model.recordingAudioLevelMonitorTaskID) {
            await model.watchAudioLevels(onlyWhenRecording: true)
        }
        .task {
            await model.watchRecordingAutoStops(openRecording: openRecording)
        }
        .fileImporter(
            isPresented: $isImportingRecording,
            allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: false
        ) { result in
            openWindow(id: LuxelEditorScene.id)
            NSApplication.shared.activate(ignoringOtherApps: true)

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
        .alert(
            Text(model.automationPrompt?.prompt.title ?? "URL Automation"),
            isPresented: automationPromptPresented,
            presenting: model.automationPrompt
        ) { _ in
            Button("Allow Once") {
                Task {
                    await model.approveAutomationPrompt(
                        alwaysAllow: false,
                        openSettings: openLuxelSettings,
                        openRecording: openRecording
                    )
                }
            }

            Button("Always Allow") {
                Task {
                    await model.approveAutomationPrompt(
                        alwaysAllow: true,
                        openSettings: openLuxelSettings,
                        openRecording: openRecording
                    )
                }
            }

            Button("Deny", role: .cancel) {
                model.denyAutomationPrompt()
            }
        } message: { prompt in
            Text(prompt.prompt.message)
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

    private func openLuxelSettings() {
        openSettings()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func refreshMenuState() async {
        model.refreshRecentRecordings()
        await model.refreshPermissions()
        await model.refreshCaptureTargets()
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

    private var automationPromptPresented: Binding<Bool> {
        Binding {
            model.automationPrompt != nil
        } set: { isPresented in
            if !isPresented {
                model.denyAutomationPrompt()
            }
        }
    }
}
