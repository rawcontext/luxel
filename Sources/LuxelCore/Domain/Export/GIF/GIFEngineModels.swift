import Foundation

public enum GIFDitheringMode: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case auto
    case none
    case ordered
    case diffusion
}

public enum GIFLoopMode: Equatable, Hashable, Sendable {
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

public struct RGBColor: Codable, Equatable, Hashable, Sendable {
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
