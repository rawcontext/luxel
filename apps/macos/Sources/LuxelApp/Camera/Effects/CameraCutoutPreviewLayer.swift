import AppKit
import QuartzCore

@MainActor
final class CameraCutoutPreviewLayer: CALayer {
    override init() {
        super.init()
        backgroundColor = NSColor.clear.cgColor
        contentsGravity = .resizeAspectFill
        masksToBounds = true
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present(_ image: CGImage) {
        contents = image
    }

    func clear() {
        contents = nil
    }
}
