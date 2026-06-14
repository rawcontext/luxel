import AppKit
import Foundation
import LuxelCore
import QuartzCore
import SwiftUI

struct LuxelMenuBarLabel: View {
    @Bindable var model: LuxelMenuModel
    @State private var now = Date()
    @State private var quickExportProgressPanelController = QuickExportProgressPanelController()

    var body: some View {
        let presentation = model.menuBarStatusPresentation(now: now)

        MenuBarStatusIcon(
            systemImage: presentation.menuBarSystemImage,
            animates: presentation.animatesMenuBarSystemImage
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
    }
}

private struct MenuBarStatusIcon: View {
    let systemImage: String
    let animates: Bool

    var body: some View {
        MenuBarStatusIconView(
            systemImageName: systemImage,
            isAnimating: animates
        )
        .frame(width: 18, height: 18)
    }
}

private struct MenuBarStatusIconView: NSViewRepresentable {
    let systemImageName: String
    let isAnimating: Bool

    func makeNSView(context: Context) -> MenuBarStatusIconNSView {
        let view = MenuBarStatusIconNSView()
        view.update(systemImageName: systemImageName, isAnimating: isAnimating)
        return view
    }

    func updateNSView(_ nsView: MenuBarStatusIconNSView, context: Context) {
        nsView.update(systemImageName: systemImageName, isAnimating: isAnimating)
    }
}

@MainActor
private final class MenuBarStatusIconNSView: NSView {
    private let previousImageView = NSImageView()
    private let currentImageView = NSImageView()
    private var currentSystemImageName: String?
    private var isAnimating = false
    private var symbolImageCache: [String: NSImage] = [:]

    private let pulseAnimationKey = "media.luxel.menu-bar-recording-pulse"

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

    func update(systemImageName: String, isAnimating: Bool) {
        if currentSystemImageName != systemImageName {
            transition(to: systemImageName)
        }

        updatePulse(isAnimating)
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

    private func transition(to systemImageName: String) {
        let image = symbolImage(named: systemImageName)
        defer {
            currentSystemImageName = systemImageName
        }

        guard currentSystemImageName != nil else {
            currentImageView.image = image
            currentImageView.alphaValue = 1
            return
        }

        previousImageView.image = currentImageView.image
        previousImageView.alphaValue = 1
        currentImageView.image = image
        currentImageView.alphaValue = 0

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
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

    private func updatePulse(_ isAnimating: Bool) {
        guard self.isAnimating != isAnimating else {
            return
        }

        self.isAnimating = isAnimating

        if isAnimating {
            let animation = CABasicAnimation(keyPath: "transform.scale")
            animation.fromValue = 0.94
            animation.toValue = 1.08
            animation.duration = 0.9
            animation.autoreverses = true
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animation.isRemovedOnCompletion = false
            currentImageView.layer?.add(animation, forKey: pulseAnimationKey)
        } else {
            currentImageView.layer?.removeAnimation(forKey: pulseAnimationKey)
        }
    }

    private func symbolImage(named name: String) -> NSImage? {
        if let image = symbolImageCache[name] {
            return image
        }

        guard let baseImage = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            return nil
        }

        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let image = baseImage.withSymbolConfiguration(configuration) ?? baseImage
        image.isTemplate = true
        symbolImageCache[name] = image
        return image
    }
}
