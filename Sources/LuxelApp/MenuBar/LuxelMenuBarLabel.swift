import AppKit
import QuartzCore
import SwiftUI

struct LuxelMenuBarLabel: View {
    @Bindable var model: LuxelMenuModel
    @State private var now = Date()
    @State private var iconAnimationState = LuxelMenuBarIconAnimationState()
    @State private var quickExportProgressPanelController = QuickExportProgressPanelController()

    var body: some View {
        let presentation = model.recordingPresentation(now: now)

        LuxelMenuBarIconView(
            systemImageName: presentation.menuBarSystemImage,
            isAnimating: presentation.animatesMenuBarSystemImage,
            animationState: iconAnimationState
        )
            .background {
                QuickExportProgressPanelHost(
                    model: model,
                    controller: quickExportProgressPanelController
                )
            }
            .accessibilityLabel(Text(presentation.accessibilityLabel))
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    now = Date()
                }
            }
            .task {
                await model.keepCaptureTargetCacheWarm()
            }
    }
}

private struct LuxelMenuBarIconView: NSViewRepresentable {
    let systemImageName: String
    let isAnimating: Bool
    let animationState: LuxelMenuBarIconAnimationState

    func makeNSView(context: Context) -> LuxelMenuBarIconNSView {
        let view = LuxelMenuBarIconNSView()
        view.update(
            systemImageName: systemImageName,
            isAnimating: isAnimating,
            animationState: animationState
        )
        return view
    }

    func updateNSView(_ nsView: LuxelMenuBarIconNSView, context: Context) {
        nsView.update(
            systemImageName: systemImageName,
            isAnimating: isAnimating,
            animationState: animationState
        )
    }
}

@MainActor
private final class LuxelMenuBarIconAnimationState {
    var systemImageName: String?
}

@MainActor
private final class LuxelMenuBarIconNSView: NSView {
    private let previousImageView = NSImageView()
    private let currentImageView = NSImageView()
    private var currentSystemImageName: String?
    private var isAnimating = false
    private let recordingAnimationKey = "media.luxel.menu-bar-recording-opacity"

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 18, height: 18)
    }

    override func layout() {
        super.layout()
        previousImageView.frame = bounds
        currentImageView.frame = bounds
    }

    func update(
        systemImageName: String,
        isAnimating: Bool,
        animationState: LuxelMenuBarIconAnimationState
    ) {
        if currentSystemImageName != systemImageName {
            transition(to: systemImageName, from: animationState.systemImageName)
        }

        animationState.systemImageName = systemImageName
        updateRecordingAnimation(isAnimating)
    }

    private func setup() {
        wantsLayer = true

        for imageView in [previousImageView, currentImageView] {
            imageView.imageScaling = .scaleProportionallyDown
            imageView.contentTintColor = .labelColor
            imageView.wantsLayer = true
            imageView.alphaValue = imageView === currentImageView ? 1 : 0
            addSubview(imageView)
        }
    }

    private func transition(to systemImageName: String, from rememberedSystemImageName: String?) {
        let image = symbolImage(named: systemImageName)
        defer {
            currentSystemImageName = systemImageName
        }

        guard currentSystemImageName != nil else {
            if let rememberedSystemImageName,
               rememberedSystemImageName != systemImageName,
               let rememberedImage = symbolImage(named: rememberedSystemImageName) {
                previousImageView.image = rememberedImage
                previousImageView.alphaValue = 1
                currentImageView.image = image
                currentImageView.alphaValue = 0
                animateImageTransition()
                return
            }

            currentImageView.image = image
            currentImageView.alphaValue = 1
            return
        }

        previousImageView.image = currentImageView.image
        previousImageView.alphaValue = 1
        currentImageView.image = image
        currentImageView.alphaValue = 0
        animateImageTransition()
    }

    private func animateImageTransition() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            previousImageView.animator().alphaValue = 0
            currentImageView.animator().alphaValue = 1
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.previousImageView.image = nil
                self?.previousImageView.alphaValue = 0
            }
        }
    }

    private func updateRecordingAnimation(_ isAnimating: Bool) {
        guard self.isAnimating != isAnimating else {
            return
        }

        self.isAnimating = isAnimating

        if isAnimating {
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = 0.62
            animation.toValue = 1.0
            animation.duration = 1.15
            animation.autoreverses = true
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animation.isRemovedOnCompletion = false
            currentImageView.layer?.opacity = 1
            currentImageView.layer?.add(animation, forKey: recordingAnimationKey)
        } else {
            currentImageView.layer?.removeAnimation(forKey: recordingAnimationKey)
            currentImageView.layer?.opacity = 1
        }
    }

    private func symbolImage(named name: String) -> NSImage? {
        guard let baseImage = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            return nil
        }

        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let image = baseImage.withSymbolConfiguration(configuration) ?? baseImage
        image.isTemplate = true
        return image
    }
}
