import Foundation

public struct GIFContainerWriter: Sendable {
    public init() {}

    public func data(
        pixelSize: PixelSize,
        palette: GIFColorPalette,
        frames: [GIFFrameDelta],
        delays: GIFCentisecondDelayPlan,
        loopMode: GIFLoopMode
    ) throws -> Data {
        guard !frames.isEmpty else {
            throw GIFContainerWriterError.invalidFrameCount
        }

        guard frames.count == delays.centisecondDelays.count else {
            throw GIFContainerWriterError.frameDelayCountMismatch
        }

        let colorTableSize = Self.globalColorTableSize(for: palette.colors.count)
        try validate(frames: frames, pixelSize: pixelSize, paletteSize: palette.colors.count)

        var output = Data()
        output.appendASCII("GIF89a")
        try appendLogicalScreenDescriptor(
            to: &output,
            pixelSize: pixelSize,
            colorTableSize: colorTableSize
        )
        appendGlobalColorTable(to: &output, palette: palette, colorTableSize: colorTableSize)

        if let loopCount = loopMode.imageIOLoopCount {
            try appendLoopExtension(to: &output, loopCount: loopCount)
        }

        for (frame, delay) in zip(frames, delays.centisecondDelays) {
            try appendGraphicControlExtension(to: &output, frame: frame, delay: delay)
            try appendImageDescriptor(to: &output, frame: frame)
            try appendImageData(to: &output, frame: frame, colorTableSize: colorTableSize)
        }

        output.appendByte(0x3B)
        return output
    }

    public func write(
        pixelSize: PixelSize,
        palette: GIFColorPalette,
        frames: [GIFFrameDelta],
        delays: GIFCentisecondDelayPlan,
        loopMode: GIFLoopMode,
        to outputFileURL: URL
    ) throws {
        let output = try data(
            pixelSize: pixelSize,
            palette: palette,
            frames: frames,
            delays: delays,
            loopMode: loopMode
        )
        try output.write(to: outputFileURL, options: .atomic)
    }

    private func validate(
        frames: [GIFFrameDelta],
        pixelSize: PixelSize,
        paletteSize: Int
    ) throws {
        for frame in frames {
            guard frame.rect.x + frame.rect.width <= pixelSize.width,
                  frame.rect.y + frame.rect.height <= pixelSize.height else {
                throw GIFContainerWriterError.frameRectOutOfBounds
            }

            guard Int(frame.transparentColorIndex) < paletteSize,
                  frame.colorIndexes.allSatisfy({ Int($0) < paletteSize }) else {
                throw GIFContainerWriterError.colorIndexOutOfPalette
            }
        }
    }

    private func appendLogicalScreenDescriptor(
        to output: inout Data,
        pixelSize: PixelSize,
        colorTableSize: Int
    ) throws {
        try output.appendUInt16LittleEndian(pixelSize.width)
        try output.appendUInt16LittleEndian(pixelSize.height)
        let colorTableSizeCode = UInt8(Self.colorTableSizeCode(for: colorTableSize))
        output.appendByte(0b1000_0000 | 0b0111_0000 | colorTableSizeCode)
        output.appendByte(0)
        output.appendByte(0)
    }

    private func appendGlobalColorTable(
        to output: inout Data,
        palette: GIFColorPalette,
        colorTableSize: Int
    ) {
        for color in palette.colors {
            output.appendByte(color.red)
            output.appendByte(color.green)
            output.appendByte(color.blue)
        }

        let paddingColorCount = colorTableSize - palette.colors.count
        guard paddingColorCount > 0 else {
            return
        }

        output.append(contentsOf: Array(repeating: UInt8(0), count: paddingColorCount * 3))
    }

    private func appendLoopExtension(to output: inout Data, loopCount: Int) throws {
        output.appendByte(0x21)
        output.appendByte(0xFF)
        output.appendByte(0x0B)
        output.appendASCII("NETSCAPE2.0")
        output.appendByte(0x03)
        output.appendByte(0x01)
        try output.appendUInt16LittleEndian(loopCount)
        output.appendByte(0x00)
    }

    private func appendGraphicControlExtension(
        to output: inout Data,
        frame: GIFFrameDelta,
        delay: Int
    ) throws {
        output.appendByte(0x21)
        output.appendByte(0xF9)
        output.appendByte(0x04)
        output.appendByte((disposalCode(for: frame.disposal) << 2) | 0x01)
        try output.appendUInt16LittleEndian(delay)
        output.appendByte(frame.transparentColorIndex)
        output.appendByte(0x00)
    }

    private func appendImageDescriptor(to output: inout Data, frame: GIFFrameDelta) throws {
        output.appendByte(0x2C)
        try output.appendUInt16LittleEndian(frame.rect.x)
        try output.appendUInt16LittleEndian(frame.rect.y)
        try output.appendUInt16LittleEndian(frame.rect.width)
        try output.appendUInt16LittleEndian(frame.rect.height)
        output.appendByte(0x00)
    }

    private func appendImageData(
        to output: inout Data,
        frame: GIFFrameDelta,
        colorTableSize: Int
    ) throws {
        let minimumCodeSize = max(2, Self.bitWidth(for: colorTableSize - 1))
        output.appendByte(UInt8(minimumCodeSize))
        let compressedData = try GIFLZWEncoder().encode(
            colorIndexes: frame.colorIndexes,
            minimumCodeSize: minimumCodeSize
        )
        output.appendSubblocks(compressedData)
    }

    private func disposalCode(for disposal: GIFFrameDisposal) -> UInt8 {
        switch disposal {
        case .doNotDispose:
            1
        case .restoreToBackground:
            2
        }
    }

    private static func globalColorTableSize(for colorCount: Int) -> Int {
        var tableSize = 2
        while tableSize < colorCount {
            tableSize *= 2
        }
        return tableSize
    }

    private static func colorTableSizeCode(for colorTableSize: Int) -> Int {
        bitWidth(for: colorTableSize - 1) - 1
    }

    private static func bitWidth(for value: Int) -> Int {
        var value = max(1, value)
        var width = 0
        while value > 0 {
            width += 1
            value >>= 1
        }
        return width
    }
}

public enum GIFContainerWriterError: Error, Equatable {
    case invalidFrameCount
    case frameDelayCountMismatch
    case frameRectOutOfBounds
    case colorIndexOutOfPalette
    case invalidCodeSize
    case invalidUInt16
}

private struct GIFLZWEncoder {
    func encode(colorIndexes: [UInt8], minimumCodeSize: Int) throws -> Data {
        guard (2...8).contains(minimumCodeSize) else {
            throw GIFContainerWriterError.invalidCodeSize
        }

        guard let firstIndex = colorIndexes.first else {
            throw GIFContainerWriterError.invalidFrameCount
        }

        let clearCode = 1 << minimumCodeSize
        let endCode = clearCode + 1
        var codeSize = minimumCodeSize + 1
        var nextCode = endCode + 1
        var dictionary = Self.initialDictionary(clearCode: clearCode)
        var packer = GIFLZWBitPacker()

        packer.write(clearCode, codeSize: codeSize)

        var currentSequence = [firstIndex]
        for colorIndex in colorIndexes.dropFirst() {
            let extendedSequence = currentSequence + [colorIndex]
            if dictionary[extendedSequence] != nil {
                currentSequence = extendedSequence
                continue
            }

            packer.write(dictionary[currentSequence] ?? Int(currentSequence[0]), codeSize: codeSize)

            if nextCode < 4096 {
                dictionary[extendedSequence] = nextCode
                nextCode += 1
                if nextCode == (1 << codeSize), codeSize < 12 {
                    codeSize += 1
                }
            } else {
                packer.write(clearCode, codeSize: codeSize)
                dictionary = Self.initialDictionary(clearCode: clearCode)
                codeSize = minimumCodeSize + 1
                nextCode = endCode + 1
            }

            currentSequence = [colorIndex]
        }

        packer.write(dictionary[currentSequence] ?? Int(currentSequence[0]), codeSize: codeSize)
        packer.write(endCode, codeSize: codeSize)
        return packer.finalizedData()
    }

    private static func initialDictionary(clearCode: Int) -> [[UInt8]: Int] {
        Dictionary(uniqueKeysWithValues: (0..<clearCode).map { code in
            ([UInt8(code)], code)
        })
    }
}

private struct GIFLZWBitPacker {
    private var bytes: [UInt8] = []
    private var accumulator = 0
    private var bitCount = 0

    mutating func write(_ code: Int, codeSize: Int) {
        accumulator |= code << bitCount
        bitCount += codeSize

        while bitCount >= 8 {
            bytes.append(UInt8(accumulator & 0xFF))
            accumulator >>= 8
            bitCount -= 8
        }
    }

    func finalizedData() -> Data {
        var finalizedBytes = bytes
        if bitCount > 0 {
            finalizedBytes.append(UInt8(accumulator & 0xFF))
        }
        return Data(finalizedBytes)
    }
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(contentsOf: string.utf8)
    }

    mutating func appendByte(_ byte: UInt8) {
        append(byte)
    }

    mutating func appendUInt16LittleEndian(_ value: Int) throws {
        guard (0...Int(UInt16.max)).contains(value) else {
            throw GIFContainerWriterError.invalidUInt16
        }

        appendByte(UInt8(value & 0xFF))
        appendByte(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendSubblocks(_ data: Data) {
        var offset = 0
        while offset < data.count {
            let count = Swift.min(255, data.count - offset)
            appendByte(UInt8(count))
            append(contentsOf: data[offset..<(offset + count)])
            offset += count
        }
        appendByte(0)
    }
}
