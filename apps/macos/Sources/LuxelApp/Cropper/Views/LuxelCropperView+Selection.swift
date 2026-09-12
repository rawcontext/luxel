import AppKit
import LuxelCore
import SwiftUI

extension LuxelCropperView {
    func selectionOverlay(rect: CGRect, viewSize: CGSize) -> some View {
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

    func dimensionPill(
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
        .accessibilityValue(LuxelLocalization.format("%d by %d", selection.width, selection.height))
        .help("Edit the exact selection size in pixels.")
    }

    func dimensionPillPosition(rect: CGRect, viewSize: CGSize) -> CGPoint {
        let fitsInside =
            rect.width >= Self.dimensionPillMinimumSelectionSize.width
            && rect.height >= Self.dimensionPillMinimumSelectionSize.height
        let pillY = fitsInside ? rect.midY : rect.minY - 26

        return CGPoint(
            x: min(max(rect.midX, 76), max(76, viewSize.width - 76)),
            y: min(max(pillY, 22), max(22, viewSize.height - 22))
        )
    }

    var dimensionEditor: some View {
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

    func beginEditingDimensions() {
        guard let selection = model.selection else {
            return
        }

        dimensionWidthText = "\(selection.width)"
        dimensionHeightText = "\(selection.height)"
        isEditingDimensions = true
    }

    func applyEditedDimensions() {
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

    func snapGuidesOverlay(viewSize: CGSize) -> some View {
        ZStack {
            ForEach(Array(model.snapGuides.enumerated()), id: \.offset) { _, guide in
                snapGuideLine(guide, viewSize: viewSize)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    func snapGuideLine(_ guide: CaptureSnapGuide, viewSize: CGSize) -> some View {
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

    func loupePosition(for sample: CaptureLoupeSample, viewSize: CGSize) -> CGPoint {
        CGPoint(
            x: CGFloat(sample.overlayOrigin.xCoordinate) / CGFloat(model.display.width) * viewSize.width
                + Self.loupeSize.width / 2,
            y: CGFloat(sample.overlayOrigin.yCoordinate) / CGFloat(model.display.height) * viewSize.height
                + Self.loupeSize.height / 2
        )
    }

    func resizeHandle(
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

    var isMovingSelection: Bool {
        if case .move = activeDragTarget {
            return true
        }

        return false
    }

    static var resizeHandlePresentationOrder: [CaptureResizeHandle] {
        [.top, .left, .right, .bottom, .topLeft, .topRight, .bottomLeft, .bottomRight]
    }

    static var resizeHandleHitTestingOrder: [CaptureResizeHandle] {
        [.topLeft, .topRight, .bottomLeft, .bottomRight, .top, .left, .right, .bottom]
    }

    func dragTarget(for point: CGPoint, viewSize: CGSize) -> CropperDragTarget {
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

    func handleHitRect(
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

    func resizeHandlePosition(
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

    func handleDragChanged(
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

    func handleDragEnded(target: CropperDragTarget) {
        switch target {
        case .draw:
            model.finishUpdateSelection()
        case .move:
            model.finishMoveSelection()
        case .resize:
            model.finishResizeSelection()
        }
    }

    func handleMoveCommand(_ direction: MoveCommandDirection) {
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
