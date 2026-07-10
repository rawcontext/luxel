import AppKit
import LuxelCore
import QuartzCore

@MainActor
final class CameraCutoutPreviewLayer: CALayer {
    private var presentedFrame: CameraCutoutCompositedFrame?

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

    func present(_ frame: CameraCutoutCompositedFrame) {
        presentedFrame = frame
        contents = frame.image
    }

    func clear() {
        contents = nil
        presentedFrame = nil
    }
}
