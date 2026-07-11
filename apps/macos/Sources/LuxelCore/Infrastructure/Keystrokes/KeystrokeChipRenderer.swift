import AppKit
import CoreGraphics
import Foundation
import SwiftUI

public struct KeystrokeChipStackView: View {
    public let chips: [KeystrokeChip]
    public let options: KeystrokeRenderOptions

    public init(chips: [KeystrokeChip], options: KeystrokeRenderOptions) {
        self.chips = chips
        self.options = options
    }

    public var body: some View {
        VStack(spacing: metrics.spacing) {
            ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                Text(chip.text)
                    .font(.system(size: metrics.fontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(foregroundStyle)
                    .padding(.horizontal, metrics.horizontalPadding)
                    .padding(.vertical, metrics.verticalPadding)
                    .background(backgroundStyle, in: RoundedRectangle(cornerRadius: metrics.cornerRadius))
                    .overlay {
                        RoundedRectangle(cornerRadius: metrics.cornerRadius)
                            .strokeBorder(borderStyle, lineWidth: metrics.borderWidth)
                    }
            }
        }
        .fixedSize()
    }

    private var metrics: KeystrokeChipMetrics {
        KeystrokeChipMetrics(options.size)
    }

    private var foregroundStyle: Color {
        switch options.theme {
        case .darkGlass, .highContrast:
            .white
        case .lightGlass:
            .black.opacity(0.9)
        }
    }

    private var backgroundStyle: Color {
        switch options.theme {
        case .darkGlass:
            .black.opacity(0.72)
        case .lightGlass:
            .white.opacity(0.82)
        case .highContrast:
            .black
        }
    }

    private var borderStyle: Color {
        switch options.theme {
        case .darkGlass:
            .white.opacity(0.2)
        case .lightGlass:
            .black.opacity(0.18)
        case .highContrast:
            .white
        }
    }
}

@MainActor
public final class KeystrokeChipImageRenderer {
    private struct CacheKey: Hashable {
        let text: String
        let size: KeystrokeOverlaySize
        let theme: KeystrokeOverlayTheme
        let scale: Int
    }

    private var cache: [CacheKey: CGImage] = [:]

    public init() {}

    public func image(
        for chip: KeystrokeChip,
        options: KeystrokeRenderOptions,
        scale: CGFloat = 2
    ) -> CGImage? {
        let key = CacheKey(
            text: chip.text,
            size: options.size,
            theme: options.theme,
            scale: Int((scale * 100).rounded())
        )
        if let image = cache[key] {
            return image
        }

        let renderer = ImageRenderer(
            content: KeystrokeChipStackView(chips: [chip], options: options)
        )
        renderer.scale = scale
        guard let image = renderer.cgImage else {
            return nil
        }
        cache[key] = image
        return image
    }
}

public enum KeystrokeOverlayLayout {
    public static func activeChips(at time: TimeInterval, in chips: [KeystrokeChip]) -> [KeystrokeChip] {
        chips.filter { $0.timeRange.start <= time && time < $0.timeRange.end }
            .sorted { $0.timeRange.start < $1.timeRange.start }
    }

    public static func origin(
        overlaySize: CGSize,
        frameSize: CGSize,
        anchor: KeystrokeOverlayAnchor,
        margin: CGFloat = 32
    ) -> CGPoint {
        let horizontalOrigin = switch anchor {
        case .topLeft, .bottomLeft:
            margin
        case .topCenter, .bottomCenter:
            (frameSize.width - overlaySize.width) / 2
        case .topRight, .bottomRight:
            frameSize.width - overlaySize.width - margin
        }
        let verticalOrigin = switch anchor {
        case .bottomLeft, .bottomCenter, .bottomRight:
            margin
        case .topLeft, .topCenter, .topRight:
            frameSize.height - overlaySize.height - margin
        }
        return CGPoint(x: max(0, horizontalOrigin), y: max(0, verticalOrigin))
    }
}

private struct KeystrokeChipMetrics {
    let fontSize: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let cornerRadius: CGFloat
    let borderWidth: CGFloat
    let spacing: CGFloat

    init(_ size: KeystrokeOverlaySize) {
        switch size {
        case .small:
            self.init(
                fontSize: 16,
                horizontalPadding: 12,
                verticalPadding: 7,
                cornerRadius: 10,
                borderWidth: 1,
                spacing: 6
            )
        case .medium:
            self.init(
                fontSize: 22,
                horizontalPadding: 16,
                verticalPadding: 10,
                cornerRadius: 13,
                borderWidth: 1,
                spacing: 8
            )
        case .large:
            self.init(
                fontSize: 30,
                horizontalPadding: 22,
                verticalPadding: 14,
                cornerRadius: 17,
                borderWidth: 2,
                spacing: 10
            )
        }
    }

    init(
        fontSize: CGFloat,
        horizontalPadding: CGFloat,
        verticalPadding: CGFloat,
        cornerRadius: CGFloat,
        borderWidth: CGFloat,
        spacing: CGFloat
    ) {
        self.fontSize = fontSize
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.cornerRadius = cornerRadius
        self.borderWidth = borderWidth
        self.spacing = spacing
    }
}
