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
    @State var activeDragTarget: CropperDragTarget?
    @State var currentCameraConfiguration: CropperCameraConfiguration?
    @State var isEditingDimensions = false
    @State var dimensionWidthText = ""
    @State var dimensionHeightText = ""

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

}
