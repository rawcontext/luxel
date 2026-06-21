import AppKit
import LuxelCore
import LuxelPresentation
import SwiftUI

struct LuxelCropperView: View {
    static let loupeSize = CGSize(width: 204, height: 136)
    static let toolbarButtonWidth: CGFloat = 196
    static let toolbarButtonHeight: CGFloat = 30
    static let toolbarControlSpacing: CGFloat = 8
    static let toolbarFullDisplayButtonWidth: CGFloat = 116
    static let toolbarIconButtonSide: CGFloat = 32
    static let toolbarIconWidth: CGFloat = 18
    static let toolbarCornerRadius: CGFloat = 8
    static let resizeHandleHitSize = CGSize(width: 28, height: 28)
    static var toolbarPairedButtonWidth: CGFloat {
        (toolbarButtonWidth - toolbarControlSpacing) / 2
    }
    static var toolbarSizeButtonWidth: CGFloat {
        toolbarButtonWidth - toolbarFullDisplayButtonWidth - toolbarControlSpacing
    }

    @Environment(\.openURL) var openURL
    @State private var activeDragTarget: CropperDragTarget?
    @State var currentCameraConfiguration: CropperCameraConfiguration?

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
}

extension LuxelCropperView {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(model.isDimmedByOtherDisplay ? 0.20 : 0.38)
                    .ignoresSafeArea()
                    .appKitCursor(.crosshair)

                if let selection = model.selection, !model.isDimmedByOtherDisplay {
                    let rect = model.viewRect(for: selection, in: geometry.size)

                    selectionOverlay(rect: rect, viewSize: geometry.size)
                }

                if !model.isDimmedByOtherDisplay {
                    snapGuidesOverlay(viewSize: geometry.size)
                }

                if let loupeSample = model.loupeSample, !model.isDimmedByOtherDisplay {
                    CropperLoupeView(
                        sample: loupeSample
                    )
                    .frame(width: Self.loupeSize.width, height: Self.loupeSize.height)
                    .position(loupePosition(for: loupeSample, viewSize: geometry.size))
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }

                if !model.isDimmedByOtherDisplay {
                    cropperOverlayControls
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let target = dragTarget(for: value.startLocation, viewSize: geometry.size)
                        let flags = NSEvent.modifierFlags

                        if activeDragTarget == nil {
                            activeDragTarget = target
                        }

                        handleDragChanged(
                            value,
                            target: activeDragTarget ?? target,
                            flags: flags,
                            viewSize: geometry.size
                        )
                    }
                    .onEnded { value in
                        handleDragEnded(
                            target: activeDragTarget
                                ?? dragTarget(for: value.startLocation, viewSize: geometry.size)
                        )
                        activeDragTarget = nil
                    }
            )
            .background(cropperKeyboardShortcuts)
            .focusable()
            .onMoveCommand { direction in
                handleMoveCommand(direction)
            }
            .onExitCommand {
                onCancel()
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

            Button("Cancel Cropper Selection") {
                onCancel()
            }
            .keyboardShortcut(.cancelAction)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private var cropperOverlayControls: some View {
        ZStack {
            if shouldShowNotificationReminder {
                VStack {
                    notificationReminderPanel
                        .padding(.top, 28)

                    Spacer()
                }
            }

            HStack(alignment: .center, spacing: 0) {
                cropperControls
                Spacer()
            }
        }
        .padding(.leading, 28)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var shouldShowNotificationReminder: Bool {
        showsNotificationReminder && model.canRecordSelection
    }

    private var cropperControls: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 7) {
                toolbarControl(selectionSummaryHelp) {
                    selectionGeometryControls
                }

                toolbarControl("Select the full current display or apply a saved size preset.") {
                    HStack(spacing: Self.toolbarControlSpacing) {
                        fullDisplayButton
                        sizePresetMenu(width: Self.toolbarSizeButtonWidth)
                    }
                }

                toolbarControl("Constrain the selected area. Current: \(model.aspectRatioSummary).") {
                    aspectRatioMenu(width: Self.toolbarButtonWidth)
                }

                Divider()

                toolbarControl("\(recordAudioHelp) \(cameraMenuHelp)") {
                    HStack(spacing: Self.toolbarControlSpacing) {
                        recordAudioToggle
                        cameraMenu
                    }
                }

                toolbarControl("Delay recording after pressing Record. Current: \(model.countdownSummary).") {
                    HStack(spacing: Self.toolbarControlSpacing) {
                        countdownMenu(width: Self.toolbarPairedButtonWidth)
                        stopAfterMenu(width: Self.toolbarPairedButtonWidth)
                    }
                }

                if model.recordsAudio, let audioLevelModel {
                    toolbarControl("Shows the current microphone input level.") {
                        CropperAudioLevelMeter(model: audioLevelModel)
                    }
                }

                Divider()

                toolbarControl("Record or cancel the selected area.") {
                    HStack(spacing: Self.toolbarControlSpacing) {
                        cancelButton
                        primaryActionButton
                    }
                }
            }
        }
        .fixedSize()
        .appKitCursor(.arrow)
    }

    private func toolbarControl<Content: View>(
        _ help: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack {
            content()
        }
        .frame(width: Self.toolbarButtonWidth, alignment: .leading)
        .contentShape(Rectangle())
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .nativeTooltip(help)
    }

    private func toolbarButtonLabel(
        _ title: String,
        systemImage: String,
        width: CGFloat,
        isActive: Bool = false,
        isDisabled: Bool = false
    ) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .frame(width: Self.toolbarIconWidth)
        }
        .labelStyle(.titleAndIcon)
        .font(.subheadline.weight(.semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.78)
        .foregroundStyle(isDisabled ? .secondary : .primary)
        .padding(.horizontal, 10)
        .frame(width: width, height: Self.toolbarButtonHeight, alignment: .leading)
        .background {
            toolbarBackground(isActive: isActive, isDisabled: isDisabled)
        }
    }

    private func toolbarMenuLabel(_ title: String, systemImage: String? = nil, width: CGFloat)
    -> some View {
        HStack(spacing: systemImage == nil ? 4 : 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .frame(width: Self.toolbarIconWidth)
            }

            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer(minLength: 0)

            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, systemImage == nil ? 9 : 10)
        .frame(width: width, height: Self.toolbarButtonHeight, alignment: .leading)
        .background {
            toolbarBackground()
        }
    }

    private func toolbarIconLabel(
        _ title: String,
        systemImage: String,
        isActive: Bool = false,
        isDisabled: Bool = false
    ) -> some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.iconOnly)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isDisabled ? .secondary : .primary)
            .frame(width: Self.toolbarIconButtonSide, height: Self.toolbarIconButtonSide)
            .background {
                toolbarBackground(isActive: isActive, isDisabled: isDisabled)
            }
    }

    private func actionLabel(
        _ title: String,
        systemImage: String,
        isActive: Bool = false,
        isDisabled: Bool = false
    ) -> some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .foregroundStyle(isDisabled ? .secondary : .primary)
            .frame(width: Self.toolbarPairedButtonWidth, height: Self.toolbarButtonHeight)
            .background {
                toolbarBackground(isActive: isActive, isDisabled: isDisabled)
            }
    }

    private func toolbarBackground(isActive: Bool = false, isDisabled: Bool = false) -> some View {
        RoundedRectangle(cornerRadius: Self.toolbarCornerRadius, style: .continuous)
            .fill(.white.opacity(isDisabled ? 0.08 : isActive ? 0.24 : 0.14))
            .overlay {
                RoundedRectangle(cornerRadius: Self.toolbarCornerRadius, style: .continuous)
                    .stroke(.white.opacity(isDisabled ? 0.05 : 0.08), lineWidth: 1)
            }
    }

    private var fullDisplayButton: some View {
        Button {
            model.selectFullDisplay()
        } label: {
            toolbarButtonLabel(
                "Full Display",
                systemImage: "rectangle.inset.filled",
                width: Self.toolbarFullDisplayButtonWidth
            )
        }
        .buttonStyle(.plain)
        .help("Select the full current display.")
    }

    private func countdownMenu(width: CGFloat = Self.toolbarButtonWidth) -> some View {
        Menu {
            countdownButton(title: "Off", duration: nil)

            Divider()

            ForEach(CountdownPreset.all) { preset in
                countdownButton(title: preset.title, duration: preset.duration)
            }
        } label: {
            countdownMenuLabel(width: width)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .frame(width: width)
    }

    private func stopAfterMenu(width: CGFloat = Self.toolbarButtonWidth) -> some View {
        Menu {
            stopAfterButton(title: "Off", duration: nil)

            Divider()

            ForEach(StopAfterPreset.all) { preset in
                stopAfterButton(title: preset.title, duration: preset.duration)
            }

            Divider()

            TextField("h:mm:ss", text: customStopAfterText)
                .frame(width: 84)
                .help("Enter a custom automatic stop duration.")

            Button {
                applyCustomStopAfterDuration()
            } label: {
                Label("Set Custom", systemImage: "timer")
            }
            .help("Use the custom automatic stop duration.")
        } label: {
            toolbarMenuLabel(compactStopAfterToolbarText, width: width)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .frame(width: width)
    }

    private func aspectRatioMenu(width: CGFloat = Self.toolbarButtonWidth) -> some View {
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
                .help("Use the \(preset.title) aspect ratio for the selected area.")
            }

            Divider()

            TextField("Custom W", text: customAspectRatioWidthText)
                .frame(width: 76)
                .help("Custom aspect ratio width.")
            TextField("Custom H", text: customAspectRatioHeightText)
                .frame(width: 76)
                .help("Custom aspect ratio height.")

            Button {
                applyCustomAspectRatio()
            } label: {
                if let customAspectRatio = model.customAspectRatio {
                    Label("\(customAspectRatio.width):\(customAspectRatio.height)", systemImage: "checkmark")
                } else {
                    Label("Apply Custom", systemImage: "aspectratio")
                }
            }
            .help("Apply the custom aspect ratio values.")
        } label: {
            toolbarMenuLabel(aspectRatioToolbarText, systemImage: "aspectratio", width: width)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .frame(width: width)
        .help("Constrain the selected area. Current: \(model.aspectRatioSummary).")
    }

    private func sizePresetMenu(width: CGFloat = Self.toolbarButtonWidth) -> some View {
        Menu {
            ForEach(model.sizePresets) { preset in
                Button {
                    model.applySizePreset(preset)
                } label: {
                    Text(preset.name)
                }
                .help("Apply the \(preset.name) size preset.")
            }
        } label: {
            toolbarMenuLabel("Size", systemImage: "arrow.up.left.and.arrow.down.right", width: width)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .frame(width: width)
        .help("Apply a saved size preset to the selected area.")
    }

    private func countdownMenuLabel(width: CGFloat = Self.toolbarButtonWidth) -> some View {
        toolbarMenuLabel(compactCountdownToolbarText, width: width)
            .accessibilityLabel("Countdown")
            .accessibilityValue(model.countdownSummary)
    }

    @ViewBuilder
    private var selectionGeometryControls: some View {
        Text(model.selectionSummary)
            .font(.caption)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(width: Self.toolbarButtonWidth)
            .help(selectionSummaryHelp)
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
                        .help("Set the camera overlay shape to \(shape.settingsLabel).")
                    }
                } label: {
                    Label("Shape", systemImage: "circle")
                }
                .help("Set the camera overlay shape.")

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
                        .help("Set the camera overlay size to \(size.settingsLabel).")
                    }
                } label: {
                    Label("Size", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .help("Set the camera overlay size.")

                Button {
                    updateCameraPreviewMirror(!cameraConfiguration.previewStyle.isMirrored)
                } label: {
                    if cameraConfiguration.previewStyle.isMirrored {
                        Label("Mirror", systemImage: "checkmark")
                    } else {
                        Text("Mirror")
                    }
                }
                .help("Flip the camera preview horizontally.")
            }
        } label: {
            toolbarIconLabel(
                cameraToolbarText,
                systemImage: cameraMenuSystemImage,
                isActive: cameraConfiguration.selectedDeviceID != nil
            )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .frame(width: Self.toolbarIconButtonSide, height: Self.toolbarIconButtonSide)
        .accessibilityLabel("Camera")
        .accessibilityValue(cameraToolbarText)
        .help(cameraMenuHelp)
    }

    private var recordAudioToggle: some View {
        Button {
            recordAudio.wrappedValue.toggle()
        } label: {
            toolbarIconLabel(
                microphoneToolbarText,
                systemImage: model.recordsAudio ? "mic.fill" : "mic.slash",
                isActive: model.recordsAudio,
                isDisabled: !model.canToggleRecordAudio
            )
        }
        .buttonStyle(.plain)
        .frame(width: Self.toolbarIconButtonSide, height: Self.toolbarIconButtonSide)
        .disabled(!model.canToggleRecordAudio)
        .accessibilityLabel("Microphone")
        .accessibilityValue(microphoneToolbarText)
        .help(recordAudioHelp)
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
                .help("Open Focus settings to silence notifications while recording.")

                Button {
                    onNotificationReminderDismiss()
                } label: {
                    Label("Dismiss", systemImage: "xmark")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Hide the notification reminder.")
            }
        }
        .fixedSize()
        .appKitCursor(.arrow)
    }

    @ViewBuilder
    private var cancelButton: some View {
        Button {
            onCancel()
        } label: {
            actionLabel("Cancel", systemImage: "xmark")
        }
        .buttonStyle(.plain)
        .frame(width: Self.toolbarPairedButtonWidth)
        .help("Close area selection without recording or capturing.")
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        Button {
            commitPrimarySelection()
        } label: {
            actionLabel(
                model.primaryActionTitle,
                systemImage: model.primaryActionSystemImage,
                isActive: model.canRecordSelection,
                isDisabled: !model.canRecordSelection
            )
        }
        .buttonStyle(.plain)
        .disabled(!model.canRecordSelection)
        .frame(width: Self.toolbarPairedButtonWidth)
        .help(primaryActionHelp)
        .contextMenu {
            Button {
                commitSelection()
            } label: {
                Label("Record", systemImage: "record.circle")
            }
            .help("Record the selected area.")

            if !quickRecordingConfiguration.presets.isEmpty {
                Menu {
                    ForEach(quickRecordingConfiguration.presets) { preset in
                        Button {
                            commitSelection(quickPresetID: preset.id)
                        } label: {
                            Label(preset.name, systemImage: quickPresetSystemImage(for: preset))
                        }
                        .help("Record with the \(preset.name) quick export preset.")
                    }
                } label: {
                    Label("Quick Record", systemImage: "bolt.circle")
                }
                .help("Record with a quick export preset.")
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
                .contentShape(Rectangle())
                .appKitCursor(isMovingSelection ? .closedHand : .openHand)

            ForEach(Self.resizeHandlePresentationOrder, id: \.self) { handle in
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
            x: CGFloat(sample.overlayOrigin.xCoordinate) / CGFloat(model.display.width) * viewSize.width
                + Self.loupeSize.width / 2,
            y: CGFloat(sample.overlayOrigin.yCoordinate) / CGFloat(model.display.height) * viewSize.height
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
                .frame(width: Self.resizeHandleHitSize.width, height: Self.resizeHandleHitSize.height)
            ResizeHandleDot()
        }
        .contentShape(Rectangle())
        .position(resizeHandlePosition(handle, rect: rect, viewSize: viewSize))
        .help(handle.helpTitle)
        .appKitCursor(handle.resizeCursor)
    }

    private var isMovingSelection: Bool {
        if case .move = activeDragTarget {
            return true
        }

        return false
    }

    private static var resizeHandlePresentationOrder: [CaptureResizeHandle] {
        [.top, .left, .right, .bottom, .topLeft, .topRight, .bottomLeft, .bottomRight]
    }

    private static var resizeHandleHitTestingOrder: [CaptureResizeHandle] {
        [.topLeft, .topRight, .bottomLeft, .bottomRight, .top, .left, .right, .bottom]
    }

    private func dragTarget(for point: CGPoint, viewSize: CGSize) -> CropperDragTarget {
        guard let selection = model.selection else {
            return .draw
        }

        let rect = model.viewRect(for: selection, in: viewSize)

        for handle in Self.resizeHandleHitTestingOrder
        where handleHitRect(handle, in: rect, viewSize: viewSize).contains(point) {
            return .resize(handle)
        }

        if rect.contains(point) {
            return .move
        }

        return .draw
    }

    private func handleHitRect(
        _ handle: CaptureResizeHandle,
        in rect: CGRect,
        viewSize: CGSize
    ) -> CGRect {
        let center = resizeHandlePosition(handle, rect: rect, viewSize: viewSize)

        return CGRect(
            x: center.x - Self.resizeHandleHitSize.width / 2,
            y: center.y - Self.resizeHandleHitSize.height / 2,
            width: Self.resizeHandleHitSize.width,
            height: Self.resizeHandleHitSize.height
        )
    }

    private func resizeHandlePosition(
        _ handle: CaptureResizeHandle,
        rect: CGRect,
        viewSize: CGSize
    ) -> CGPoint {
        let position = handle.position(in: rect)
        let horizontalInset = min(Self.resizeHandleHitSize.width / 2, viewSize.width / 2)
        let verticalInset = min(Self.resizeHandleHitSize.height / 2, viewSize.height / 2)

        return CGPoint(
            x: min(
                max(position.x, horizontalInset), max(horizontalInset, viewSize.width - horizontalInset)),
            y: min(max(position.y, verticalInset), max(verticalInset, viewSize.height - verticalInset))
        )
    }

    private func handleDragChanged(
        _ value: DragGesture.Value,
        target: CropperDragTarget,
        flags: NSEvent.ModifierFlags,
        viewSize: CGSize
    ) {
        switch target {
        case .draw:
            let isLoupeRequested = flags.contains(.option)
            let isLoupeActive = model.loupeAlwaysOn || isLoupeRequested
            model.updateSelection(
                start: value.startLocation,
                current: value.location,
                viewSize: viewSize,
                isSnappingDisabled: flags.contains(.command) || isLoupeActive,
                isLoupeRequested: isLoupeRequested,
                loupeOverlaySize: Self.loupeSize
            )

        case .move:
            model.moveSelection(
                translation: value.translation,
                viewSize: viewSize
            )

        case .resize(let handle):
            model.resizeSelection(
                handle: handle,
                translation: value.translation,
                viewSize: viewSize,
                lockingAspectRatio: flags.contains(.command),
                isLoupeRequested: flags.contains(.option),
                loupeOverlaySize: Self.loupeSize
            )
        }
    }

    private func handleDragEnded(target: CropperDragTarget) {
        switch target {
        case .draw:
            model.finishUpdateSelection()
        case .move:
            model.finishMoveSelection()
        case .resize:
            model.finishResizeSelection()
        }
    }

    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        guard model.selection != nil else {
            return
        }

        let flags = NSEvent.modifierFlags
        let step = flags.contains(.shift) ? 10 : 1
        let delta: CaptureResizeDelta =
            switch direction {
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
            model.resizeSelectionBy(width: delta.deltaX, height: delta.deltaY)
        } else {
            model.nudgeSelection(x: delta.deltaX, y: delta.deltaY)
        }
    }

}
