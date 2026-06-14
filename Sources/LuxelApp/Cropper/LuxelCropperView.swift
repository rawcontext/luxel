import AppKit
import LuxelCore
import LuxelPresentation
import SwiftUI

struct LuxelCropperView: View {
    @Bindable var model: LuxelCropperModel
    let audioLevelModel: LuxelAudioLevelModel?
    let onCancel: () -> Void
    let onSelect: (CaptureSelectionDraft) -> Void
    let onCaptureScreenshot: (CaptureSelectionDraft) -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.38)
                    .ignoresSafeArea()

                if let selection = model.selection {
                    let rect = model.viewRect(for: selection, in: geometry.size)

                    selectionOverlay(rect: rect, viewSize: geometry.size)
                }

                VStack {
                    Spacer()
                    cropperControls
                        .padding(.bottom, 28)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        model.updateSelection(
                            start: value.startLocation,
                            current: value.location,
                            viewSize: geometry.size
                        )
                    }
            )
        }
    }

    private var cropperControls: some View {
        GlassPanel {
            HStack(spacing: 12) {
                Text(model.selectionSummary)
                    .font(.callout)
                    .monospacedDigit()
                    .frame(minWidth: 96, alignment: .leading)

                Picker("Mode", selection: $model.mode) {
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

                Toggle(isOn: $model.locksWidescreenRatio) {
                    Label("16:9", systemImage: "rectangle.ratio.16.to.9")
                }
                .toggleStyle(.button)
                .help("Lock 16:9")

                if model.mode == .video {
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

                Button {
                    commitSelection()
                } label: {
                    Label(model.primaryActionTitle, systemImage: model.primaryActionSystemImage)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canRecordSelection)
            }
        }
        .fixedSize()
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
                    model.resizeSelection(
                        handle: handle,
                        translation: value.translation,
                        viewSize: viewSize
                    )
                }
                .onEnded { _ in
                    model.finishResizeSelection()
                }
        )
    }

    private func commitSelection() {
        do {
            guard let draft = try model.draft() else {
                return
            }

            switch model.mode {
            case .video:
                onSelect(draft)
            case .photo:
                onCaptureScreenshot(draft)
            }
        } catch {
            NSSound.beep()
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

    private var customStopAfterText: Binding<String> {
        Binding {
            model.customStopAfterText
        } set: { text in
            model.setCustomStopAfterText(text)
        }
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
