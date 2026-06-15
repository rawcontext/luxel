import AppKit
import LuxelCore
import LuxelPresentation
import SwiftUI

struct LuxelCropperView: View {
    private static let loupeSize = CGSize(width: 164, height: 122)

    @Environment(\.openURL) private var openURL
    @State private var currentCameraConfiguration: CropperCameraConfiguration?

    @Bindable var model: LuxelCropperModel
    let audioLevelModel: LuxelAudioLevelModel?
    let cameraConfiguration: CropperCameraConfiguration
    let quickRecordingConfiguration: CropperQuickRecordingConfiguration
    let showsNotificationReminder: Bool
    let onCameraSelectionChange: (String?) -> Void
    let onCameraPreviewStyleChange: (CameraPreviewStyle) -> Void
    let onNotificationReminderDismiss: () -> Void
    let onCancel: () -> Void
    let onSelect: (CaptureSelectionDraft) -> Void
    let onQuickSelect: (CaptureSelectionDraft, UUID) -> Void
    let onCaptureScreenshot: (CaptureSelectionDraft) -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(model.isDimmedByOtherDisplay ? 0.20 : 0.38)
                    .ignoresSafeArea()

                if let selection = model.selection, !model.isDimmedByOtherDisplay {
                    let rect = model.viewRect(for: selection, in: geometry.size)

                    selectionOverlay(rect: rect, viewSize: geometry.size)
                }

                if !model.isDimmedByOtherDisplay {
                    snapGuidesOverlay(viewSize: geometry.size)
                }

                if let loupeSample = model.loupeSample, !model.isDimmedByOtherDisplay {
                    CropperLoupeView(sample: loupeSample)
                        .frame(width: Self.loupeSize.width, height: Self.loupeSize.height)
                        .position(loupePosition(for: loupeSample, viewSize: geometry.size))
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                if !model.isDimmedByOtherDisplay {
                    VStack {
                        if showsNotificationReminder, model.mode == .video {
                            notificationReminderPanel
                                .padding(.top, 28)
                        }

                        Spacer()
                        cropperControls
                            .padding(.bottom, 28)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let flags = NSEvent.modifierFlags
                        let isLoupeRequested = flags.contains(.option)
                        let isLoupeActive = model.loupeAlwaysOn || isLoupeRequested
                        model.updateSelection(
                            start: value.startLocation,
                            current: value.location,
                            viewSize: geometry.size,
                            isSnappingDisabled: flags.contains(.command) || isLoupeActive,
                            isLoupeRequested: isLoupeRequested,
                            loupeOverlaySize: Self.loupeSize
                        )
                    }
                    .onEnded { _ in
                        model.finishUpdateSelection()
                    }
            )
            .background(cropperKeyboardShortcuts)
            .focusable()
            .onMoveCommand { direction in
                handleMoveCommand(direction)
            }
        }
    }

    private var cropperKeyboardShortcuts: some View {
        VStack {
            Button("Undo Cropper Selection") {
                model.undoSelectionChange()
            }
            .disabled(!model.canUndoSelectionChange)
            .keyboardShortcut("z", modifiers: .command)

            Button("Redo Cropper Selection") {
                model.redoSelectionChange()
            }
            .disabled(!model.canRedoSelectionChange)
            .keyboardShortcut("z", modifiers: [.command, .shift])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private var cropperControls: some View {
        GlassPanel {
            HStack(spacing: 12) {
                selectionGeometryControls

                Picker("Mode", selection: cropperMode) {
                    ForEach(LuxelCropperMode.allCases) { mode in
                        Text(mode.toolbarLabel).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(width: 126)
                .help("Capture Mode")

                Button {
                    model.selectFullDisplay()
                } label: {
                    Label("Full Display", systemImage: "rectangle.inset.filled")
                }
                .labelStyle(.iconOnly)
                .help("Select Full Display")

                aspectRatioMenu

                sizePresetMenu

                if model.mode == .video {
                    cameraMenu

                    Menu {
                        countdownButton(title: "Off", duration: nil)

                        Divider()

                        ForEach(CountdownPreset.all) { preset in
                            countdownButton(title: preset.title, duration: preset.duration)
                        }
                    } label: {
                        Label(model.countdownSummary, systemImage: "hourglass")
                    }
                    .frame(width: 82)
                    .help("Countdown")

                    Menu {
                        stopAfterButton(title: "Off", duration: nil)

                        Divider()

                        ForEach(StopAfterPreset.all) { preset in
                            stopAfterButton(title: preset.title, duration: preset.duration)
                        }

                        Divider()

                        TextField("h:mm:ss", text: customStopAfterText)
                            .frame(width: 84)

                        Button {
                            applyCustomStopAfterDuration()
                        } label: {
                            Label("Set Custom", systemImage: "timer")
                        }
                    } label: {
                        Label(model.stopAfterSummary, systemImage: "timer")
                    }
                    .frame(width: 82)
                    .help("Stop After")

                    if let audioLevelModel {
                        CropperAudioLevelMeter(model: audioLevelModel)
                    }
                }

                Button {
                    onCancel()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                }
                .labelStyle(.iconOnly)
                .help("Cancel")

                primaryActionButton
            }
        }
        .fixedSize()
    }

    private var aspectRatioMenu: some View {
        Menu {
            ForEach(CaptureAspectRatioPreset.allCases, id: \.self) { preset in
                Button {
                    model.setAspectRatioPreset(preset)
                } label: {
                    if model.customAspectRatio == nil, model.aspectRatioPreset == preset {
                        Label(preset.title, systemImage: "checkmark")
                    } else {
                        Text(preset.title)
                    }
                }
            }

            Divider()

            TextField("Custom W", text: customAspectRatioWidthText)
                .frame(width: 76)
            TextField("Custom H", text: customAspectRatioHeightText)
                .frame(width: 76)

            Button {
                applyCustomAspectRatio()
            } label: {
                if let customAspectRatio = model.customAspectRatio {
                    Label("\(customAspectRatio.width):\(customAspectRatio.height)", systemImage: "checkmark")
                } else {
                    Label("Apply Custom", systemImage: "aspectratio")
                }
            }
        } label: {
            Label(model.aspectRatioSummary, systemImage: "aspectratio")
        }
        .frame(width: 76)
        .help("Aspect Ratio")
    }

    private var sizePresetMenu: some View {
        Menu {
            ForEach(model.sizePresets) { preset in
                Button {
                    model.applySizePreset(preset)
                } label: {
                    Text(preset.name)
                }
            }
        } label: {
            Label("Size", systemImage: "arrow.up.left.and.arrow.down.right")
        }
        .labelStyle(.iconOnly)
        .help("Size Presets")
    }

    @ViewBuilder
    private var selectionGeometryControls: some View {
        if model.selection == nil {
            Text(model.selectionSummary)
                .font(.callout)
                .monospacedDigit()
                .frame(minWidth: 96, alignment: .leading)
        } else {
            HStack(spacing: 6) {
                SelectionNumberField(title: "X", value: selectionX)
                SelectionNumberField(title: "Y", value: selectionY)
                SelectionNumberField(title: "W", value: selectionWidth)
                SelectionNumberField(title: "H", value: selectionHeight)
            }
            .help("Selection Geometry")
        }
    }

    @ViewBuilder
    private var cameraMenu: some View {
        let cameraConfiguration = effectiveCameraConfiguration

        Menu {
            cameraDeviceButton(title: "Off", deviceID: nil)

            if !cameraConfiguration.devices.isEmpty {
                Divider()

                ForEach(cameraConfiguration.devices) { device in
                    cameraDeviceButton(title: device.settingsLabel, deviceID: device.id)
                }
            }

            if cameraConfiguration.selectedDeviceID != nil {
                Divider()

                Menu {
                    ForEach(CameraOverlayShape.allCases, id: \.self) { shape in
                        Button {
                            updateCameraPreviewShape(shape)
                        } label: {
                            if cameraConfiguration.previewStyle.shape == shape {
                                Label(shape.settingsLabel, systemImage: "checkmark")
                            } else {
                                Text(shape.settingsLabel)
                            }
                        }
                    }
                } label: {
                    Label("Shape", systemImage: "circle")
                }

                Menu {
                    ForEach(CameraPreviewSize.allCases, id: \.self) { size in
                        Button {
                            updateCameraPreviewSize(size)
                        } label: {
                            if cameraConfiguration.previewStyle.size == size {
                                Label(size.settingsLabel, systemImage: "checkmark")
                            } else {
                                Text(size.settingsLabel)
                            }
                        }
                    }
                } label: {
                    Label("Size", systemImage: "arrow.up.left.and.arrow.down.right")
                }

                Button {
                    updateCameraPreviewMirror(!cameraConfiguration.previewStyle.isMirrored)
                } label: {
                    if cameraConfiguration.previewStyle.isMirrored {
                        Label("Mirror", systemImage: "checkmark")
                    } else {
                        Text("Mirror")
                    }
                }
            }
        } label: {
            Label(cameraMenuTitle, systemImage: cameraMenuSystemImage)
        }
        .labelStyle(.iconOnly)
        .help("Camera")
    }

    private var notificationReminderPanel: some View {
        GlassPanel {
            HStack(spacing: 10) {
                Image(systemName: "moon")
                    .foregroundStyle(.secondary)

                Text("Tip: enable a Focus to silence notifications.")
                    .font(.callout)
                    .foregroundStyle(.primary)

                Button {
                    openFocusSettings()
                } label: {
                    Label("Focus Settings", systemImage: "gearshape")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    onNotificationReminderDismiss()
                } label: {
                    Label("Dismiss", systemImage: "xmark")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Dismiss Reminder")
            }
        }
        .fixedSize()
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        Button {
            commitPrimarySelection()
        } label: {
            Label(model.primaryActionTitle, systemImage: model.primaryActionSystemImage)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!model.canRecordSelection)
        .help(model.primaryActionHelp)
        .contextMenu {
            if model.mode == .video {
                Button {
                    commitSelection()
                } label: {
                    Label("Record", systemImage: "record.circle")
                }

                if !quickRecordingConfiguration.presets.isEmpty {
                    Menu {
                        ForEach(quickRecordingConfiguration.presets) { preset in
                            Button {
                                commitSelection(quickPresetID: preset.id)
                            } label: {
                                Label(preset.name, systemImage: quickPresetSystemImage(for: preset))
                            }
                        }
                    } label: {
                        Label("Quick Record", systemImage: "bolt.circle")
                    }
                }
            }
        }
    }

    private func selectionOverlay(rect: CGRect, viewSize: CGSize) -> some View {
        ZStack {
            Rectangle()
                .fill(.clear)
                .overlay {
                    Rectangle()
                        .stroke(.white, lineWidth: 2)
                }
                .background(.white.opacity(0.08))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

            ForEach(CaptureResizeHandle.allCases, id: \.self) { handle in
                resizeHandle(handle, rect: rect, viewSize: viewSize)
            }
        }
    }

    private func snapGuidesOverlay(viewSize: CGSize) -> some View {
        ZStack {
            ForEach(Array(model.snapGuides.enumerated()), id: \.offset) { _, guide in
                snapGuideLine(guide, viewSize: viewSize)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func snapGuideLine(_ guide: CaptureSnapGuide, viewSize: CGSize) -> some View {
        switch guide.axis {
        case .vertical:
            Rectangle()
                .fill(.blue.opacity(0.86))
                .frame(width: 1, height: viewSize.height)
                .position(
                    x: CGFloat(guide.position) / CGFloat(model.display.width) * viewSize.width,
                    y: viewSize.height / 2
                )

        case .horizontal:
            Rectangle()
                .fill(.blue.opacity(0.86))
                .frame(width: viewSize.width, height: 1)
                .position(
                    x: viewSize.width / 2,
                    y: CGFloat(guide.position) / CGFloat(model.display.height) * viewSize.height
                )
        }
    }

    private func loupePosition(for sample: CaptureLoupeSample, viewSize: CGSize) -> CGPoint {
        CGPoint(
            x: CGFloat(sample.overlayOrigin.x) / CGFloat(model.display.width) * viewSize.width
                + Self.loupeSize.width / 2,
            y: CGFloat(sample.overlayOrigin.y) / CGFloat(model.display.height) * viewSize.height
                + Self.loupeSize.height / 2
        )
    }

    private func resizeHandle(
        _ handle: CaptureResizeHandle,
        rect: CGRect,
        viewSize: CGSize
    ) -> some View {
        ZStack {
            Color.clear
                .frame(width: 28, height: 28)
            ResizeHandleDot()
        }
        .contentShape(Rectangle())
        .position(handle.position(in: rect))
        .help(handle.helpTitle)
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let isLoupeRequested = NSEvent.modifierFlags.contains(.option)
                    model.resizeSelection(
                        handle: handle,
                        translation: value.translation,
                        viewSize: viewSize,
                        isLoupeRequested: isLoupeRequested,
                        loupeOverlaySize: Self.loupeSize
                    )
                }
                .onEnded { _ in
                    model.finishResizeSelection()
                }
        )
    }

    private func commitPrimarySelection() {
        let quickPresetID: UUID? = if model.mode == .video,
                                      NSEvent.modifierFlags.contains(.option) {
            quickRecordingConfiguration.activePresetID
        } else {
            nil
        }

        commitSelection(quickPresetID: quickPresetID)
    }

    private func commitSelection(quickPresetID: UUID? = nil) {
        do {
            guard let draft = try model.draft() else {
                return
            }

            switch model.mode {
            case .video:
                if let quickPresetID {
                    onQuickSelect(draft, quickPresetID)
                } else {
                    onSelect(draft)
                }
            case .photo:
                onCaptureScreenshot(draft)
            }
        } catch {
            NSSound.beep()
        }
    }

    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        guard model.selection != nil else {
            return
        }

        let flags = NSEvent.modifierFlags
        let step = flags.contains(.shift) ? 10 : 1
        let delta: CaptureResizeDelta = switch direction {
        case .up:
            CaptureResizeDelta(x: 0, y: -step)
        case .down:
            CaptureResizeDelta(x: 0, y: step)
        case .left:
            CaptureResizeDelta(x: -step, y: 0)
        case .right:
            CaptureResizeDelta(x: step, y: 0)
        @unknown default:
            CaptureResizeDelta(x: 0, y: 0)
        }

        if flags.contains(.option) {
            model.resizeSelectionBy(width: delta.x, height: delta.y)
        } else {
            model.nudgeSelection(x: delta.x, y: delta.y)
        }
    }

    @ViewBuilder
    private func countdownButton(title: String, duration: TimeInterval?) -> some View {
        Button {
            model.setCountdownDuration(duration)
        } label: {
            if model.countdownDuration == duration {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    @ViewBuilder
    private func stopAfterButton(title: String, duration: TimeInterval?) -> some View {
        Button {
            model.setStopAfterDuration(duration)
        } label: {
            if model.stopAfterDuration == duration {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private func applyCustomStopAfterDuration() {
        guard model.applyCustomStopAfterDuration() else {
            NSSound.beep()
            return
        }
    }

    private func applyCustomAspectRatio() {
        guard model.applyCustomAspectRatio() else {
            NSSound.beep()
            return
        }
    }

    private var customStopAfterText: Binding<String> {
        Binding {
            model.customStopAfterText
        } set: { text in
            model.setCustomStopAfterText(text)
        }
    }

    private var customAspectRatioWidthText: Binding<String> {
        Binding {
            model.customAspectRatioWidthText
        } set: { text in
            model.setCustomAspectRatioWidthText(text)
        }
    }

    private var customAspectRatioHeightText: Binding<String> {
        Binding {
            model.customAspectRatioHeightText
        } set: { text in
            model.setCustomAspectRatioHeightText(text)
        }
    }

    private var cropperMode: Binding<LuxelCropperMode> {
        Binding {
            model.mode
        } set: { mode in
            model.setMode(mode)
        }
    }

    private var selectionX: Binding<Int> {
        Binding {
            model.selection?.x ?? 0
        } set: { value in
            model.setSelectionX(value)
        }
    }

    private var selectionY: Binding<Int> {
        Binding {
            model.selection?.y ?? 0
        } set: { value in
            model.setSelectionY(value)
        }
    }

    private var selectionWidth: Binding<Int> {
        Binding {
            model.selection?.width ?? 0
        } set: { value in
            model.setSelectionWidth(value)
        }
    }

    private var selectionHeight: Binding<Int> {
        Binding {
            model.selection?.height ?? 0
        } set: { value in
            model.setSelectionHeight(value)
        }
    }

    @ViewBuilder
    private func cameraDeviceButton(title: String, deviceID: String?) -> some View {
        Button {
            let cameraConfiguration = effectiveCameraConfiguration
            currentCameraConfiguration = CropperCameraConfiguration(
                selectedDeviceID: deviceID,
                devices: cameraConfiguration.devices,
                previewStyle: cameraConfiguration.previewStyle
            )
            onCameraSelectionChange(deviceID)
        } label: {
            if effectiveCameraConfiguration.selectedDeviceID == deviceID {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private var effectiveCameraConfiguration: CropperCameraConfiguration {
        currentCameraConfiguration ?? cameraConfiguration
    }

    private var cameraMenuTitle: String {
        effectiveCameraConfiguration.selectedDevice?.name ?? "Camera"
    }

    private var cameraMenuSystemImage: String {
        effectiveCameraConfiguration.selectedDeviceID == nil ? "video.slash" : "video.fill"
    }

    private func updateCameraPreviewShape(_ shape: CameraOverlayShape) {
        let cameraConfiguration = effectiveCameraConfiguration
        let style = cameraConfiguration.previewStyle
        let updatedStyle = CameraPreviewStyle(
            shape: shape,
            size: style.size,
            isMirrored: style.isMirrored
        )
        updateCameraPreviewStyle(updatedStyle, from: cameraConfiguration)
    }

    private func updateCameraPreviewSize(_ size: CameraPreviewSize) {
        let cameraConfiguration = effectiveCameraConfiguration
        let style = cameraConfiguration.previewStyle
        let updatedStyle = CameraPreviewStyle(
            shape: style.shape,
            size: size,
            isMirrored: style.isMirrored
        )
        updateCameraPreviewStyle(updatedStyle, from: cameraConfiguration)
    }

    private func updateCameraPreviewMirror(_ isMirrored: Bool) {
        let cameraConfiguration = effectiveCameraConfiguration
        let style = cameraConfiguration.previewStyle
        let updatedStyle = CameraPreviewStyle(
            shape: style.shape,
            size: style.size,
            isMirrored: isMirrored
        )
        updateCameraPreviewStyle(updatedStyle, from: cameraConfiguration)
    }

    private func updateCameraPreviewStyle(
        _ style: CameraPreviewStyle,
        from cameraConfiguration: CropperCameraConfiguration
    ) {
        currentCameraConfiguration = CropperCameraConfiguration(
            selectedDeviceID: cameraConfiguration.selectedDeviceID,
            devices: cameraConfiguration.devices,
            previewStyle: style
        )
        onCameraPreviewStyleChange(style)
    }

    private func quickPresetSystemImage(for preset: ExportPreset) -> String {
        preset.id == quickRecordingConfiguration.activePresetID ? "bolt.circle.fill" : "bolt.circle"
    }

    private func openFocusSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Focus-Settings.extension") else {
            return
        }

        openURL(url)
    }
}

private extension LuxelCropperMode {
    var toolbarLabel: String {
        switch self {
        case .video:
            "Video"
        case .photo:
            "Photo"
        }
    }
}

private extension LuxelCropperModel {
    var primaryActionTitle: String {
        switch mode {
        case .video:
            "Record"
        case .photo:
            "Capture"
        }
    }

    var primaryActionSystemImage: String {
        switch mode {
        case .video:
            "record.circle"
        case .photo:
            "camera"
        }
    }

    var primaryActionHelp: String {
        switch mode {
        case .video:
            "Record"
        case .photo:
            "Capture"
        }
    }
}

private struct CountdownPreset: Identifiable {
    let duration: TimeInterval
    let title: String

    var id: TimeInterval {
        duration
    }

    static let all: [CountdownPreset] = [
        CountdownPreset(duration: 3, title: "3 s"),
        CountdownPreset(duration: 5, title: "5 s"),
        CountdownPreset(duration: 10, title: "10 s")
    ]
}

private struct StopAfterPreset: Identifiable {
    let duration: TimeInterval
    let title: String

    var id: TimeInterval {
        duration
    }

    static let all: [StopAfterPreset] = [
        StopAfterPreset(duration: 10, title: "10 s"),
        StopAfterPreset(duration: 30, title: "30 s"),
        StopAfterPreset(duration: 60, title: "1 min"),
        StopAfterPreset(duration: 300, title: "5 min")
    ]
}

private struct CropperAudioLevelMeter: View {
    @Bindable var model: LuxelAudioLevelModel

    var body: some View {
        AudioLevelMeterView(sample: model.sample)
    }
}

private struct SelectionNumberField: View {
    let title: String
    @Binding var value: Int

    var body: some View {
        HStack(spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 10, alignment: .leading)

            TextField(title, value: $value, format: .number)
                .labelsHidden()
                .font(.callout)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(width: 58)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

private struct CropperLoupeView: View {
    let sample: CaptureLoupeSample

    var body: some View {
        GlassPanel {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(.black.opacity(0.46))

                    CropperLoupeGrid(sample: sample)
                        .padding(6)

                    Rectangle()
                        .fill(.white.opacity(0.78))
                        .frame(width: 1)

                    Rectangle()
                        .fill(.white.opacity(0.78))
                        .frame(height: 1)
                }
                .frame(width: 136, height: 74)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                HStack(spacing: 8) {
                    Text("x \(sample.readout.cursor.x) y \(sample.readout.cursor.y)")
                    Spacer(minLength: 8)
                    Text(selectionSummary)
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.primary)
            }
        }
        .accessibilityLabel("Selection loupe")
        .accessibilityValue("\(sample.readout.cursor.x), \(sample.readout.cursor.y), \(selectionSummary)")
    }

    private var selectionSummary: String {
        guard let selection = sample.readout.selection else {
            return "No selection"
        }

        return "\(selection.width)x\(selection.height)"
    }
}

private struct CropperLoupeGrid: View {
    let sample: CaptureLoupeSample

    var body: some View {
        Canvas { context, size in
            let columns = min(max(sample.sourceRect.width, 1), 24)
            let rows = min(max(sample.sourceRect.height, 1), 24)
            let cellWidth = size.width / CGFloat(columns)
            let cellHeight = size.height / CGFloat(rows)

            for row in 0..<rows {
                for column in 0..<columns {
                    let intensity = ((row + column).isMultiple(of: 2) ? 0.18 : 0.28)
                    let rect = CGRect(
                        x: CGFloat(column) * cellWidth,
                        y: CGFloat(row) * cellHeight,
                        width: cellWidth,
                        height: cellHeight
                    )
                    context.fill(
                        Path(rect),
                        with: .color(.white.opacity(intensity))
                    )
                }
            }

            var gridPath = Path()
            for column in 0...columns {
                let x = CGFloat(column) * cellWidth
                gridPath.move(to: CGPoint(x: x, y: 0))
                gridPath.addLine(to: CGPoint(x: x, y: size.height))
            }
            for row in 0...rows {
                let y = CGFloat(row) * cellHeight
                gridPath.move(to: CGPoint(x: 0, y: y))
                gridPath.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(gridPath, with: .color(.white.opacity(0.20)), lineWidth: 0.5)
        }
    }
}

private struct ResizeHandleDot: View {
    var body: some View {
        if #available(macOS 26.0, *) {
            Circle()
                .fill(.white.opacity(0.74))
                .frame(width: 12, height: 12)
                .glassEffect(in: .circle)
        } else {
            Circle()
                .fill(.regularMaterial)
                .frame(width: 12, height: 12)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.72), lineWidth: 1)
                }
        }
    }
}

private extension CaptureResizeHandle {
    func position(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft:
            CGPoint(x: rect.minX, y: rect.minY)
        case .top:
            CGPoint(x: rect.midX, y: rect.minY)
        case .topRight:
            CGPoint(x: rect.maxX, y: rect.minY)
        case .left:
            CGPoint(x: rect.minX, y: rect.midY)
        case .right:
            CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomLeft:
            CGPoint(x: rect.minX, y: rect.maxY)
        case .bottom:
            CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomRight:
            CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    var helpTitle: String {
        switch self {
        case .topLeft:
            "Resize top left"
        case .top:
            "Resize top"
        case .topRight:
            "Resize top right"
        case .left:
            "Resize left"
        case .right:
            "Resize right"
        case .bottomLeft:
            "Resize bottom left"
        case .bottom:
            "Resize bottom"
        case .bottomRight:
            "Resize bottom right"
        }
    }
}
