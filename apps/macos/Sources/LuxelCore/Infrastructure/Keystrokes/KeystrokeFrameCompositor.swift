import CoreGraphics
import Foundation

@MainActor
public final class KeystrokeFrameCompositor {
    private let renderer = KeystrokeChipImageRenderer()

    public init() {}

    public func composite(
        _ frame: CGImage,
        timeline: KeystrokeTimeline?,
        options: KeystrokeRenderOptions?,
        at sourceTime: TimeInterval
    ) -> CGImage {
        guard let timeline,
              let options,
              options.isVisible,
              let planned = try? KeystrokeChipPlanner(renderOptions: options)
                .plannedChips(for: timeline)
        else {
            return frame
        }
        let chips = KeystrokeOverlayLayout.activeChips(at: sourceTime, in: planned)
        guard !chips.isEmpty,
              let colorSpace = frame.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: frame.width,
                height: frame.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else {
            return frame
        }

        let frameRect = CGRect(x: 0, y: 0, width: frame.width, height: frame.height)
        context.draw(frame, in: frameRect)
        var offset: CGFloat = 0
        for chip in chips {
            guard let image = renderer.image(for: chip, options: options) else {
                continue
            }
            let size = CGSize(width: image.width, height: image.height)
            var origin = KeystrokeOverlayLayout.origin(
                overlaySize: size,
                frameSize: frameRect.size,
                anchor: options.anchor
            )
            switch options.anchor {
            case .bottomLeft, .bottomCenter, .bottomRight:
                origin.y += offset
            case .topLeft, .topCenter, .topRight:
                origin.y -= offset
            }
            context.draw(image, in: CGRect(origin: origin, size: size))
            offset += size.height + 8
        }
        return context.makeImage() ?? frame
    }
}
