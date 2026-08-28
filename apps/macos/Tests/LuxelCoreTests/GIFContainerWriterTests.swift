import Foundation
import ImageIO
import LuxelCore
import Testing

@Suite("GIF container writer")
struct GIFContainerWriterTests {
    @Test("writer emits readable GIF with loop extension and cropped frame descriptors")
    func writerEmitsReadableGIFWithLoopExtensionAndCroppedFrameDescriptors() throws {
        let palette = try testPalette()
        let frames = [
            try GIFFrameDelta(
                rect: GIFPixelRect(x: 0, y: 0, width: 2, height: 2),
                colorIndexes: [0, 1, 1, 0],
                transparentColorIndex: 0
            ),
            try GIFFrameDelta(
                rect: GIFPixelRect(x: 1, y: 0, width: 1, height: 1),
                colorIndexes: [2],
                transparentColorIndex: 0,
                disposal: .restoreToBackground
            )
        ]
        let delays = try GIFCentisecondDelayPlan(centisecondDelays: [5, 7])

        let data = try GIFContainerWriter().data(
            pixelSize: PixelSize(width: 2, height: 2),
            palette: palette,
            frames: frames,
            delays: delays,
            loopMode: .count(3)
        )
        let parsed = try parseGIF(data)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))

        #expect(Array(data.prefix(6)) == Array("GIF89a".utf8))
        #expect(CGImageSourceGetCount(source) == 2)
        #expect(parsed.loopCount == 3)
        #expect(parsed.graphicControls.map(\.delay) == [5, 7])
        #expect(parsed.graphicControls.map(\.transparentColorIndex) == [0, 0])
        #expect(parsed.graphicControls.map(\.disposal) == [1, 2])
        #expect(
            parsed.imageDescriptors == [
                GIFImageDescriptor(x: 0, y: 0, width: 2, height: 2),
                GIFImageDescriptor(x: 1, y: 0, width: 1, height: 1)
            ])
    }

    @Test("LZW output decodes losslessly once the code table crosses width boundaries")
    func lzwOutputDecodesLosslesslyAcrossCodeWidthBoundaries() throws {
        // High-entropy content grows the LZW dictionary through the 512, 1024,
        // and 2048 code-width boundaries and past a 4096-entry table reset —
        // the regions where a miswritten code width desyncs standard decoders.
        let side = 300
        let colors = Self.fullPaletteColors()
        let palette = try GIFColorPalette(colors: colors)
        let colorIndexes = Self.highEntropyIndexes(count: side * side)
        let frame = try GIFFrameDelta(
            rect: GIFPixelRect(x: 0, y: 0, width: side, height: side),
            colorIndexes: colorIndexes,
            transparentColorIndex: 0
        )

        let data = try GIFContainerWriter().data(
            pixelSize: PixelSize(width: side, height: side),
            palette: palette,
            frames: [frame],
            delays: try GIFCentisecondDelayPlan(centisecondDelays: [5]),
            loopMode: .forever
        )

        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == side)
        #expect(image.height == side)

        var decoded = [UInt8](repeating: 0, count: side * side * 4)
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(
            CGContext(
                data: &decoded,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))

        var mismatchedPixelCount = 0
        for pixel in 0..<(side * side) {
            let expected = colors[Int(colorIndexes[pixel])]
            let offset = pixel * 4
            if abs(Int(decoded[offset]) - Int(expected.red)) > 2
                || abs(Int(decoded[offset + 1]) - Int(expected.green)) > 2
                || abs(Int(decoded[offset + 2]) - Int(expected.blue)) > 2
                || decoded[offset + 3] != 255 {
                mismatchedPixelCount += 1
            }
        }
        #expect(mismatchedPixelCount == 0)
    }

}

extension GIFContainerWriterTests {
    @Test("writer rejects invalid frame shape palette indexes and delay counts")
    func writerRejectsInvalidFrameShapePaletteIndexesAndDelayCounts() throws {
        let palette = try testPalette()
        let validFrame = try GIFFrameDelta(
            rect: GIFPixelRect(x: 0, y: 0, width: 1, height: 1),
            colorIndexes: [0],
            transparentColorIndex: 0
        )
        let outOfBoundsFrame = try GIFFrameDelta(
            rect: GIFPixelRect(x: 2, y: 0, width: 1, height: 1),
            colorIndexes: [0],
            transparentColorIndex: 0
        )
        let invalidIndexFrame = try GIFFrameDelta(
            rect: GIFPixelRect(x: 0, y: 0, width: 1, height: 1),
            colorIndexes: [3],
            transparentColorIndex: 0
        )
        let delays = try GIFCentisecondDelayPlan(centisecondDelays: [5])
        let writer = GIFContainerWriter()

        #expect(throws: GIFContainerWriterError.frameDelayCountMismatch) {
            _ = try writer.data(
                pixelSize: PixelSize(width: 2, height: 2),
                palette: palette,
                frames: [validFrame, validFrame],
                delays: delays,
                loopMode: .forever
            )
        }
        #expect(throws: GIFContainerWriterError.frameRectOutOfBounds) {
            _ = try writer.data(
                pixelSize: PixelSize(width: 2, height: 2),
                palette: palette,
                frames: [outOfBoundsFrame],
                delays: delays,
                loopMode: .forever
            )
        }
        #expect(throws: GIFContainerWriterError.colorIndexOutOfPalette) {
            _ = try writer.data(
                pixelSize: PixelSize(width: 2, height: 2),
                palette: palette,
                frames: [invalidIndexFrame],
                delays: delays,
                loopMode: .forever
            )
        }
    }

    private static func fullPaletteColors() -> [GIFPaletteColor] {
        (0..<256).map { (index: Int) -> GIFPaletteColor in
            let blue: Int = (index * 89 + 41) % 256
            return GIFPaletteColor(
                red: UInt8(index),
                green: UInt8(255 - index),
                blue: UInt8(blue)
            )
        }
    }

    private static func highEntropyIndexes(count: Int) -> [UInt8] {
        (0..<count).map { (index: Int) -> UInt8 in
            let value: Int = (index * 31 + (index >> 3) * 17) % 255
            return UInt8(1 + value)
        }
    }

    private func testPalette() throws -> GIFColorPalette {
        try GIFColorPalette(colors: [
            GIFPaletteColor(red: 0, green: 0, blue: 0),
            GIFPaletteColor(red: 255, green: 255, blue: 255),
            GIFPaletteColor(red: 255, green: 0, blue: 0)
        ])
    }

    private func parseGIF(_ data: Data) throws -> ParsedGIF {
        let bytes = Array(data)
        try #require(bytes.count >= 13)
        let packed = bytes[10]
        let hasGlobalColorTable = (packed & 0b1000_0000) != 0
        let globalColorTableSize =
            hasGlobalColorTable
            ? 3 * (1 << (Int(packed & 0b0000_0111) + 1))
            : 0
        var offset = 13 + globalColorTableSize
        var loopCount: Int?
        var graphicControls: [GIFGraphicControl] = []
        var imageDescriptors: [GIFImageDescriptor] = []

        while offset < bytes.count {
            switch bytes[offset] {
            case 0x21:
                parseExtension(
                    bytes,
                    offset: &offset,
                    loopCount: &loopCount,
                    graphicControls: &graphicControls
                )
            case 0x2C:
                imageDescriptors.append(parseImageDescriptor(bytes, offset: &offset))
            case 0x3B:
                return ParsedGIF(
                    loopCount: loopCount,
                    graphicControls: graphicControls,
                    imageDescriptors: imageDescriptors
                )
            default:
                Issue.record("Unexpected GIF byte \(bytes[offset]) at offset \(offset)")
                return ParsedGIF(
                    loopCount: loopCount,
                    graphicControls: graphicControls,
                    imageDescriptors: imageDescriptors
                )
            }
        }

        return ParsedGIF(
            loopCount: loopCount,
            graphicControls: graphicControls,
            imageDescriptors: imageDescriptors
        )
    }

    private func parseExtension(
        _ bytes: [UInt8],
        offset: inout Int,
        loopCount: inout Int?,
        graphicControls: inout [GIFGraphicControl]
    ) {
        let label = bytes[offset + 1]
        if label == 0xF9 {
            let packed = bytes[offset + 3]
            graphicControls.append(
                GIFGraphicControl(
                    disposal: Int((packed >> 2) & 0b0000_0111),
                    delay: readUInt16(bytes, offset + 4),
                    transparentColorIndex: bytes[offset + 6]
                ))
            offset += 8
        } else if label == 0xFF {
            let blockSize = Int(bytes[offset + 2])
            let application =
                String(
                    bytes: bytes[(offset + 3)..<(offset + 3 + blockSize)],
                    encoding: .utf8
                ) ?? ""
            offset += 3 + blockSize
            if application == "NETSCAPE2.0", bytes[offset] == 3, bytes[offset + 1] == 1 {
                loopCount = readUInt16(bytes, offset + 2)
            }
            offset = skipSubblocks(bytes, from: offset)
        } else {
            offset += 2
            offset = skipSubblocks(bytes, from: offset)
        }
    }

    private func parseImageDescriptor(_ bytes: [UInt8], offset: inout Int) -> GIFImageDescriptor {
        let packed = bytes[offset + 9]
        let descriptor = GIFImageDescriptor(
            x: readUInt16(bytes, offset + 1),
            y: readUInt16(bytes, offset + 3),
            width: readUInt16(bytes, offset + 5),
            height: readUInt16(bytes, offset + 7)
        )
        offset += 10
        if (packed & 0b1000_0000) != 0 {
            offset += 3 * (1 << (Int(packed & 0b0000_0111) + 1))
        }
        offset += 1
        offset = skipSubblocks(bytes, from: offset)
        return descriptor
    }

    private func skipSubblocks(_ bytes: [UInt8], from offset: Int) -> Int {
        var offset = offset
        while offset < bytes.count {
            let blockSize = Int(bytes[offset])
            offset += 1
            guard blockSize > 0 else {
                return offset
            }
            offset += blockSize
        }
        return offset
    }

    private func readUInt16(_ bytes: [UInt8], _ offset: Int) -> Int {
        Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
    }
}

private struct ParsedGIF {
    let loopCount: Int?
    let graphicControls: [GIFGraphicControl]
    let imageDescriptors: [GIFImageDescriptor]
}

private struct GIFGraphicControl {
    let disposal: Int
    let delay: Int
    let transparentColorIndex: UInt8
}

private struct GIFImageDescriptor: Equatable {
    let originX: Int
    let originY: Int
    let width: Int
    let height: Int

    init(x originX: Int, y originY: Int, width: Int, height: Int) {
        self.originX = originX
        self.originY = originY
        self.width = width
        self.height = height
    }
}
