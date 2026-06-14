import Foundation

public enum GIFDitheringMode: String, Codable, CaseIterable, Equatable, Sendable {
    case auto
    case none
    case ordered
    case diffusion
}

public enum GIFLoopMode: Equatable, Sendable {
    case forever
    case none
    case count(Int)
    case bounce

    public static func counted(_ count: Int) throws -> GIFLoopMode {
        guard Self.isValidCount(count) else {
            throw GIFEngineModelError.invalidLoopCount
        }

        return .count(count)
    }

    public var imageIOLoopCount: Int? {
        switch self {
        case .forever, .bounce:
            0
        case .none:
            nil
        case .count(let count):
            count
        }
    }

    var hasValidAssociatedValues: Bool {
        switch self {
        case .forever, .none, .bounce:
            true
        case .count(let count):
            Self.isValidCount(count)
        }
    }

    private static func isValidCount(_ count: Int) -> Bool {
        (1...100).contains(count)
    }
}

extension GIFLoopMode: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case count
    }

    private enum Kind: String, Codable {
        case forever
        case none
        case count
        case bounce
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .forever:
            self = .forever
        case .none:
            self = .none
        case .count:
            self = try .counted(container.decode(Int.self, forKey: .count))
        case .bounce:
            self = .bounce
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .forever:
            try container.encode(Kind.forever, forKey: .kind)
        case .none:
            try container.encode(Kind.none, forKey: .kind)
        case .count(let count):
            guard Self.isValidCount(count) else {
                throw GIFEngineModelError.invalidLoopCount
            }

            try container.encode(Kind.count, forKey: .kind)
            try container.encode(count, forKey: .count)
        case .bounce:
            try container.encode(Kind.bounce, forKey: .kind)
        }
    }
}

public struct RGBColor: Codable, Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) throws {
        guard Self.isValidComponent(red),
              Self.isValidComponent(green),
              Self.isValidComponent(blue) else {
            throw GIFEngineModelError.invalidColor
        }

        self.red = red
        self.green = green
        self.blue = blue
    }

    private enum CodingKeys: String, CodingKey {
        case red
        case green
        case blue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            red: container.decode(Double.self, forKey: .red),
            green: container.decode(Double.self, forKey: .green),
            blue: container.decode(Double.self, forKey: .blue)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(red, forKey: .red)
        try container.encode(green, forKey: .green)
        try container.encode(blue, forKey: .blue)
    }

    private static func isValidComponent(_ value: Double) -> Bool {
        value.isFinite && (0...1).contains(value)
    }
}

public struct GIFRenderOptions: Codable, Equatable, Sendable {
    public let loopMode: GIFLoopMode
    public let dithering: GIFDitheringMode
    public let paletteSize: Int
    public let lossyTolerance: Int
    public let backgroundMatte: RGBColor?

    public static let standard = GIFRenderOptions(
        uncheckedLoopMode: .forever,
        dithering: .auto,
        paletteSize: 256,
        lossyTolerance: 0,
        backgroundMatte: nil
    )

    public init(
        loopMode: GIFLoopMode = .forever,
        dithering: GIFDitheringMode = .auto,
        paletteSize: Int = 256,
        lossyTolerance: Int = 0,
        backgroundMatte: RGBColor? = nil
    ) throws {
        guard loopMode.hasValidAssociatedValues else {
            throw GIFEngineModelError.invalidLoopCount
        }

        guard (2...256).contains(paletteSize) else {
            throw GIFEngineModelError.invalidPaletteSize
        }

        guard (0...32).contains(lossyTolerance) else {
            throw GIFEngineModelError.invalidLossyTolerance
        }

        self.init(
            uncheckedLoopMode: loopMode,
            dithering: dithering,
            paletteSize: paletteSize,
            lossyTolerance: lossyTolerance,
            backgroundMatte: backgroundMatte
        )
    }

    public init(
        quality: ExportQuality,
        loopMode: GIFLoopMode = .forever,
        dithering: GIFDitheringMode = .auto,
        backgroundMatte: RGBColor? = nil
    ) throws {
        switch quality {
        case .compact:
            try self.init(
                loopMode: loopMode,
                dithering: dithering,
                paletteSize: 128,
                lossyTolerance: 8,
                backgroundMatte: backgroundMatte
            )
        case .balanced, .high:
            try self.init(
                loopMode: loopMode,
                dithering: dithering,
                paletteSize: 256,
                lossyTolerance: 0,
                backgroundMatte: backgroundMatte
            )
        case .lossless:
            throw GIFEngineModelError.unsupportedQuality(quality)
        }
    }

    private init(
        uncheckedLoopMode loopMode: GIFLoopMode,
        dithering: GIFDitheringMode,
        paletteSize: Int,
        lossyTolerance: Int,
        backgroundMatte: RGBColor?
    ) {
        self.loopMode = loopMode
        self.dithering = dithering
        self.paletteSize = paletteSize
        self.lossyTolerance = lossyTolerance
        self.backgroundMatte = backgroundMatte
    }

    private enum CodingKeys: String, CodingKey {
        case loopMode
        case dithering
        case paletteSize
        case lossyTolerance
        case backgroundMatte
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            loopMode: container.decode(GIFLoopMode.self, forKey: .loopMode),
            dithering: container.decode(GIFDitheringMode.self, forKey: .dithering),
            paletteSize: container.decode(Int.self, forKey: .paletteSize),
            lossyTolerance: container.decode(Int.self, forKey: .lossyTolerance),
            backgroundMatte: container.decodeIfPresent(RGBColor.self, forKey: .backgroundMatte)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(loopMode, forKey: .loopMode)
        try container.encode(dithering, forKey: .dithering)
        try container.encode(paletteSize, forKey: .paletteSize)
        try container.encode(lossyTolerance, forKey: .lossyTolerance)
        try container.encodeIfPresent(backgroundMatte, forKey: .backgroundMatte)
    }
}

public struct GIFCentisecondDelayPlan: Equatable, Sendable {
    public let centisecondDelays: [Int]

    public init(centisecondDelays: [Int]) throws {
        guard !centisecondDelays.isEmpty,
              centisecondDelays.allSatisfy({ $0 > 0 }) else {
            throw GIFEngineModelError.invalidCentisecondDelay
        }

        self.centisecondDelays = centisecondDelays
    }

    public var delays: [TimeInterval] {
        centisecondDelays.map { TimeInterval($0) / 100 }
    }

    public var totalDuration: TimeInterval {
        TimeInterval(centisecondDelays.reduce(0, +)) / 100
    }
}

public struct CentisecondDelayPlanner: Sendable {
    public init() {}

    public func plan(
        frameCount: Int,
        frameDuration: TimeInterval
    ) throws -> GIFCentisecondDelayPlan {
        guard frameCount > 0 else {
            throw GIFEngineModelError.invalidFrameCount
        }

        return try plan(frameDurations: Array(repeating: frameDuration, count: frameCount))
    }

    public func plan(frameDurations: [TimeInterval]) throws -> GIFCentisecondDelayPlan {
        guard !frameDurations.isEmpty else {
            throw GIFEngineModelError.invalidFrameCount
        }

        var carriedCentiseconds = 0.0
        let centisecondDelays = try frameDurations.map { duration in
            guard duration.isFinite, duration > 0 else {
                throw GIFEngineModelError.invalidFrameDuration
            }

            let exactCentiseconds = duration * 100 + carriedCentiseconds
            let centiseconds = max(1, Int(exactCentiseconds.rounded()))
            carriedCentiseconds = exactCentiseconds - Double(centiseconds)
            return centiseconds
        }

        return try GIFCentisecondDelayPlan(centisecondDelays: centisecondDelays)
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
        let bestIndex = colors.indices.min { lhs, rhs in
            let leftDistance = squaredDistance(from: target, to: colors[lhs])
            let rightDistance = squaredDistance(from: target, to: colors[rhs])
            if leftDistance == rightDistance {
                return lhs < rhs
            }

            return leftDistance < rightDistance
        } ?? 0

        return UInt8(bestIndex)
    }

    private func squaredDistance(from lhs: GIFPaletteColor, to rhs: GIFPaletteColor) -> Int {
        let red = Int(lhs.red) - Int(rhs.red)
        let green = Int(lhs.green) - Int(rhs.green)
        let blue = Int(lhs.blue) - Int(rhs.blue)
        return red * red + green * green + blue * blue
    }
}

public struct GIFFrameBitmap: Codable, Equatable, Sendable {
    public let pixelSize: PixelSize
    public let pixels: [GIFRGBAPixel]

    public init(pixelSize: PixelSize, pixels: [GIFRGBAPixel]) throws {
        guard pixels.count == pixelSize.width * pixelSize.height else {
            throw GIFEngineModelError.invalidFrameBuffer
        }

        self.pixelSize = pixelSize
        self.pixels = pixels
    }

    public func pixel(x: Int, y: Int) throws -> GIFRGBAPixel {
        try pixels[linearIndex(x: x, y: y)]
    }

    public func linearIndex(x: Int, y: Int) throws -> Int {
        guard x >= 0, x < pixelSize.width, y >= 0, y < pixelSize.height else {
            throw GIFEngineModelError.pixelOutOfBounds
        }

        return y * pixelSize.width + x
    }
}

public struct MedianCutPaletteBuilder: Sendable {
    public init() {}

    public func palette(
        from frames: [GIFFrameBitmap],
        maxColorCount: Int
    ) throws -> GIFColorPalette {
        guard !frames.isEmpty else {
            throw GIFEngineModelError.invalidFrameCount
        }

        guard (2...256).contains(maxColorCount) else {
            throw GIFEngineModelError.invalidPaletteSize
        }

        let weightedColors = weightedSampledColors(from: frames)
        guard !weightedColors.isEmpty else {
            throw GIFEngineModelError.invalidFrameBuffer
        }

        if weightedColors.count <= maxColorCount {
            return try GIFColorPalette(colors: normalizedPaletteColors(
                weightedColors.map(\.color),
                maxColorCount: maxColorCount
            ))
        }

        var boxes = [MedianCutColorBox(colors: weightedColors)]
        while boxes.count < maxColorCount {
            guard let boxIndex = boxes.bestSplittableBoxIndex(),
                  let splitBoxes = boxes[boxIndex].split() else {
                break
            }

            boxes.remove(at: boxIndex)
            boxes.append(splitBoxes.left)
            boxes.append(splitBoxes.right)
        }

        return try GIFColorPalette(colors: normalizedPaletteColors(
            boxes.map(\.averageColor),
            maxColorCount: maxColorCount
        ))
    }

    private func weightedSampledColors(from frames: [GIFFrameBitmap]) -> [WeightedGIFColor] {
        var counts: [GIFPaletteColor: Int] = [:]

        for frame in frames {
            for pixel in sampledPixels(from: frame) {
                counts[GIFPaletteColor(pixel: pixel), default: 0] += 1
            }
        }

        return counts
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

        for sampleY in 0..<sampledHeight {
            let y = min(frame.pixelSize.height - 1, sampleY * frame.pixelSize.height / sampledHeight)
            for sampleX in 0..<sampledWidth {
                let x = min(frame.pixelSize.width - 1, sampleX * frame.pixelSize.width / sampledWidth)
                pixels.append(frame.pixels[y * frame.pixelSize.width + x])
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

    fileprivate static func sortsBefore(_ lhs: GIFPaletteColor, _ rhs: GIFPaletteColor) -> Bool {
        if lhs.red != rhs.red {
            return lhs.red < rhs.red
        }

        if lhs.green != rhs.green {
            return lhs.green < rhs.green
        }

        return lhs.blue < rhs.blue
    }
}

private struct WeightedGIFColor: Equatable, Sendable {
    let color: GIFPaletteColor
    let count: Int
}

private enum GIFPaletteChannel {
    case red
    case green
    case blue
}

private struct MedianCutColorBox: Sendable {
    let colors: [WeightedGIFColor]

    var canSplit: Bool {
        colors.count > 1
    }

    var population: Int {
        colors.reduce(0) { $0 + $1.count }
    }

    var longestRange: Int {
        range(for: longestChannel)
    }

    var averageColor: GIFPaletteColor {
        let total = max(1, population)
        let red = colors.reduce(0) { $0 + Int($1.color.red) * $1.count }
        let green = colors.reduce(0) { $0 + Int($1.color.green) * $1.count }
        let blue = colors.reduce(0) { $0 + Int($1.color.blue) * $1.count }

        return GIFPaletteColor(
            red: UInt8((Double(red) / Double(total)).rounded()),
            green: UInt8((Double(green) / Double(total)).rounded()),
            blue: UInt8((Double(blue) / Double(total)).rounded())
        )
    }

    func split() -> (left: MedianCutColorBox, right: MedianCutColorBox)? {
        guard colors.count > 1 else {
            return nil
        }

        let sortedColors = colors.sorted { lhs, rhs in
            let channel = longestChannel
            let leftValue = lhs.color.value(for: channel)
            let rightValue = rhs.color.value(for: channel)
            if leftValue == rightValue {
                return MedianCutPaletteBuilder.sortsBefore(lhs.color, rhs.color)
            }

            return leftValue < rightValue
        }
        let halfPopulation = max(1, population / 2)
        var accumulated = 0
        var splitIndex = 1

        for index in sortedColors.indices {
            accumulated += sortedColors[index].count
            if accumulated >= halfPopulation {
                splitIndex = min(max(index + 1, 1), sortedColors.count - 1)
                break
            }
        }

        return (
            left: MedianCutColorBox(colors: Array(sortedColors[..<splitIndex])),
            right: MedianCutColorBox(colors: Array(sortedColors[splitIndex...]))
        )
    }

    private var longestChannel: GIFPaletteChannel {
        let redRange = range(for: .red)
        let greenRange = range(for: .green)
        let blueRange = range(for: .blue)

        if redRange >= greenRange, redRange >= blueRange {
            return .red
        }

        if greenRange >= blueRange {
            return .green
        }

        return .blue
    }

    private func range(for channel: GIFPaletteChannel) -> Int {
        let values = colors.map { $0.color.value(for: channel) }
        guard let minValue = values.min(), let maxValue = values.max() else {
            return 0
        }

        return Int(maxValue) - Int(minValue)
    }
}

private extension Array where Element == MedianCutColorBox {
    func bestSplittableBoxIndex() -> Int? {
        var bestIndex: Int?

        for index in indices where self[index].canSplit {
            if let currentBest = bestIndex {
                if self[index].hasHigherSplitPriority(than: self[currentBest]) {
                    bestIndex = index
                }
            } else {
                bestIndex = index
            }
        }

        return bestIndex
    }
}

private extension MedianCutColorBox {
    func hasHigherSplitPriority(than other: MedianCutColorBox) -> Bool {
        if longestRange != other.longestRange {
            return longestRange > other.longestRange
        }

        if population != other.population {
            return population > other.population
        }

        return colors.count > other.colors.count
    }
}

private extension GIFPaletteColor {
    static let black = GIFPaletteColor(red: 0, green: 0, blue: 0)
    static let white = GIFPaletteColor(red: 255, green: 255, blue: 255)

    func value(for channel: GIFPaletteChannel) -> UInt8 {
        switch channel {
        case .red:
            red
        case .green:
            green
        case .blue:
            blue
        }
    }
}

private extension Array where Element == GIFPaletteColor {
    func uniqued() -> [GIFPaletteColor] {
        var seen: Set<GIFPaletteColor> = []
        var result: [GIFPaletteColor] = []
        result.reserveCapacity(count)

        for color in self where seen.insert(color).inserted {
            result.append(color)
        }

        return result
    }
}

public struct GIFIndexedFrame: Codable, Equatable, Sendable {
    public let pixelSize: PixelSize
    public let colorIndexes: [UInt8]

    public init(pixelSize: PixelSize, colorIndexes: [UInt8]) throws {
        guard colorIndexes.count == pixelSize.width * pixelSize.height else {
            throw GIFEngineModelError.invalidFrameBuffer
        }

        self.pixelSize = pixelSize
        self.colorIndexes = colorIndexes
    }

    public func colorIndex(x: Int, y: Int) throws -> UInt8 {
        try colorIndexes[linearIndex(x: x, y: y)]
    }

    public func linearIndex(x: Int, y: Int) throws -> Int {
        guard x >= 0, x < pixelSize.width, y >= 0, y < pixelSize.height else {
            throw GIFEngineModelError.pixelOutOfBounds
        }

        return y * pixelSize.width + x
    }
}

public struct GIFNearestColorQuantizer: Sendable {
    public init() {}

    public func indexedFrame(
        from frame: GIFFrameBitmap,
        palette: GIFColorPalette
    ) throws -> GIFIndexedFrame {
        try GIFIndexedFrame(
            pixelSize: frame.pixelSize,
            colorIndexes: frame.pixels.map { palette.nearestColorIndex(for: $0) }
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
        var colorIndexes: [UInt8] = []
        colorIndexes.reserveCapacity(frame.pixels.count)

        for y in 0..<frame.pixelSize.height {
            for x in 0..<frame.pixelSize.width {
                let index = y * frame.pixelSize.width + x
                let threshold = Self.bayer4x4[y % 4][x % 4]
                let adjustment = (Double(threshold) - 7.5) * 16
                colorIndexes.append(palette.nearestColorIndex(
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
        var workingPixels = frame.pixels.map(DitherWorkingPixel.init(pixel:))
        var colorIndexes = Array(repeating: UInt8(0), count: frame.pixels.count)

        for y in 0..<frame.pixelSize.height {
            for x in 0..<frame.pixelSize.width {
                let index = y * frame.pixelSize.width + x
                let colorIndex = palette.nearestColorIndex(for: workingPixels[index].pixel)
                let paletteColor = palette.colors[Int(colorIndex)]
                colorIndexes[index] = colorIndex

                let error = workingPixels[index].error(from: paletteColor)
                diffuse(error, factor: 7.0 / 16.0, x: x + 1, y: y, frame: frame, pixels: &workingPixels)
                diffuse(error, factor: 3.0 / 16.0, x: x - 1, y: y + 1, frame: frame, pixels: &workingPixels)
                diffuse(error, factor: 5.0 / 16.0, x: x, y: y + 1, frame: frame, pixels: &workingPixels)
                diffuse(error, factor: 1.0 / 16.0, x: x + 1, y: y + 1, frame: frame, pixels: &workingPixels)
            }
        }

        return try GIFIndexedFrame(pixelSize: frame.pixelSize, colorIndexes: colorIndexes)
    }

    private func diffuse(
        _ error: DitherError,
        factor: Double,
        x: Int,
        y: Int,
        frame: GIFFrameBitmap,
        pixels: inout [DitherWorkingPixel]
    ) {
        guard x >= 0, x < frame.pixelSize.width, y >= 0, y < frame.pixelSize.height else {
            return
        }

        pixels[y * frame.pixelSize.width + x].apply(error, factor: factor)
    }
}

public struct GIFDitheringHeuristic: Sendable {
    public static let flatContentMeanErrorThreshold = 12.0

    public init() {}

    public func resolvedMode(
        for frames: [GIFFrameBitmap],
        palette: GIFColorPalette
    ) throws -> GIFDitheringMode {
        let error = try meanQuantizationError(for: frames, palette: palette)
        return error <= Self.flatContentMeanErrorThreshold ? .none : .diffusion
    }

    public func meanQuantizationError(
        for frames: [GIFFrameBitmap],
        palette: GIFColorPalette
    ) throws -> Double {
        guard !frames.isEmpty else {
            throw GIFEngineModelError.invalidFrameCount
        }

        var errorTotal = 0.0
        var channelCount = 0

        for frame in frames {
            for pixel in frame.pixels {
                let colorIndex = palette.nearestColorIndex(for: pixel)
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

        return try frames.map { frame in
            try indexedFrame(from: frame, palette: palette, resolvedMode: resolvedMode)
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

private extension GIFRGBAPixel {
    func adjustedRGB(by adjustment: Double) -> GIFRGBAPixel {
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

public struct GIFPixelRect: Codable, Equatable, Sendable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int

    public init(x: Int, y: Int, width: Int, height: Int) throws {
        guard x >= 0, y >= 0, width > 0, height > 0 else {
            throw GIFEngineModelError.invalidPixelRect
        }

        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public enum GIFFrameDisposal: String, Codable, CaseIterable, Equatable, Sendable {
    case doNotDispose
    case restoreToBackground
}

public struct GIFFrameDelta: Codable, Equatable, Sendable {
    public let rect: GIFPixelRect
    public let colorIndexes: [UInt8]
    public let transparentColorIndex: UInt8
    public let disposal: GIFFrameDisposal

    public init(
        rect: GIFPixelRect,
        colorIndexes: [UInt8],
        transparentColorIndex: UInt8,
        disposal: GIFFrameDisposal = .doNotDispose
    ) throws {
        guard colorIndexes.count == rect.width * rect.height else {
            throw GIFEngineModelError.invalidFrameBuffer
        }

        self.rect = rect
        self.colorIndexes = colorIndexes
        self.transparentColorIndex = transparentColorIndex
        self.disposal = disposal
    }
}

public struct GIFFrameDiffer: Sendable {
    public init() {}

    public func delta(
        from previousFrame: GIFFrameBitmap?,
        to currentFrame: GIFFrameBitmap,
        indexedFrame: GIFIndexedFrame,
        transparentColorIndex: UInt8 = 0,
        lossyTolerance: Int = 0
    ) throws -> GIFFrameDelta {
        guard (0...32).contains(lossyTolerance) else {
            throw GIFEngineModelError.invalidLossyTolerance
        }

        guard currentFrame.pixelSize == indexedFrame.pixelSize else {
            throw GIFEngineModelError.frameSizeMismatch
        }

        guard let previousFrame else {
            return try fullFrameDelta(
                indexedFrame,
                transparentColorIndex: transparentColorIndex
            )
        }

        guard previousFrame.pixelSize == currentFrame.pixelSize else {
            throw GIFEngineModelError.frameSizeMismatch
        }

        var minX = currentFrame.pixelSize.width
        var minY = currentFrame.pixelSize.height
        var maxX = -1
        var maxY = -1

        for y in 0..<currentFrame.pixelSize.height {
            for x in 0..<currentFrame.pixelSize.width {
                let index = y * currentFrame.pixelSize.width + x
                if !isNearMatch(
                    previousFrame.pixels[index],
                    currentFrame.pixels[index],
                    tolerance: lossyTolerance
                ) {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }

        guard maxX >= minX, maxY >= minY else {
            return try transparentDelta(
                at: currentFrame.pixelSize,
                transparentColorIndex: transparentColorIndex
            )
        }

        let rect = try GIFPixelRect(
            x: minX,
            y: minY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )
        return try GIFFrameDelta(
            rect: rect,
            colorIndexes: croppedIndexes(from: indexedFrame, rect: rect),
            transparentColorIndex: transparentColorIndex
        )
    }

    private func fullFrameDelta(
        _ frame: GIFIndexedFrame,
        transparentColorIndex: UInt8
    ) throws -> GIFFrameDelta {
        try GIFFrameDelta(
            rect: GIFPixelRect(
                x: 0,
                y: 0,
                width: frame.pixelSize.width,
                height: frame.pixelSize.height
            ),
            colorIndexes: frame.colorIndexes,
            transparentColorIndex: transparentColorIndex
        )
    }

    private func transparentDelta(
        at pixelSize: PixelSize,
        transparentColorIndex: UInt8
    ) throws -> GIFFrameDelta {
        try GIFFrameDelta(
            rect: GIFPixelRect(x: 0, y: 0, width: 1, height: 1),
            colorIndexes: [transparentColorIndex],
            transparentColorIndex: transparentColorIndex
        )
    }

    private func croppedIndexes(
        from frame: GIFIndexedFrame,
        rect: GIFPixelRect
    ) -> [UInt8] {
        var indexes: [UInt8] = []
        indexes.reserveCapacity(rect.width * rect.height)

        for y in rect.y..<(rect.y + rect.height) {
            let rowStart = y * frame.pixelSize.width + rect.x
            indexes.append(
                contentsOf: frame.colorIndexes[rowStart..<(rowStart + rect.width)]
            )
        }

        return indexes
    }

    private func isNearMatch(
        _ lhs: GIFRGBAPixel,
        _ rhs: GIFRGBAPixel,
        tolerance: Int
    ) -> Bool {
        abs(Int(lhs.red) - Int(rhs.red)) <= tolerance
            && abs(Int(lhs.green) - Int(rhs.green)) <= tolerance
            && abs(Int(lhs.blue) - Int(rhs.blue)) <= tolerance
            && abs(Int(lhs.alpha) - Int(rhs.alpha)) <= tolerance
    }
}

public enum GIFEngineModelError: Error, Equatable {
    case invalidLoopCount
    case invalidColor
    case invalidPaletteSize
    case invalidLossyTolerance
    case unsupportedQuality(ExportQuality)
    case invalidFrameCount
    case invalidFrameDuration
    case invalidCentisecondDelay
    case invalidFrameBuffer
    case invalidPixelRect
    case pixelOutOfBounds
    case frameSizeMismatch
}
