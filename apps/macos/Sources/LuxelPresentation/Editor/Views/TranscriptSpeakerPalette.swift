import Foundation
import SwiftUI

public enum TranscriptSpeakerPalette {
    private struct ColorComponents {
        let hue: Double
        let saturation: Double
        let brightness: Double
    }

    public static let colorCount = 60

    public static func paletteIndex(for displayName: String) -> Int {
        let normalizedName = displayName.precomposedStringWithCanonicalMapping
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in normalizedName.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return Int(hash % UInt64(colorCount))
    }

    public static func dotColor(for displayName: String) -> Color {
        let components = colorComponents(for: displayName)
        return Color(
            hue: components.hue,
            saturation: components.saturation,
            brightness: components.brightness
        )
    }

    public static func textColor(for displayName: String) -> Color {
        let components = colorComponents(for: displayName)
        return Color(
            hue: components.hue,
            saturation: min(components.saturation, 0.72),
            brightness: max(components.brightness, 0.96)
        )
    }

    private static func colorComponents(
        for displayName: String
    ) -> ColorComponents {
        let index = paletteIndex(for: displayName)
        let hue = Double(index % 30) / 30
        let isDeepVariant = index >= 30
        return ColorComponents(
            hue: hue,
            saturation: isDeepVariant ? 0.82 : 0.68,
            brightness: isDeepVariant ? 0.88 : 0.96
        )
    }
}
