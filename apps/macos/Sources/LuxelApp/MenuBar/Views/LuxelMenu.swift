import AVFoundation
import AppKit
import LuxelCore
import LuxelPresentation
import SwiftUI

struct LuxelMenu: View {
    private static let contentWidth: CGFloat = 300
    private static let contentPadding: CGFloat = 6
    private static let islandSpacing: CGFloat = 12
    private static let deviceIconCellWidth: CGFloat = 42
    private static let deviceControlHeight: CGFloat = 36
    private static let deviceControlCornerRadius: CGFloat = 18
    private static let deviceCircleButtonSize: CGFloat = 36

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

    private var footerControls: some View {
        HStack(spacing: 0) {
            systemAudioFooterControl

            Spacer(minLength: 6)

            microphoneFooterControl

            Spacer(minLength: 6)

            cameraFooterControl

            Spacer(minLength: 6)

            overflowFooterMenu
        }
        .frame(maxWidth: .infinity)
    }

    private var overflowFooterMenu: some View {
        Menu {
            overflowMenuItems
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: Self.deviceCircleButtonSize, height: Self.deviceCircleButtonSize)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .luxelIslandControlGroupBackground(cornerRadius: Self.deviceControlCornerRadius)
        .frame(height: Self.deviceControlHeight)
    }

    private var microphoneFooterControl: some View {
        let presentation = model.sourcePermissionPresentation(for: .microphone)

        return HStack(spacing: 0) {
            Button {
                handleMicrophoneFooterAction(presentation)
            } label: {
                footerSourceIcon(presentation)
                    .frame(width: Self.deviceIconCellWidth, height: Self.deviceControlHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(
                LuxelIslandCellButtonStyle(
                    corners: .leading,
                    cornerRadius: Self.deviceControlCornerRadius
                )
            )
            .help(presentation.message)
            .accessibilityLabel("Microphone")
            .accessibilityValue(presentation.statusTitle)

            footerControlDivider

            microphoneFooterPicker
        }
        .luxelIslandControlGroupBackground(cornerRadius: Self.deviceControlCornerRadius)
    }

    private var cameraFooterControl: some View {
        let presentation = model.sourcePermissionPresentation(for: .camera)

        return HStack(spacing: 0) {
            Button {
                handleCameraFooterAction(presentation)
            } label: {
                footerSourceIcon(presentation)
                    .frame(width: Self.deviceIconCellWidth, height: Self.deviceControlHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(
                LuxelIslandCellButtonStyle(
                    corners: .leading,
                    cornerRadius: Self.deviceControlCornerRadius
                )
            )
            .help(presentation.message)
            .accessibilityLabel("Camera")
            .accessibilityValue(presentation.statusTitle)

            footerControlDivider

            cameraFooterPicker
        }
        .luxelIslandControlGroupBackground(cornerRadius: Self.deviceControlCornerRadius)
    }

    private var footerControlDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.12))
            .frame(width: 1, height: 18)
    }

    private var systemAudioFooterControl: some View {
        let presentation = model.sourcePermissionPresentation(for: .systemAudio)

        return HStack(spacing: 0) {
            Button {
                handleSystemAudioFooterAction(presentation)
            } label: {
                footerSourceIcon(presentation)
                    .frame(width: Self.deviceIconCellWidth, height: Self.deviceControlHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(
                LuxelIslandCellButtonStyle(
                    corners: .leading,
                    cornerRadius: Self.deviceControlCornerRadius
                )
            )
            .help(presentation.message)
            .accessibilityLabel("System Audio")
            .accessibilityValue(presentation.statusTitle)

            footerControlDivider

            systemAudioFooterPicker(presentation)
        }
        .luxelIslandControlGroupBackground(cornerRadius: Self.deviceControlCornerRadius)
    }

    private func systemAudioFooterPicker(
        _ presentation: CaptureSourcePermissionPresentation
    ) -> some View {
        Menu {
            Picker("Audio Source", selection: systemAudioFooterSelection(presentation)) {
                Text("Off").tag(false)
                Text("System Audio").tag(true)
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "chevron.down")
                .labelStyle(.iconOnly)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 30, height: Self.deviceControlHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(
            LuxelIslandCellButtonStyle(
                corners: .trailing,
                cornerRadius: Self.deviceControlCornerRadius
            )
        )
        .frame(height: Self.deviceControlHeight)
        .help("Choose audio source")
        .accessibilityLabel("Choose Audio Source")
        .accessibilityValue(model.settings.recordSystemAudio ? "System Audio" : "Off")
    }

    private func systemAudioFooterSelection(
        _ presentation: CaptureSourcePermissionPresentation
    ) -> Binding<Bool> {
        Binding {
            model.settings.recordSystemAudio
        } set: { isEnabled in
            guard isEnabled else {
                model.settings.recordSystemAudio = false
                model.saveSettings()
                return
            }

            switch presentation.phase {
            case .ready, .offByUser:
                model.settings.recordSystemAudio = true
                model.saveSettings()
            case .checking, .needsGrant, .requestInProgress, .openSettings, .grantedNeedsRelaunch,
                 .pausedByMacOS, .blocked:
                presentPermissionPrompt(.systemAudio)
            }
        }
    }

    private func footerSourceIcon(
        _ presentation: CaptureSourcePermissionPresentation
    ) -> some View {
        Image(systemName: presentation.systemImage)
            .labelStyle(.iconOnly)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white.opacity(presentation.phase == .ready ? 0.92 : 0.42))
    }

    @ViewBuilder
    private var overflowMenuItems: some View {
        Button {
            openLuxelSettings()
        } label: {
            Label("Settings", systemImage: "gearshape")
        }

        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Label("Quit Luxel", systemImage: "power")
        }
    }

    func showAreaCapturePicker() {
        model.refreshCameraDevices()
        cropperPanelController.show(
            countdownDuration: model.settings.defaultCountdown,
            stopAfterDuration: model.settings.lastStopAfter,
            canRecordAudio: model.microphoneStatus == .authorized,
            cameraConfiguration: model.cropperCameraConfiguration(),
            quickRecordingConfiguration: model.cropperQuickRecordingConfiguration(),
            selectionPresetConfiguration: model.cropperSelectionPresetConfiguration(),
            restoreSelectionConfiguration: model.cropperRestoreSelectionConfiguration(),
            recordAudio: model.captureCapabilities.microphoneTrackAvailable,
            loupeAlwaysOn: model.settings.loupeAlwaysOn,
            dimOtherDisplays: model.settings.dimOtherDisplays,
            showsNotificationReminder: false,
            onCountdownDurationChange: { duration in
                model.settings.defaultCountdown = duration
                model.saveSettings()
            },
            onStopAfterDurationChange: { duration in
                model.settings.lastStopAfter = duration
                model.saveSettings()
            },
            onRecordAudioChange: { isEnabled in
                guard !isEnabled || model.microphoneStatus == .authorized else {
                    presentPermissionPrompt(.microphone)
                    return
                }

                model.settings.recordAudio = isEnabled
                model.saveSettings()
            },
            onCameraSelectionChange: { deviceID in
                Task {
                    await model.setCameraDeviceFromCropper(deviceID)
                }
            },
            onCameraPreviewStyleChange: { style in
                Task {
                    await model.setCameraPreviewStyleFromCropper(style)
                }
            },
            onNotificationReminderDismiss: {
                model.dismissNotificationReminder()
            },
            onQuickSelect: { draft, presetID in
                Task {
                    await model.startQuickRecording(from: draft, presetID: presetID)
                }
            },
            onSelect: { draft in
                Task {
                    await model.startRecording(from: draft)
                }
            }
        )
    }

    func startAfterDismissingMenu(_ action: @escaping @MainActor () async -> Void) {
        Task { @MainActor in
            dismissMenu()
            await Task.yield()
            await action()
        }
    }

    func openRecording(_ url: URL) {
        Task { @MainActor in
            dismissMenu()
            await Task.yield()
            openEditorWindow()
            model.configureEditor(editorModel)
            await editorModel.open(
                fileURL: url,
                outputDirectory: model.settings.recordingsDirectory,
                outputDirectoryBookmark: model.settings.recordingsDirectoryBookmark,
                transcriptSourceContext: model.transcriptSourceContext(for: url)
            )
        }
    }

    private func openLuxelSettings() {
        Task { @MainActor in
            dismissMenu()
            await Task.yield()
            openSettingsWindow()
        }
    }

    private func openRecentRecording(_ recording: PastRecording) {
        openRecording(recording.primaryMediaURL)
    }

    private func revealRecentRecording(_ recording: PastRecording) {
        dismissMenu()
        model.revealRecording(recording)
    }

    private func recentRecordingOpenTitle(for recording: PastRecording) -> String {
        "Open in editor"
    }

    private func recentRecordingTitle(for recording: PastRecording) -> String {
        recording.name.components(separatedBy: " at ").first ?? recording.name
    }

    private func refreshMenuState() async {
        model.refreshRecentRecordings()
        model.refreshAudioInputDevices()
        model.refreshCameraDevices()
        await model.refreshPermissions()
        await model.refreshCaptureTargets()
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

    private func handleSystemAudioFooterAction(_ presentation: CaptureSourcePermissionPresentation) {
        switch presentation.phase {
        case .ready:
            model.settings.recordSystemAudio = false
            model.saveSettings()
        case .offByUser:
            model.settings.recordSystemAudio = true
            model.saveSettings()
        case .checking, .needsGrant, .requestInProgress, .openSettings, .grantedNeedsRelaunch,
             .pausedByMacOS, .blocked:
            presentPermissionPrompt(.systemAudio)
        }
    }

    private func handleMicrophoneFooterAction(_ presentation: CaptureSourcePermissionPresentation) {
        switch presentation.phase {
        case .ready:
            model.settings.recordAudio = false
            model.saveSettings()
        case .offByUser:
            model.settings.recordAudio = true
            model.saveSettings()
        case .checking, .needsGrant, .requestInProgress, .openSettings, .grantedNeedsRelaunch,
             .pausedByMacOS, .blocked:
            presentPermissionPrompt(.microphone)
        }
    }

    private func handleCameraFooterAction(_ presentation: CaptureSourcePermissionPresentation) {
        switch presentation.phase {
        case .ready:
            model.disableCameraSource()
        case .offByUser:
            Task {
                await model.enableDefaultCameraSource()
            }
        case .checking, .needsGrant, .requestInProgress, .openSettings, .grantedNeedsRelaunch,
             .pausedByMacOS, .blocked:
            presentPermissionPrompt(.camera)
        }
    }
}

private struct RecentRecordingThumbnail: View {
    private static let size = CGSize(width: 60, height: 38)

    @State private var thumbnail: NSImage?

    let recording: PastRecording

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            thumbnailContent

            Image(systemName: badgeSystemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(.black.opacity(0.56), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(.white.opacity(0.14), lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .padding(4)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .task(id: thumbnailRequest) {
            await loadThumbnail()
        }
        .accessibilityLabel("Recent recording preview")
    }

    @ViewBuilder
    private var thumbnailContent: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .scaledToFill()
                .frame(width: Self.size.width, height: Self.size.height)
                .clipped()
        } else {
            ZStack {
                Rectangle()
                    .fill(.white.opacity(0.08))

                Image(systemName: placeholderSystemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var thumbnailRequest: RecentRecordingThumbnailRequest {
        RecentRecordingThumbnailRequest(
            fileURL: thumbnailURL,
            isAudioOnly: recording.options.isAudioOnly
        )
    }

    private var thumbnailURL: URL {
        recording.latestExport?.fileURL ?? recording.primaryMediaURL
    }

    private var placeholderSystemImage: String {
        recording.options.isAudioOnly ? "waveform" : "film"
    }

    private var badgeSystemImage: String {
        recording.options.isAudioOnly ? "waveform" : "film"
    }

    @MainActor
    private func loadThumbnail() async {
        thumbnail = await Self.thumbnail(for: thumbnailRequest)
    }

    @MainActor
    private static func thumbnail(for request: RecentRecordingThumbnailRequest) async -> NSImage? {
        guard !request.isAudioOnly else {
            return nil
        }

        if request.fileURL.isImageLikeMedia {
            return NSImage(contentsOf: request.fileURL)
        }

        return await videoThumbnail(for: request.fileURL)
    }

    @MainActor
    private static func videoThumbnail(for fileURL: URL) async -> NSImage? {
        let asset = AVURLAsset(url: fileURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: size.width * 2, height: size.height * 2)

        for time in [
            CMTime(seconds: 0.2, preferredTimescale: 600),
            .zero
        ] {
            if let image = try? await generator.image(at: time).image {
                return NSImage(cgImage: image, size: .zero)
            }
        }

        return nil
    }
}

private struct RecentRecordingThumbnailRequest: Equatable {
    let fileURL: URL
    let isAudioOnly: Bool
}

private struct RecentRecordingMetadataLabel: View {
    @State private var durationText: String?

    let recording: PastRecording

    var body: some View {
        Text(metadataText)
            .task(id: mediaURL) {
                durationText = nil
                durationText = await Self.durationText(for: mediaURL)
            }
    }

    private var metadataText: String {
        let components = [
            durationText,
            fileSizeText,
            formatText
        ].compactMap { text -> String? in
            guard let text, !text.isEmpty else {
                return nil
            }

            return text
        }

        if !components.isEmpty {
            return components.joined(separator: " · ")
        }

        return recording.date.formatted(date: .abbreviated, time: .shortened)
    }

    private var mediaURL: URL {
        recording.latestExport?.fileURL ?? recording.primaryMediaURL
    }

    private var fileSizeText: String? {
        if let fileSizeBytes = recording.latestExport?.fileSizeBytes {
            return ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
        }

        guard let fileSizeBytes = try? mediaURL.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return nil
        }

        return ByteCountFormatter.string(fromByteCount: Int64(fileSizeBytes), countStyle: .file)
    }

    private var formatText: String? {
        if let exportFormat = recording.latestExport?.format.prettyName {
            return exportFormat
        }

        let fileExtension = mediaURL.pathExtension
        guard !fileExtension.isEmpty else {
            return nil
        }

        return fileExtension.uppercased()
    }

    private static func durationText(for fileURL: URL) async -> String? {
        let asset = AVURLAsset(url: fileURL)

        do {
            let duration = try await asset.load(.duration)
            let seconds = duration.seconds
            guard seconds.isFinite, seconds > 0 else {
                return nil
            }

            return formatDuration(seconds)
        } catch {
            return nil
        }
    }

    private static func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours):\(twoDigits(minutes)):\(twoDigits(seconds))"
        }

        return "\(twoDigits(minutes)):\(twoDigits(seconds))"
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
