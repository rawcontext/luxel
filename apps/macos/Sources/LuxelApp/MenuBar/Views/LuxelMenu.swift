import AppKit
import AVFoundation
import LuxelCore
import LuxelPresentation
import SwiftUI
import UniformTypeIdentifiers

struct LuxelMenu: View {
    private static let contentWidth: CGFloat = 300
    private static let contentPadding: CGFloat = 6
    private static let outerPadding: CGFloat = 2
    private static let captureActionButtonHeight: CGFloat = 46
    private static let captureActionButtonCornerRadius: CGFloat = 12
    private static let footerButtonHeight: CGFloat = 32
    private static let footerButtonCornerRadius: CGFloat = 11
    private static let footerMicButtonWidth: CGFloat = 38
    private static let footerRecentFolderButtonWidth: CGFloat = 34
    private static let footerMoreButtonWidth: CGFloat = 42

    @State private var isImportingRecording = false

    @Bindable var model: LuxelMenuModel
    let editorModel: LuxelEditorModel
    let cropperPanelController: LuxelCropperPanelController
    let shortcutController: LuxelShortcutController
    let dismissMenu: @MainActor () -> Void
    let openEditorWindow: @MainActor () -> Void
    let openSettingsWindow: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LuxelCaptureTargetPicker(model: model)
            captureActionSelector
            permissionButtons
            LuxelRecordingStatusMessages(model: model)
            LuxelReplayBufferControls(model: model)
            latestRecordingCard
            footerControls
        }
        .frame(width: Self.contentWidth, alignment: .leading)
        .padding(Self.contentPadding)
        .padding(Self.outerPadding)
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
        .fileImporter(
            isPresented: $isImportingRecording,
            allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: false
        ) { result in
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
}

private extension LuxelMenu {
    private var captureActionSelector: some View {
        HStack(spacing: 6) {
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
        .buttonStyle(.plain)
        .disabled(!canPerformCaptureAction(action))
    }

    @ViewBuilder
    private func captureActionButtonLabel(_ action: LuxelCaptureAction) -> some View {
        if canPerformCaptureAction(action) {
            captureActionButtonContent(action)
                .foregroundStyle(.white)
                .luxelMenuControlBackground(cornerRadius: Self.captureActionButtonCornerRadius, isActive: true)
        } else {
            captureActionButtonContent(action)
                .foregroundStyle(.secondary)
                .luxelMenuControlBackground(cornerRadius: Self.captureActionButtonCornerRadius)
                .opacity(0.55)
        }
    }

    private func captureActionButtonContent(_ action: LuxelCaptureAction) -> some View {
        VStack(spacing: 4) {
            Image(systemName: action.systemImage)
                .font(.system(size: 17, weight: .medium))
                .symbolRenderingMode(.hierarchical)
            Text(action.title)
                .font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity, minHeight: Self.captureActionButtonHeight)
        .contentShape(RoundedRectangle(cornerRadius: Self.captureActionButtonCornerRadius, style: .continuous))
    }

    @ViewBuilder
    private var permissionButtons: some View {
        let needsScreenRecording = model.screenRecordingStatus != .authorized
        let needsMicrophone = model.microphoneStatus != .authorized
        let needsCamera = model.settings.cameraDeviceID != nil && model.cameraStatus != .authorized

        if needsScreenRecording || needsMicrophone || needsCamera {
            HStack(spacing: 6) {
                if needsScreenRecording {
                    permissionButton(
                        title: "Screen",
                        systemImage: "display",
                        status: model.screenRecordingStatus,
                        permission: .screenRecording
                    )
                }

                if needsMicrophone {
                    permissionButton(
                        title: "Mic",
                        systemImage: "mic",
                        status: model.microphoneStatus,
                        permission: .microphone
                    )
                }

                if needsCamera {
                    permissionButton(
                        title: "Camera",
                        systemImage: "video",
                        status: model.cameraStatus,
                        permission: .camera
                    )
                }
            }
        }
    }

    private func permissionButton(
        title: String,
        systemImage: String,
        status: PermissionStatus,
        permission: SystemPermission
    ) -> some View {
        Button {
            model.presentPermissionPrompt(for: permission)
        } label: {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(status.tint)
            }
            .font(.callout.weight(.medium))
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 28)
            .luxelMenuControlBackground(cornerRadius: 10)
        }
        .buttonStyle(.plain)
        .help(model.permissionActionTitle(for: permission))
    }

    @ViewBuilder
    private var latestRecordingCard: some View {
        if let recording = model.recentRecordings.first {
            HStack(spacing: 8) {
                Button {
                    openRecentRecording(recording)
                } label: {
                    HStack(spacing: 8) {
                        RecentRecordingThumbnail(recording: recording)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(recentRecordingTitle(for: recording))
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .lineLimit(2)
                                .minimumScaleFactor(0.86)

                            RecentRecordingMetadataLabel(recording: recording)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
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
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(.white.opacity(0.16), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Show in Finder")
            }
            .padding(8)
            .luxelMenuSectionBackground(cornerRadius: 15)
        }
    }

    private var footerControls: some View {
        HStack(spacing: 8) {
            recordAudioFooterToggle

            recentFooterControl
                .layoutPriority(1)

            Menu {
                overflowMenuItems
            } label: {
                Label("More", systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
                    .font(.callout.weight(.semibold))
                    .frame(width: Self.footerMoreButtonWidth, height: Self.footerButtonHeight)
                    .luxelMenuControlBackground(cornerRadius: Self.footerButtonCornerRadius)
            }
            .buttonStyle(.plain)
            .frame(height: Self.footerButtonHeight)
        }
        .frame(maxWidth: .infinity)
    }

    private var recentFooterControl: some View {
        HStack(spacing: 0) {
            Menu {
                recentRecordingsMenuItems
            } label: {
                Label("Recent", systemImage: "clock")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: Self.footerButtonHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.recentRecordings.isEmpty)
            .help("Show recent recordings and screenshots")

            Rectangle()
                .fill(.white.opacity(0.16))
                .frame(width: 1, height: 18)

            Button {
                dismissMenu()
                model.openRecordingsFolder()
            } label: {
                Image(systemName: "folder")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: Self.footerRecentFolderButtonWidth, height: Self.footerButtonHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open \(model.recordingsDirectorySummary)")
            .accessibilityLabel("Open Luxel folder")
        }
        .frame(maxWidth: .infinity, minHeight: Self.footerButtonHeight, maxHeight: Self.footerButtonHeight)
        .luxelMenuControlBackground(cornerRadius: Self.footerButtonCornerRadius)
        .clipShape(RoundedRectangle(cornerRadius: Self.footerButtonCornerRadius, style: .continuous))
    }

    private var recordAudioFooterToggle: some View {
        Button {
            recordAudio.wrappedValue.toggle()
        } label: {
            Image(systemName: model.settings.recordAudio ? "mic.fill" : "mic.slash")
                .labelStyle(.iconOnly)
                .font(.callout.weight(.semibold))
                .foregroundStyle(model.settings.recordAudio ? .black : .white)
                .frame(width: Self.footerMicButtonWidth, height: Self.footerButtonHeight)
                .background(
                    model.settings.recordAudio ? .white.opacity(0.92) : .white.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: Self.footerButtonCornerRadius, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .frame(height: Self.footerButtonHeight)
        .help(recordAudioHelp)
        .accessibilityLabel("Microphone")
        .accessibilityValue(model.settings.recordAudio ? "On" : "Off")
    }

    @ViewBuilder
    private var recentRecordingsMenuItems: some View {
        if model.recentRecordings.isEmpty {
            Text("No recent items")
        } else {
            ForEach(Array(model.recentRecordings.prefix(8)), id: \.fileURL) { recording in
                Button {
                    openRecentRecording(recording)
                } label: {
                    Label(recording.name, systemImage: recentRecordingBadgeSystemImage(for: recording))
                }
                .help(recording.fileURL.path)
            }
        }
    }

    @ViewBuilder
    private var overflowMenuItems: some View {
        Button {
            startAfterDismissingMenu {
                await model.startQuickRecordingFromSelectedTarget()
            }
        } label: {
            Label("Quick Record", systemImage: "bolt.circle")
        }
        .disabled(!model.canUseQuickRecordButton)

        Button {
            startAfterDismissingMenu {
                await model.captureScreenshotFromSelectedTarget()
            }
        } label: {
            Label("Screenshot", systemImage: "camera")
        }
        .disabled(!model.canCaptureScreenshot)

        Menu {
            Button {
                startAfterDismissingMenu {
                    showAreaCapturePicker()
                }
            } label: {
                Label("Select Area", systemImage: "crop")
            }
            .disabled(!model.canSelectArea)

            Button {
                startAfterDismissingMenu {
                    await model.startAudioOnlyRecording()
                }
            } label: {
                Label("Record Audio Only", systemImage: "waveform")
            }
            .disabled(!model.canUseAudioOnlyButton)

            Button {
                startAfterDismissingMenu {
                    await model.startQuickRecordingFromLastCapture()
                }
            } label: {
                Label("Quick Record Last", systemImage: "bolt.circle")
            }
            .disabled(!model.canUseQuickRecordLastButton)
        } label: {
            Label("Advanced Capture", systemImage: "viewfinder")
        }

        Divider()

        Button {
            startAfterDismissingMenu {
                await model.startRecordingFromLastCapture()
            }
        } label: {
            Label("Record Again", systemImage: "arrow.clockwise")
        }
        .disabled(!model.canUseRecordAgainButton)

        Button {
            isImportingRecording = true
        } label: {
            Label("Open Recording", systemImage: "folder")
        }

        Divider()

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

    private func showAreaCapturePicker() {
        model.refreshCameraDevices()
        cropperPanelController.show(
            countdownDuration: model.settings.defaultCountdown,
            stopAfterDuration: model.settings.lastStopAfter,
            audioLevelConfiguration: model.cropperAudioLevelConfiguration(),
            cameraConfiguration: model.cropperCameraConfiguration(),
            quickRecordingConfiguration: model.cropperQuickRecordingConfiguration(),
            selectionPresetConfiguration: model.cropperSelectionPresetConfiguration(),
            restoreSelectionConfiguration: model.cropperRestoreSelectionConfiguration(),
            recordAudio: model.settings.recordAudio,
            loupeAlwaysOn: model.settings.loupeAlwaysOn,
            dimOtherDisplays: model.settings.dimOtherDisplays,
            showsNotificationReminder: model.settings.notificationReminder,
            onCountdownDurationChange: { duration in
                model.settings.defaultCountdown = duration
                model.saveSettings()
            },
            onStopAfterDurationChange: { duration in
                model.settings.lastStopAfter = duration
                model.saveSettings()
            },
            onRecordAudioChange: { isEnabled in
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
            onCaptureScreenshot: { draft in
                Task {
                    await model.captureScreenshot(from: draft)
                }
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
            await editorModel.open(fileURL: url, outputDirectory: model.settings.recordingsDirectory)
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
        if recording.kind == .recording {
            openRecording(recording.primaryMediaURL)
        } else {
            revealRecentRecording(recording)
        }
    }

    private func revealRecentRecording(_ recording: PastRecording) {
        dismissMenu()
        model.revealRecording(recording)
    }

    private func recentRecordingSystemImage(for recording: PastRecording) -> String {
        switch recording.kind {
        case .recording:
            recording.options.isAudioOnly ? "waveform" : "film"
        case .screenshot:
            "photo"
        }
    }

    private func recentRecordingBadgeSystemImage(for recording: PastRecording) -> String {
        switch recording.kind {
        case .recording:
            recording.options.isAudioOnly ? "waveform" : "film"
        case .screenshot:
            "camera"
        }
    }

    private func recentRecordingOpenTitle(for recording: PastRecording) -> String {
        recording.kind == .recording ? "Open in editor" : "Show in Finder"
    }

    private func recentRecordingTitle(for recording: PastRecording) -> String {
        recording.name.replacingOccurrences(of: " at ", with: "\nat ")
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

    private var recordAudio: Binding<Bool> {
        Binding {
            model.settings.recordAudio
        } set: { isEnabled in
            if isEnabled, model.microphoneStatus != .authorized {
                model.presentPermissionPrompt(for: .microphone)
                return
            }

            model.settings.recordAudio = isEnabled
            model.saveSettings()
        }
    }

    private var recordAudioHelp: String {
        if model.settings.recordAudio {
            return "Record microphone audio with screen and area recordings."
        }

        if model.microphoneStatus == .authorized {
            return "Do not record microphone audio with screen and area recordings."
        }

        return "Grant microphone permission to enable mic recording."
    }
}

private struct RecentRecordingThumbnail: View {
    private static let size = CGSize(width: 58, height: 42)

    @State private var thumbnail: NSImage?

    let recording: PastRecording

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            thumbnailContent

            Image(systemName: badgeSystemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .padding(4)
                .background(.black.opacity(0.56), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .padding(5)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
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
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var thumbnailRequest: RecentRecordingThumbnailRequest {
        RecentRecordingThumbnailRequest(
            fileURL: thumbnailURL,
            isAudioOnly: recording.kind == .recording && recording.options.isAudioOnly
        )
    }

    private var thumbnailURL: URL {
        if recording.kind == .recording {
            return recording.latestExport?.fileURL ?? recording.primaryMediaURL
        }

        return recording.fileURL
    }

    private var placeholderSystemImage: String {
        switch recording.kind {
        case .recording:
            recording.options.isAudioOnly ? "waveform" : "film"
        case .screenshot:
            "photo"
        }
    }

    private var badgeSystemImage: String {
        switch recording.kind {
        case .recording:
            recording.options.isAudioOnly ? "waveform" : "film"
        case .screenshot:
            "camera"
        }
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

                guard recording.kind == .recording else {
                    return
                }

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
        if recording.kind == .recording {
            return recording.latestExport?.fileURL ?? recording.primaryMediaURL
        }

        return recording.fileURL
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
            return recording.kind == .screenshot ? "Screenshot" : nil
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

private extension URL {
    var isImageLikeMedia: Bool {
        switch pathExtension.lowercased() {
        case "gif", "heic", "jpeg", "jpg", "png", "tif", "tiff", "webp":
            true
        default:
            false
        }
    }
}

extension View {
    func luxelMenuSectionBackground(cornerRadius: CGFloat) -> some View {
        background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    func luxelMenuControlBackground(cornerRadius: CGFloat, isActive: Bool = false) -> some View {
        background(
            .white.opacity(isActive ? 0.14 : 0.09),
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
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
