import Foundation

enum GIFFrameBuffer {
    static func validate(elementCount: Int, pixelSize: PixelSize) throws {
        guard elementCount == pixelSize.width * pixelSize.height else {
            throw GIFEngineModelError.invalidFrameBuffer
        }
    }

    static func linearIndex(x column: Int, y row: Int, pixelSize: PixelSize) throws -> Int {
        guard column >= 0, column < pixelSize.width, row >= 0, row < pixelSize.height else {
            throw GIFEngineModelError.pixelOutOfBounds
        }
        return row * pixelSize.width + column
    }
}

public struct GIFFrameSequencePlanner: Sendable {
    public init() {}

    public func frameIndexes(
        frameCount: Int,
        loopMode: GIFLoopMode
    ) throws -> [Int] {
        guard frameCount > 0 else {
            throw GIFEngineModelError.invalidFrameCount
        }

        guard loopMode.hasValidAssociatedValues else {
            throw GIFEngineModelError.invalidLoopCount
        }

        let forward = Array(0..<frameCount)
        guard loopMode == .bounce, frameCount > 1 else {
            return forward
        }

        return forward + stride(from: frameCount - 2, through: 0, by: -1)
    }
}

public struct GIFRGBAPixel: Codable, Equatable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8
    public let alpha: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

public struct GIFPaletteColor: Codable, Equatable, Hashable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init(pixel: GIFRGBAPixel) {
        self.init(red: pixel.red, green: pixel.green, blue: pixel.blue)
    }
}

public struct GIFColorPalette: Codable, Equatable, Sendable {
    public let colors: [GIFPaletteColor]

    public init(colors: [GIFPaletteColor]) throws {
        guard (2...256).contains(colors.count) else {
            throw GIFEngineModelError.invalidPaletteSize
        }

        self.colors = colors
    }

    public func nearestColorIndex(for pixel: GIFRGBAPixel) -> UInt8 {
        let target = GIFPaletteColor(pixel: pixel)
        var bestIndex = 0
        var bestDistance = Int.max

        for index in colors.indices {
            let distance = squaredDistance(from: target, to: colors[index])
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }

        return UInt8(bestIndex)
    }

    private func squaredDistance(from lhs: GIFPaletteColor, to rhs: GIFPaletteColor) -> Int {
        let red = Int(lhs.red) - Int(rhs.red)
        let green = Int(lhs.green) - Int(rhs.green)
        let blue = Int(lhs.blue) - Int(rhs.blue)
        return red * red + green * green + blue * blue
    }
}

final class GIFNearestColorMemo {
    private let palette: GIFColorPalette
    private var cachedIndexes: [UInt32: UInt8] = [:]

    init(palette: GIFColorPalette) {
        self.palette = palette
        cachedIndexes.reserveCapacity(4_096)
    }

    func nearestColorIndex(for pixel: GIFRGBAPixel) -> UInt8 {
        let key = UInt32(pixel.red) << 16 | UInt32(pixel.green) << 8 | UInt32(pixel.blue)
        if let cached = cachedIndexes[key] {
            return cached
        }

        let index = palette.nearestColorIndex(for: pixel)
        cachedIndexes[key] = index
        return index
    }
}

public struct GIFFrameBitmap: Codable, Equatable, Sendable {
    public let pixelSize: PixelSize
    public let pixels: [GIFRGBAPixel]

    public init(pixelSize: PixelSize, pixels: [GIFRGBAPixel]) throws {
        try GIFFrameBuffer.validate(elementCount: pixels.count, pixelSize: pixelSize)
        self.pixelSize = pixelSize
        self.pixels = pixels
    }

    public func linearIndex(x column: Int, y row: Int) throws -> Int {
        try GIFFrameBuffer.linearIndex(x: column, y: row, pixelSize: pixelSize)
    }

    public func pixel(x column: Int, y row: Int) throws -> GIFRGBAPixel {
        try pixels[linearIndex(x: column, y: row)]
    }
}

public struct MedianCutPaletteBuilder: Sendable {
    public init() {}

    public func palette(
        from frames: [GIFFrameBitmap],
        maxColorCount: Int,
        transparentAlphaThreshold: UInt8? = nil
    ) throws -> GIFColorPalette {
        guard !frames.isEmpty else {
            throw GIFEngineModelError.invalidFrameCount
        }

        guard (2...256).contains(maxColorCount) else {
            throw GIFEngineModelError.invalidPaletteSize
        }

        let weightedColors = weightedSampledColors(
            from: frames,
            transparentAlphaThreshold: transparentAlphaThreshold
        )
        guard !weightedColors.isEmpty else {
            return try GIFColorPalette(
                colors: normalizedPaletteColors(
                    [.black],
                    maxColorCount: maxColorCount
                ))
        }

        if weightedColors.count <= maxColorCount {
            return try GIFColorPalette(
                colors: normalizedPaletteColors(
                    weightedColors.map(\.color),
                    maxColorCount: maxColorCount
                ))
        }

        var boxes = [MedianCutColorBox(colors: weightedColors)]
        while boxes.count < maxColorCount {
            guard let boxIndex = boxes.bestSplittableBoxIndex(),
                  let splitBoxes = boxes[boxIndex].split()
            else {
                break
            }

            boxes.remove(at: boxIndex)
            boxes.append(splitBoxes.left)
            boxes.append(splitBoxes.right)
        }

        return try GIFColorPalette(
            colors: normalizedPaletteColors(
                boxes.map(\.averageColor),
                maxColorCount: maxColorCount
            ))
    }

    private func weightedSampledColors(
        from frames: [GIFFrameBitmap],
        transparentAlphaThreshold: UInt8?
    ) -> [WeightedGIFColor] {
        var counts: [GIFPaletteColor: Int] = [:]

        for frame in frames {
            for pixel in sampledPixels(from: frame) {
                if let transparentAlphaThreshold, pixel.alpha < transparentAlphaThreshold {
                    continue
                }

                counts[GIFPaletteColor(pixel: pixel), default: 0] += 1
            }
        }

        return
            counts
            .map { WeightedGIFColor(color: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                Self.sortsBefore(lhs.color, rhs.color)
            }
    }

    private func sampledPixels(from frame: GIFFrameBitmap) -> [GIFRGBAPixel] {
        let sampledWidth = min(frame.pixelSize.width, 64)
        let sampledHeight = min(frame.pixelSize.height, 64)

        guard sampledWidth < frame.pixelSize.width || sampledHeight < frame.pixelSize.height else {
            return frame.pixels
        }

        var pixels: [GIFRGBAPixel] = []
        pixels.reserveCapacity(sampledWidth * sampledHeight)

        for sampleRow in 0..<sampledHeight {
            let sourceRow = min(
                frame.pixelSize.height - 1, sampleRow * frame.pixelSize.height / sampledHeight)
            for sampleColumn in 0..<sampledWidth {
                let sourceColumn = min(
                    frame.pixelSize.width - 1, sampleColumn * frame.pixelSize.width / sampledWidth)
                pixels.append(frame.pixels[sourceRow * frame.pixelSize.width + sourceColumn])
            }
        }

        return pixels
    }

    private func normalizedPaletteColors(
        _ colors: [GIFPaletteColor],
        maxColorCount: Int
    ) -> [GIFPaletteColor] {
        var normalized = Array(
            colors
                .uniqued()
                .sorted(by: Self.sortsBefore)
                .prefix(maxColorCount)
        )

        if normalized.count == 1 {
            normalized.append(normalized[0] == .black ? .white : .black)
            normalized.sort(by: Self.sortsBefore)
        }

        return normalized
    }

    static func sortsBefore(_ lhs: GIFPaletteColor, _ rhs: GIFPaletteColor) -> Bool {
        if lhs.red != rhs.red {
            return lhs.red < rhs.red
        }

        if lhs.green != rhs.green {
            return lhs.green < rhs.green
        }

        return lhs.blue < rhs.blue
    }
}
