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
                    if application == "NETSCAPE2.0",
                       bytes[offset] == 3,
                       bytes[offset + 1] == 1 {
                        loopCount = readUInt16(bytes, offset + 2)
                    }
                    offset = skipSubblocks(bytes, from: offset)
                } else {
                    offset += 2
                    offset = skipSubblocks(bytes, from: offset)
                }
            case 0x2C:
                let packed = bytes[offset + 9]
                imageDescriptors.append(
                    GIFImageDescriptor(
                        x: readUInt16(bytes, offset + 1),
                        y: readUInt16(bytes, offset + 3),
                        width: readUInt16(bytes, offset + 5),
                        height: readUInt16(bytes, offset + 7)
                    ))
                offset += 10
                if (packed & 0b1000_0000) != 0 {
                    offset += 3 * (1 << (Int(packed & 0b0000_0111) + 1))
                }
                offset += 1
                offset = skipSubblocks(bytes, from: offset)
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
