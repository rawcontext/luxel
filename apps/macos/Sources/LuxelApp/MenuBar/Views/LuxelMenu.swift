import AVFoundation
import AppKit
import LuxelCore
import LuxelPresentation
import SwiftUI

struct LuxelMenu: View {
    private static let contentWidth: CGFloat = 300
    private static let contentPadding: CGFloat = 6
    private static let moduleSpacing: CGFloat = 8
    private static let captureActionButtonHeight: CGFloat = 56
    private static let captureActionButtonCornerRadius: CGFloat = 17
    private static let footerButtonHeight: CGFloat = 34
    private static let footerButtonCornerRadius: CGFloat = 17
    private static let footerButtonWidth: CGFloat = 34
    private static let footerMicrophoneControlWidth: CGFloat = 82
    private static let footerCameraControlWidth: CGFloat = 82

    @Bindable var model: LuxelMenuModel
    let editorModel: LuxelEditorModel
    let cropperPanelController: LuxelCropperPanelController
    let shortcutController: LuxelShortcutController
    let dismissMenu: @MainActor () -> Void
    let openEditorWindow: @MainActor () -> Void
    let openSettingsWindow: @MainActor () -> Void
    let presentPermissionPrompt: @MainActor (CapturePermissionSource) -> Void

    var body: some View {
        GlassEffectContainer(spacing: Self.moduleSpacing) {
            VStack(alignment: .leading, spacing: Self.moduleSpacing) {
                LuxelCaptureTargetPicker(model: model)
                captureActionSelector
                LuxelRecordingStatusMessages(model: model)
                LuxelReplayBufferControls(model: model)
                latestRecordingCard
                footerControls
            }
            .frame(width: Self.contentWidth, alignment: .leading)
            .padding(Self.contentPadding)
        }
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
    private var captureActionSelector: some View {
        HStack(spacing: 7) {
            captureActionButton(.screen)
            captureActionButton(.area)
            captureActionButton(.audio)
        }
        .frame(maxWidth: .infinity, minHeight: Self.captureActionButtonHeight)
    }

    private func captureActionButton(_ action: LuxelCaptureAction) -> some View {
        Button {
            performCaptureAction(action)
        } label: {
            captureActionButtonLabel(action)
        }
        .buttonStyle(LuxelMenuControlButtonStyle(cornerRadius: Self.captureActionButtonCornerRadius))
        .frame(maxWidth: .infinity)
        .disabled(!canPerformCaptureAction(action) && !canRecoverCaptureAction(action))
    }

    @ViewBuilder
    private func captureActionButtonLabel(_ action: LuxelCaptureAction) -> some View {
        if canPerformCaptureAction(action) {
            captureActionButtonContent(action)
                .foregroundStyle(.white)
        } else {
            captureActionButtonContent(action)
                .foregroundStyle(.secondary)
                .opacity(0.55)
        }
    }

    private func captureActionButtonContent(_ action: LuxelCaptureAction) -> some View {
        VStack(spacing: 6) {
            Image(systemName: action.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
            Text(action.title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .frame(maxWidth: .infinity, minHeight: Self.captureActionButtonHeight)
        .contentShape(
            RoundedRectangle(cornerRadius: Self.captureActionButtonCornerRadius, style: .continuous))
    }

    @ViewBuilder
    private var latestRecordingCard: some View {
        if let recording = model.recentRecordings.first {
            HStack(spacing: 12) {
                Button {
                    openRecentRecording(recording)
                } label: {
                    HStack(spacing: 12) {
                        RecentRecordingThumbnail(recording: recording)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(recentRecordingTitle(for: recording))
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)

                            RecentRecordingMetadataLabel(recording: recording)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
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
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(LuxelMenuControlButtonStyle(cornerRadius: 17))
                .help("Show in Finder")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(minHeight: 68)
            .luxelMenuSectionBackground(cornerRadius: 18)
        }
    }

    private var footerControls: some View {
        HStack(spacing: 7) {
            recordSystemAudioFooterToggle
            microphoneFooterControl
            cameraFooterControl

            Spacer(minLength: 0)

            Menu {
                overflowMenuItems
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: Self.footerButtonWidth, height: Self.footerButtonHeight)
                    .luxelMenuControlBackground(cornerRadius: Self.footerButtonCornerRadius)
            }
            .buttonStyle(.plain)
            .frame(height: Self.footerButtonHeight)
        }
        .frame(maxWidth: .infinity)
    }

    private var microphoneFooterControl: some View {
        HStack(spacing: 0) {
            recordMicrophoneFooterToggle(backgrounded: false)
                .frame(width: 50, height: Self.footerButtonHeight)

            Rectangle()
                .fill(.white.opacity(0.18))
                .frame(width: 1, height: 18)

            microphoneFooterPicker
                .frame(width: 31, height: Self.footerButtonHeight)
        }
        .frame(width: Self.footerMicrophoneControlWidth, height: Self.footerButtonHeight)
        .luxelMenuControlBackground(cornerRadius: Self.footerButtonCornerRadius)
        .clipShape(RoundedRectangle(cornerRadius: Self.footerButtonCornerRadius, style: .continuous))
    }

    private var cameraFooterControl: some View {
        HStack(spacing: 0) {
            cameraFooterToggle(backgrounded: false)
                .frame(width: 50, height: Self.footerButtonHeight)

            Rectangle()
                .fill(.white.opacity(0.18))
                .frame(width: 1, height: 18)

            cameraFooterPicker
                .frame(width: 31, height: Self.footerButtonHeight)
        }
        .frame(width: Self.footerCameraControlWidth, height: Self.footerButtonHeight)
        .luxelMenuControlBackground(cornerRadius: Self.footerButtonCornerRadius)
        .clipShape(RoundedRectangle(cornerRadius: Self.footerButtonCornerRadius, style: .continuous))
    }

    private var recordSystemAudioFooterToggle: some View {
        let presentation = model.sourcePermissionPresentation(for: .systemAudio)

        return Button {
            handleSystemAudioFooterAction(presentation)
        } label: {
            footerSourceIcon(presentation)
        }
        .buttonStyle(
            LuxelMenuControlButtonStyle(
                cornerRadius: Self.footerButtonCornerRadius,
                addsContrastBackground: true
            )
        )
        .frame(height: Self.footerButtonHeight)
        .help(presentation.message)
        .accessibilityLabel("System Audio")
        .accessibilityValue(presentation.statusTitle)
    }

    private func recordMicrophoneFooterToggle(backgrounded: Bool = true) -> some View {
        let presentation = model.sourcePermissionPresentation(for: .microphone)

        return Button {
            handleMicrophoneFooterAction(presentation)
        } label: {
            footerSourceIcon(presentation, backgrounded: backgrounded)
        }
        .buttonStyle(
            LuxelMenuControlButtonStyle(
                cornerRadius: Self.footerButtonCornerRadius,
                addsContrastBackground: backgrounded
            )
        )
        .frame(height: Self.footerButtonHeight)
        .help(presentation.message)
        .accessibilityLabel("Microphone")
        .accessibilityValue(presentation.statusTitle)
    }

    private func cameraFooterToggle(backgrounded: Bool) -> some View {
        let presentation = model.sourcePermissionPresentation(for: .camera)

        return Button {
            handleCameraFooterAction(presentation)
        } label: {
            footerSourceIcon(presentation, backgrounded: backgrounded)
        }
        .buttonStyle(
            LuxelMenuControlButtonStyle(
                cornerRadius: Self.footerButtonCornerRadius,
                addsContrastBackground: backgrounded
            )
        )
        .frame(height: Self.footerButtonHeight)
        .help(presentation.message)
        .accessibilityLabel("Camera")
        .accessibilityValue(presentation.statusTitle)
    }

    @ViewBuilder
    private func footerSourceIcon(
        _ presentation: CaptureSourcePermissionPresentation,
        backgrounded: Bool = true
    ) -> some View {
        let icon = Image(systemName: presentation.systemImage)
            .labelStyle(.iconOnly)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: backgrounded ? Self.footerButtonWidth : 50, height: Self.footerButtonHeight)
            .contentShape(Rectangle())

        icon
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

    private func canPerformCaptureAction(_ action: LuxelCaptureAction) -> Bool {
        guard !model.hasActiveRecording else {
            return false
        }

        switch action {
        case .screen:
            return model.canUseRecordButton
        case .area:
            return model.canSelectArea
        case .audio:
            return model.canUseAudioOnlyButton
        }
    }

    private func performCaptureAction(_ action: LuxelCaptureAction) {
        guard canPerformCaptureAction(action) else {
            recoverCaptureAction(action)
            return
        }

        switch action {
        case .screen:
            startAfterDismissingMenu {
                await model.startRecordingFromSelectedTarget()
            }
        case .area:
            startAfterDismissingMenu {
                showAreaCapturePicker()
            }
        case .audio:
            startAfterDismissingMenu {
                await model.startAudioOnlyRecording()
            }
        }
    }

    private func canRecoverCaptureAction(_ action: LuxelCaptureAction) -> Bool {
        switch action {
        case .screen, .area:
            model.sourcePermissionPresentation(for: .screenPixels).needsSetup
        case .audio:
            audioCaptureRecoverySource() != nil
        }
    }

    private func recoverCaptureAction(_ action: LuxelCaptureAction) {
        switch action {
        case .screen, .area:
            presentPermissionPrompt(.screenPixels)
        case .audio:
            if let source = audioCaptureRecoverySource() {
                presentPermissionPrompt(source)
            }
        }
    }

    private func audioCaptureRecoverySource() -> CapturePermissionSource? {
        let microphone = model.sourcePermissionPresentation(for: .microphone)
        let systemAudio = model.sourcePermissionPresentation(for: .systemAudio)

        if microphone.needsSetup {
            return .microphone
        }

        if systemAudio.needsSetup {
            return .systemAudio
        }

        if microphone.phase == .offByUser {
            return .microphone
        }

        if systemAudio.phase == .offByUser {
            return .systemAudio
        }

        return nil
    }

    private func showAreaCapturePicker() {
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

    private func startAfterDismissingMenu(_ action: @escaping @MainActor () async -> Void) {
        Task { @MainActor in
            dismissMenu()
            await Task.yield()
            await action()
        }
    }

    private func openRecording(_ url: URL) {
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
    private static let size = CGSize(width: 78, height: 49)

    @State private var thumbnail: NSImage?

    let recording: PastRecording

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            thumbnailContent

            Image(systemName: badgeSystemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(.black.opacity(0.56), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(.white.opacity(0.14), lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .padding(5)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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
                    .font(.system(size: 17, weight: .medium))
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

private enum LuxelCaptureAction {
    case screen
    case area
    case audio

    var title: String {
        switch self {
        case .screen:
            "Screen"
        case .area:
            "Area"
        case .audio:
            "Audio"
        }
    }

    var systemImage: String {
        switch self {
        case .screen:
            "rectangle.dashed"
        case .area:
            "viewfinder"
        case .audio:
            "waveform"
        }
    }
}
