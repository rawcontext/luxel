import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

public final class CameraChromaKeyFilter: @unchecked Sendable {
    private struct HSV {
        let hue: Float
        let saturation: Float
        let value: Float
    }

    private let filter: any CIFilter & CIColorCube

    public init() {
        let filter = CIFilter.colorCube()
        filter.cubeDimension = Float(Self.dimension)
        filter.cubeData = Self.cubeData
        filter.extrapolate = false
        self.filter = filter
    }

    public func apply(to image: CIImage) -> CIImage {
        filter.inputImage = image
        return filter.outputImage ?? image
    }

    private static let dimension = 64

    private static let cubeData: Data = {
        var values = [Float]()
        values.reserveCapacity(dimension * dimension * dimension * 4)

        for blueIndex in 0..<dimension {
            let blue = Float(blueIndex) / Float(dimension - 1)
            for greenIndex in 0..<dimension {
                let green = Float(greenIndex) / Float(dimension - 1)
                for redIndex in 0..<dimension {
                    let red = Float(redIndex) / Float(dimension - 1)
                    let hsv = hsv(red: red, green: green, blue: blue)
                    let hueDistance = min(
                        abs(hsv.hue - greenHue),
                        1 - abs(hsv.hue - greenHue)
                    )
                    let hueMatch = 1 - smoothstep(0.08, 0.16, hueDistance)
                    let saturationMatch = smoothstep(0.22, 0.62, hsv.saturation)
                    let brightnessMatch = smoothstep(0.08, 0.32, hsv.value)
                    let dominance = green - max(red, blue)
                    let dominanceMatch = smoothstep(0.03, 0.22, dominance)
                    let keyStrength = min(
                        1,
                        hueMatch * saturationMatch * brightnessMatch * dominanceMatch
                    )
                    let alpha = 1 - keyStrength
                    let despilledGreen = green + (max(red, blue) - green) * keyStrength

                    values.append(red * alpha)
                    values.append(despilledGreen * alpha)
                    values.append(blue * alpha)
                    values.append(alpha)
                }
            }
        }

        return values.withUnsafeBytes { Data($0) }
    }()

    private static let greenHue: Float = 1.0 / 3.0

    private static func hsv(red: Float, green: Float, blue: Float) -> HSV {
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let delta = maximum - minimum
        let saturation = maximum == 0 ? 0 : delta / maximum
        guard delta > 0 else {
            return HSV(hue: 0, saturation: saturation, value: maximum)
        }

        let hue: Float
        if maximum == red {
            hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6) / 6
        } else if maximum == green {
            hue = ((blue - red) / delta + 2) / 6
        } else {
            hue = ((red - green) / delta + 4) / 6
        }
        return HSV(
            hue: hue < 0 ? hue + 1 : hue,
            saturation: saturation,
            value: maximum
        )
    }

    private static func smoothstep(_ lower: Float, _ upper: Float, _ value: Float) -> Float {
        let position = min(max((value - lower) / (upper - lower), 0), 1)
        return position * position * (3 - 2 * position)
    }
}
