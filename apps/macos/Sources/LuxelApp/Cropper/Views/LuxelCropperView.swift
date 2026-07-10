import AppKit
import LuxelCore
import LuxelPresentation
import SwiftUI

struct LuxelCropperView: View {
    static let loupeSize = CGSize(width: 204, height: 136)
    static let toolbarCircleSide: CGFloat = 36
    static let toolbarPillHeight: CGFloat = 36
    static let toolbarBottomPadding: CGFloat = 22
    static let dimensionPillMinimumSelectionSize = CGSize(width: 170, height: 60)
    static let resizeHandleHitSize = CGSize(width: 28, height: 28)

    @Environment(\.openURL) var openURL
    @State private var activeDragTarget: CropperDragTarget?
    @State var currentCameraConfiguration: CropperCameraConfiguration?
    @State private var isEditingDimensions = false
    @State private var dimensionWidthText = ""
    @State private var dimensionHeightText = ""

    @Bindable var model: LuxelCropperModel
    let cameraConfiguration: CropperCameraConfiguration
    let quickRecordingConfiguration: CropperQuickRecordingConfiguration
    let showsNotificationReminder: Bool
    let toolbarBottomInset: CGFloat
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
        ZStack(alignment: .bottom) {
            if shouldShowNotificationReminder {
                VStack {
                    notificationReminderPanel
                        .padding(.top, 28)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }

            bottomToolbar
                .padding(.bottom, Self.toolbarBottomPadding + toolbarBottomInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private var shouldShowNotificationReminder: Bool {
        showsNotificationReminder && model.canRecordSelection
    }

    private var bottomToolbar: some View {
        HStack(spacing: 6) {
            fullDisplayButton
            sizePresetMenu
            aspectRatioMenu

            toolbarDivider

            recordAudioToggle
            cameraMenu
            countdownMenu
            stopAfterMenu

            toolbarDivider

            cancelButton
            primaryActionButton
        }
        .padding(8)
        .luxelMenuIslandBackground(cornerRadius: 26)
        .background(
            Color.black.opacity(0.32),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .fixedSize()
        .appKitCursor(.arrow)
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.12))
            .frame(width: 1, height: 22)
            .padding(.horizontal, 2)
    }

    private func toolbarCircleLabel(
        _ title: String,
        systemImage: String,
        isActive: Bool = false,
        isDisabled: Bool = false
    ) -> some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.iconOnly)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isDisabled ? .tertiary : isActive ? .primary : .secondary)
            .frame(width: Self.toolbarCircleSide, height: Self.toolbarCircleSide)
            .background {
                toolbarControlBackground(in: Circle(), isActive: isActive, isDisabled: isDisabled)
            }
            .contentShape(Circle())
    }

    private func toolbarPillLabel(_ title: String, isActive: Bool = false) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .lineLimit(1)

            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .font(.subheadline.weight(.medium))
        .padding(.leading, 12)
        .padding(.trailing, 9)
        .frame(height: Self.toolbarPillHeight)
        .background {
            toolbarControlBackground(in: Capsule(style: .continuous), isActive: isActive)
        }
        .contentShape(Capsule(style: .continuous))
    }

    private func toolbarControlBackground<S: InsettableShape>(
        in shape: S,
        isActive: Bool = false,
        isDisabled: Bool = false
    ) -> some View {
        shape
            .fill(.white.opacity(isDisabled ? 0.04 : isActive ? 0.16 : 0.08))
            .overlay {
                shape
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(isDisabled ? 0.05 : isActive ? 0.2 : 0.1), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            }
    }

    private var fullDisplayButton: some View {
        Button {
            model.selectFullDisplay()
        } label: {
            toolbarCircleLabel("Full Display", systemImage: "display")
        }
        .buttonStyle(.plain)
        .help("Select the full current display.")
    }

    private var countdownMenu: some View {
        Menu {
            countdownButton(title: "Off", duration: nil)

            Divider()

            ForEach(CountdownPreset.all) { preset in
                countdownButton(title: preset.title, duration: preset.duration)
            }
        } label: {
            toolbarCircleLabel(
                "Countdown",
                systemImage: "clock",
                isActive: model.countdownDuration != nil
            )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .frame(width: Self.toolbarCircleSide, height: Self.toolbarCircleSide)
        .accessibilityLabel("Countdown")
        .accessibilityValue(model.countdownSummary)
        .help("Delay recording after pressing Record. Current: \(model.countdownSummary).")
    }

    private var stopAfterMenu: some View {
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
            toolbarCircleLabel(
                "Stop After",
                systemImage: "square",
                isActive: model.stopAfterDuration != nil
            )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .frame(width: Self.toolbarCircleSide, height: Self.toolbarCircleSide)
        .accessibilityLabel("Stop After")
        .accessibilityValue(model.stopAfterSummary)
        .help("Stop recording automatically. Current: \(model.stopAfterSummary).")
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
                .help(
                    LuxelLocalization.format(
                        "cropper.aspectRatioPreset.help",
                        defaultValue: "Use the %@ aspect ratio for the selected area.",
                        preset.title)
                )
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
            toolbarPillLabel(model.aspectRatioSummary)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("Aspect Ratio")
        .accessibilityValue(model.aspectRatioSummary)
        .help(
            LuxelLocalization.format(
                "cropper.aspectRatio.currentHelp",
                defaultValue: "Constrain the selected area. Current: %@.",
                model.aspectRatioSummary)
        )
    }

    private var sizePresetMenu: some View {
        Menu {
            ForEach(model.sizePresets) { preset in
                Button {
                    model.applySizePreset(preset)
                } label: {
                    Text(preset.name)
                }
                .help(
                    LuxelLocalization.format(
                        "cropper.sizePreset.applyHelp",
                        defaultValue: "Apply the %@ size preset.",
                        preset.name)
                )
            }
        } label: {
            toolbarPillLabel("Size")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .help("Apply a saved size preset to the selected area.")
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
                        .help(shape.settingsHelp)
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
                        .help(
                            LuxelLocalization.format(
                                "cameraOverlay.size.optionHelp",
                                defaultValue: "Set the camera overlay size to %@.",
                                size.settingsLabel)
                        )
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
            toolbarCircleLabel(
                cameraToolbarText,
                systemImage: cameraMenuSystemImage,
                isActive: cameraConfiguration.selectedDeviceID != nil
            )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .frame(width: Self.toolbarCircleSide, height: Self.toolbarCircleSide)
        .accessibilityLabel("Camera")
        .accessibilityValue(cameraToolbarText)
        .help(cameraMenuHelp)
    }

    private var recordAudioToggle: some View {
        Button {
            recordAudio.wrappedValue.toggle()
        } label: {
            toolbarCircleLabel(
                microphoneToolbarText,
                systemImage: model.recordsAudio ? "mic.fill" : "mic.slash",
                isActive: model.recordsAudio,
                isDisabled: !model.canToggleRecordAudio
            )
        }
        .buttonStyle(.plain)
        .frame(width: Self.toolbarCircleSide, height: Self.toolbarCircleSide)
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
            toolbarCircleLabel("Cancel", systemImage: "xmark")
        }
        .buttonStyle(.plain)
        .help("Close area selection without recording or capturing.")
    }

    private func recordPillLabel(isDisabled: Bool) -> some View {
        HStack(spacing: 7) {
            ZStack {
                Circle()
                    .strokeBorder(.white.opacity(0.9), lineWidth: 2)

                Circle()
                    .fill(.white)
                    .frame(width: 5, height: 5)
            }
            .frame(width: 13, height: 13)

            Text(model.primaryActionTitle)
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(.white)
        .opacity(isDisabled ? 0.55 : 1)
        .padding(.leading, 13)
        .padding(.trailing, 16)
        .frame(height: Self.toolbarPillHeight)
        .background {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            LuxelMenuIslandStyle.recordRedTop,
                            LuxelMenuIslandStyle.recordRedBottom
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.35), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                }
                .saturation(isDisabled ? 0.35 : 1)
                .opacity(isDisabled ? 0.5 : 1)
                .shadow(
                    color: LuxelMenuIslandStyle.recordGlow.opacity(isDisabled ? 0 : 0.35),
                    radius: 11,
                    y: 4
                )
        }
        .contentShape(Capsule(style: .continuous))
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        Button {
            commitPrimarySelection()
        } label: {
            recordPillLabel(isDisabled: !model.canRecordSelection)
        }
        .buttonStyle(.plain)
        .disabled(!model.canRecordSelection)
        .accessibilityLabel(model.primaryActionTitle)
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
                        .help(
                            LuxelLocalization.format(
                                "cropper.quickPreset.recordHelp",
                                defaultValue: "Record with the %@ quick export preset.",
                                preset.name)
                        )
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

            if let selection = model.selection {
                dimensionPill(selection: selection, rect: rect, viewSize: viewSize)
            }
        }
    }

    private func dimensionPill(
        selection: CaptureRect,
        rect: CGRect,
        viewSize: CGSize
    ) -> some View {
        Button {
            beginEditingDimensions()
        } label: {
            HStack(spacing: 6) {
                Text("\(selection.width)")

                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .opacity(0.5)

                Text("\(selection.height)")

                Image(systemName: "pencil")
                    .font(.system(size: 9, weight: .semibold))
                    .opacity(0.45)
                    .padding(.leading, 2)
            }
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassEffect(.clear, in: .capsule)
            .background(Color.black.opacity(0.42), in: Capsule(style: .continuous))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .position(dimensionPillPosition(rect: rect, viewSize: viewSize))
        .popover(isPresented: $isEditingDimensions, arrowEdge: .bottom) {
            dimensionEditor
        }
        .appKitCursor(.arrow)
        .accessibilityLabel("Selection Size")
        .accessibilityValue("\(selection.width) by \(selection.height)")
        .help("Edit the exact selection size in pixels.")
    }

    private func dimensionPillPosition(rect: CGRect, viewSize: CGSize) -> CGPoint {
        let fitsInside =
            rect.width >= Self.dimensionPillMinimumSelectionSize.width
            && rect.height >= Self.dimensionPillMinimumSelectionSize.height
        let pillY = fitsInside ? rect.midY : rect.minY - 26

        return CGPoint(
            x: min(max(rect.midX, 76), max(76, viewSize.width - 76)),
            y: min(max(pillY, 22), max(22, viewSize.height - 22))
        )
    }

    private var dimensionEditor: some View {
        HStack(spacing: 6) {
            TextField("Width", text: $dimensionWidthText)
                .frame(width: 64)

            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("Height", text: $dimensionHeightText)
                .frame(width: 64)

            Button("Apply") {
                applyEditedDimensions()
            }
            .keyboardShortcut(.defaultAction)
        }
        .textFieldStyle(.roundedBorder)
        .monospacedDigit()
        .padding(12)
    }

    private func beginEditingDimensions() {
        guard let selection = model.selection else {
            return
        }

        dimensionWidthText = "\(selection.width)"
        dimensionHeightText = "\(selection.height)"
        isEditingDimensions = true
    }

    private func applyEditedDimensions() {
        guard
            let width = Int(dimensionWidthText.trimmingCharacters(in: .whitespaces)),
            let height = Int(dimensionHeightText.trimmingCharacters(in: .whitespaces)),
            model.setSelectionSize(width: width, height: height)
        else {
            NSSound.beep()
            return
        }

        isEditingDimensions = false
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
