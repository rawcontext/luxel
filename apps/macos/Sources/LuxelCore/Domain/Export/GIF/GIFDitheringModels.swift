import Foundation

public struct GIFIndexedFrame: Codable, Equatable, Sendable {
    public let pixelSize: PixelSize
    public let colorIndexes: [UInt8]

    public init(pixelSize: PixelSize, colorIndexes: [UInt8]) throws {
        try GIFFrameBuffer.validate(elementCount: colorIndexes.count, pixelSize: pixelSize)
        self.pixelSize = pixelSize
        self.colorIndexes = colorIndexes
    }

    public func colorIndex(x column: Int, y row: Int) throws -> UInt8 {
        try colorIndexes[linearIndex(x: column, y: row)]
    }

    public func linearIndex(x column: Int, y row: Int) throws -> Int {
        try GIFFrameBuffer.linearIndex(x: column, y: row, pixelSize: pixelSize)
    }
}

public struct GIFNearestColorQuantizer: Sendable {
    public init() {}

    public func indexedFrame(
        from frame: GIFFrameBitmap,
        palette: GIFColorPalette
    ) throws -> GIFIndexedFrame {
        let memo = GIFNearestColorMemo(palette: palette)
        return try GIFIndexedFrame(
            pixelSize: frame.pixelSize,
            colorIndexes: frame.pixels.map { memo.nearestColorIndex(for: $0) }
        )
    }
}

public struct OrderedDitherer: Sendable {
    private static let bayer4x4 = [
        [0, 8, 2, 10],
        [12, 4, 14, 6],
        [3, 11, 1, 9],
        [15, 7, 13, 5]
    ]

    public init() {}

    public func indexedFrame(
        from frame: GIFFrameBitmap,
        palette: GIFColorPalette
    ) throws -> GIFIndexedFrame {
        let memo = GIFNearestColorMemo(palette: palette)
        var colorIndexes: [UInt8] = []
        colorIndexes.reserveCapacity(frame.pixels.count)

        for row in 0..<frame.pixelSize.height {
            for column in 0..<frame.pixelSize.width {
                let index = row * frame.pixelSize.width + column
                let threshold = Self.bayer4x4[row % 4][column % 4]
                let adjustment = (Double(threshold) - 7.5) * 16
                colorIndexes.append(
                    memo.nearestColorIndex(
                        for: frame.pixels[index].adjustedRGB(by: adjustment)
                    ))
            }
        }

        return try GIFIndexedFrame(pixelSize: frame.pixelSize, colorIndexes: colorIndexes)
    }
}

public struct FloydSteinbergDitherer: Sendable {
    public init() {}

    public func indexedFrame(
        from frame: GIFFrameBitmap,
        palette: GIFColorPalette
    ) throws -> GIFIndexedFrame {
        let memo = GIFNearestColorMemo(palette: palette)
        var workingPixels = frame.pixels.map(DitherWorkingPixel.init(pixel:))
        var colorIndexes = Array(repeating: UInt8(0), count: frame.pixels.count)

        for row in 0..<frame.pixelSize.height {
            for column in 0..<frame.pixelSize.width {
                let index = row * frame.pixelSize.width + column
                let colorIndex = memo.nearestColorIndex(for: workingPixels[index].pixel)
                let paletteColor = palette.colors[Int(colorIndex)]
                colorIndexes[index] = colorIndex

                let error = workingPixels[index].error(from: paletteColor)
                diffuse(
                    error,
                    factor: 7.0 / 16.0,
                    at: (column + 1, row),
                    frame: frame,
                    pixels: &workingPixels
                )
                diffuse(
                    error,
                    factor: 3.0 / 16.0,
                    at: (column - 1, row + 1),
                    frame: frame,
                    pixels: &workingPixels
                )
                diffuse(
                    error,
                    factor: 5.0 / 16.0,
                    at: (column, row + 1),
                    frame: frame,
                    pixels: &workingPixels
                )
                diffuse(
                    error,
                    factor: 1.0 / 16.0,
                    at: (column + 1, row + 1),
                    frame: frame,
                    pixels: &workingPixels
                )
            }
        }

        return try GIFIndexedFrame(pixelSize: frame.pixelSize, colorIndexes: colorIndexes)
    }

    private func diffuse(
        _ error: DitherError,
        factor: Double,
        at position: (column: Int, row: Int),
        frame: GIFFrameBitmap,
        pixels: inout [DitherWorkingPixel]
    ) {
        let (column, row) = position
        guard column >= 0, column < frame.pixelSize.width, row >= 0, row < frame.pixelSize.height else {
            return
        }

        pixels[row * frame.pixelSize.width + column].apply(error, factor: factor)
    }
}

public struct GIFDitheringHeuristic: Sendable {
    public static let flatContentMeanErrorThreshold = 12.0
    private static let maximumSampledFrameCount = 8

    public init() {}

    public func resolvedMode(
        for frames: [GIFFrameBitmap],
        palette: GIFColorPalette
    ) throws -> GIFDitheringMode {
        let error = try meanQuantizationError(
            for: Self.sampledFrames(frames),
            palette: palette
        )
        return error <= Self.flatContentMeanErrorThreshold ? .none : .diffusion
    }

    static func sampledFrames(_ frames: [GIFFrameBitmap]) -> [GIFFrameBitmap] {
        guard frames.count > maximumSampledFrameCount else {
            return frames
        }

        return (0..<maximumSampledFrameCount).map { sampleIndex in
            frames[sampleIndex * (frames.count - 1) / (maximumSampledFrameCount - 1)]
        }
    }

    public func meanQuantizationError(
        for frames: [GIFFrameBitmap],
        palette: GIFColorPalette
    ) throws -> Double {
        guard !frames.isEmpty else {
            throw GIFEngineModelError.invalidFrameCount
        }

        let memo = GIFNearestColorMemo(palette: palette)
        var errorTotal = 0.0
        var channelCount = 0

        for frame in frames {
            for pixel in frame.pixels {
                let colorIndex = memo.nearestColorIndex(for: pixel)
                let color = palette.colors[Int(colorIndex)]
                errorTotal += abs(Double(pixel.red) - Double(color.red))
                errorTotal += abs(Double(pixel.green) - Double(color.green))
                errorTotal += abs(Double(pixel.blue) - Double(color.blue))
                channelCount += 3
            }
        }

        return errorTotal / Double(max(1, channelCount))
    }
}

public struct GIFFrameIndexer: Sendable {
    private let heuristic: GIFDitheringHeuristic

    public init(heuristic: GIFDitheringHeuristic = GIFDitheringHeuristic()) {
        self.heuristic = heuristic
    }

    public func resolvedDitheringMode(
        for frames: [GIFFrameBitmap],
        palette: GIFColorPalette,
        requestedMode: GIFDitheringMode
    ) throws -> GIFDitheringMode {
        switch requestedMode {
        case .auto:
            try heuristic.resolvedMode(for: frames, palette: palette)
        case .none, .ordered, .diffusion:
            requestedMode
        }
    }

    public func indexedFrame(
        from frame: GIFFrameBitmap,
        palette: GIFColorPalette,
        dithering: GIFDitheringMode
    ) throws -> GIFIndexedFrame {
        let resolvedMode = try resolvedDitheringMode(
            for: [frame],
            palette: palette,
            requestedMode: dithering
        )

        return try indexedFrame(from: frame, palette: palette, resolvedMode: resolvedMode)
    }

    public func indexedFrames(
        from frames: [GIFFrameBitmap],
        palette: GIFColorPalette,
        dithering: GIFDitheringMode
    ) throws -> [GIFIndexedFrame] {
        guard !frames.isEmpty else {
            throw GIFEngineModelError.invalidFrameCount
        }

        let resolvedMode = try resolvedDitheringMode(
            for: frames,
            palette: palette,
            requestedMode: dithering
        )

        return try GIFConcurrentMapper.map(count: frames.count) { index in
            try indexedFrame(from: frames[index], palette: palette, resolvedMode: resolvedMode)
        }
    }

    private func indexedFrame(
        from frame: GIFFrameBitmap,
        palette: GIFColorPalette,
        resolvedMode: GIFDitheringMode
    ) throws -> GIFIndexedFrame {
        switch resolvedMode {
        case .auto, .none:
            return try GIFNearestColorQuantizer().indexedFrame(from: frame, palette: palette)
        case .ordered:
            return try OrderedDitherer().indexedFrame(from: frame, palette: palette)
        case .diffusion:
            return try FloydSteinbergDitherer().indexedFrame(from: frame, palette: palette)
        }
    }
}

private struct DitherError: Sendable {
    let red: Double
    let green: Double
    let blue: Double
}

private struct DitherWorkingPixel: Sendable {
    var red: Double
    var green: Double
    var blue: Double

    init(pixel: GIFRGBAPixel) {
        red = Double(pixel.red)
        green = Double(pixel.green)
        blue = Double(pixel.blue)
    }

    var pixel: GIFRGBAPixel {
        GIFRGBAPixel(
            red: clampToUInt8(red),
            green: clampToUInt8(green),
            blue: clampToUInt8(blue)
        )
    }

    func error(from color: GIFPaletteColor) -> DitherError {
        DitherError(
            red: red - Double(color.red),
            green: green - Double(color.green),
            blue: blue - Double(color.blue)
        )
    }

    mutating func apply(_ error: DitherError, factor: Double) {
        red += error.red * factor
        green += error.green * factor
        blue += error.blue * factor
    }
}

extension GIFRGBAPixel {
    fileprivate func adjustedRGB(by adjustment: Double) -> GIFRGBAPixel {
        GIFRGBAPixel(
            red: clampToUInt8(Double(red) + adjustment),
            green: clampToUInt8(Double(green) + adjustment),
            blue: clampToUInt8(Double(blue) + adjustment),
            alpha: alpha
        )
    }
}

private func clampToUInt8(_ value: Double) -> UInt8 {
    UInt8(min(255, max(0, Int(value.rounded()))))
}
