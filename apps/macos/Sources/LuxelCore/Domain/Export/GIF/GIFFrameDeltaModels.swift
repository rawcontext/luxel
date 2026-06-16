import Foundation

public struct GIFPixelRect: Codable, Equatable, Sendable {
    public let originX: Int
    public let originY: Int
    public let width: Int
    public let height: Int

    public init(x originX: Int, y originY: Int, width: Int, height: Int) throws {
        guard originX >= 0, originY >= 0, width > 0, height > 0 else {
            throw GIFEngineModelError.invalidPixelRect
        }

        self.originX = originX
        self.originY = originY
        self.width = width
        self.height = height
    }

    private enum CodingKeys: String, CodingKey {
        case originX = "x"
        case originY = "y"
        case width
        case height
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

        for row in 0..<currentFrame.pixelSize.height {
            for column in 0..<currentFrame.pixelSize.width {
                let index = row * currentFrame.pixelSize.width + column
                if !isNearMatch(
                    previousFrame.pixels[index],
                    currentFrame.pixels[index],
                    tolerance: lossyTolerance
                ) {
                    minX = min(minX, column)
                    minY = min(minY, row)
                    maxX = max(maxX, column)
                    maxY = max(maxY, row)
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

        for row in rect.originY..<(rect.originY + rect.height) {
            let rowStart = row * frame.pixelSize.width + rect.originX
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
