import AVFoundation
import AppKit
import LuxelCore
import LuxelPresentation
import SwiftUI

struct LuxelMenu: View {
    static let contentWidth: CGFloat = 300
    static let contentPadding: CGFloat = 6
    static let islandSpacing: CGFloat = 12
    static let deviceIconCellWidth: CGFloat = 42
    static let deviceControlHeight: CGFloat = 36
    static let deviceControlCornerRadius: CGFloat = 18
    static let deviceCircleButtonSize: CGFloat = 36

    @Bindable var model: LuxelMenuModel
    let editorModel: LuxelEditorModel
    let cropperPanelController: LuxelCropperPanelController
    let shortcutController: LuxelShortcutController
    let dismissMenu: @MainActor () -> Void
    let openEditorWindow: @MainActor () -> Void
    let openSettingsWindow: @MainActor () -> Void
    let presentPermissionPrompt: @MainActor (CapturePermissionSource) -> Void

    @State var captureMode: LuxelCaptureMode = .display

    var body: some View {
        VStack(alignment: .leading, spacing: Self.islandSpacing) {
            captureIsland
            statusMessages
            LuxelReplayBufferControls(model: model) { fileURL in
                openRecording(fileURL)
            }
            libraryIsland
        }
        .frame(width: Self.contentWidth, alignment: .leading)
        .padding(Self.contentPadding)
        .fixedSize(horizontal: false, vertical: true)
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
            if model.selectedCaptureTarget?.kind == .window {
                captureMode = .window
            }

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
        .task {
            await model.watchRecordingAutoStops(openRecording: openRecording)
        }
        .task {
            await model.watchAudioInputDeviceUpdates()
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
}

extension LuxelMenu {
    @ViewBuilder
    private var statusMessages: some View {
        let hasMessages =
            model.captureTargetStatusMessage != nil
            || model.recordingStatusMessage != nil
            || model.shouldShowRecordingAudioLevelMeter
            || model.recordingNoticeMessage != nil
            || model.recordingActionErrorMessage != nil
            || model.recoveryStatusMessage != nil

        if hasMessages {
            VStack(alignment: .leading, spacing: 4) {
                if let captureTargetStatusMessage = model.captureTargetStatusMessage {
                    Text(captureTargetStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                LuxelRecordingStatusMessages(model: model)
            }
            .padding(.horizontal, 10)
        }
    }

    private var libraryIsland: some View {
        VStack(spacing: 8) {
            if let recording = model.recentRecordings.first {
                latestRecordingRow(recording)

                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(height: 1)
                    .padding(.horizontal, 8)
            }

            footerControls
                .padding(.horizontal, 3)
                .padding(.bottom, 2)
        }
        .padding(9)
        .luxelMenuIslandBackground(cornerRadius: 26)
    }

    private func latestRecordingRow(_ recording: PastRecording) -> some View {
        HStack(spacing: 11) {
            Button {
                openRecentRecording(recording)
            } label: {
                HStack(spacing: 11) {
                    RecentRecordingThumbnail(recording: recording)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(recentRecordingTitle(for: recording))
                            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.96))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        RecentRecordingMetadataLabel(recording: recording)
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                    .layoutPriority(1)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(recentRecordingOpenTitle(for: recording))

            Button {
                revealRecentRecording(recording)
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
            }
            .buttonStyle(LuxelIslandButtonStyle(cornerRadius: 15, fillOpacity: 0.08))
            .help("Show in Finder")
        }
        .padding(EdgeInsets(top: 6, leading: 7, bottom: 6, trailing: 6))
    }

}
