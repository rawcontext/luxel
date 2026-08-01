import Foundation

@testable import LuxelCodecWebM

struct WebMTestDocument {
    let data: Data
    let rootElements: [WebMTestElement]
    let segment: WebMTestElement
    let segmentChildren: [WebMTestElement]

    private let parser: EBMLTestParser

    init(data: Data) throws {
        self.data = data
        let parser = EBMLTestParser(data: data)
        self.parser = parser
        rootElements = try parser.parseElements(in: 0..<data.count)
        guard let segment = rootElements.first(where: { $0.id == WebMTestID.segment }) else {
            throw WebMTestReaderError.missingElement(WebMTestID.segment)
        }

        self.segment = segment
        segmentChildren = try parser.parseElements(in: segment.payloadRange)
    }

    func children(of element: WebMTestElement) throws -> [WebMTestElement] {
        try parser.parseElements(in: element.payloadRange)
    }

    func firstChild(_ id: UInt64, in element: WebMTestElement) throws -> WebMTestElement {
        guard let child = try children(of: element).first(where: { $0.id == id }) else {
            throw WebMTestReaderError.missingElement(id)
        }

        return child
    }

    func topLevelElement(_ id: UInt64) throws -> WebMTestElement {
        guard let element = segmentChildren.first(where: { $0.id == id }) else {
            throw WebMTestReaderError.missingElement(id)
        }

        return element
    }

    func topLevelElements(_ id: UInt64) -> [WebMTestElement] {
        segmentChildren.filter { $0.id == id }
    }

    func element(atSegmentPosition position: UInt64) -> WebMTestElement? {
        let offset = segment.payloadRange.lowerBound + Int(position)
        return segmentChildren.first { $0.headerRange.lowerBound == offset }
    }

    func unsigned(_ element: WebMTestElement) throws -> UInt64 {
        try parser.unsigned(element)
    }

    func string(_ element: WebMTestElement) -> String {
        parser.string(element)
    }

    func binary(_ element: WebMTestElement) -> Data {
        parser.binary(element)
    }

    func double(_ element: WebMTestElement) throws -> Double {
        try parser.double(element)
    }

    func seekEntries() throws -> [(targetID: UInt64, position: UInt64)] {
        let seekHead = try topLevelElement(WebMTestID.seekHead)
        return try children(of: seekHead)
            .filter { $0.id == WebMTestID.seek }
            .map { seek in
                let target = try firstChild(WebMTestID.seekID, in: seek)
                let position = try firstChild(WebMTestID.seekPosition, in: seek)
                return (targetID: parser.idValue(from: binary(target)), position: try unsigned(position))
            }
    }

    func cuePoints() throws -> [WebMTestCuePoint] {
        let cues = try topLevelElement(WebMTestID.cues)
        return try children(of: cues)
            .filter { $0.id == WebMTestID.cuePoint }
            .map { cuePoint in
                let time = try unsigned(firstChild(WebMTestID.cueTime, in: cuePoint))
                let positions = try firstChild(WebMTestID.cueTrackPositions, in: cuePoint)
                return try WebMTestCuePoint(
                    time: time,
                    track: unsigned(firstChild(WebMTestID.cueTrack, in: positions)),
                    clusterPosition: unsigned(firstChild(WebMTestID.cueClusterPosition, in: positions))
                )
            }
    }
}

struct WebMTestElement: Equatable {
    let id: UInt64
    let headerRange: Range<Int>
    let payloadRange: Range<Int>
    let size: UInt64

    var elementRange: Range<Int> {
        headerRange.lowerBound..<payloadRange.upperBound
    }
}

struct WebMTestCuePoint: Equatable {
    let time: UInt64
    let track: UInt64
    let clusterPosition: UInt64
}

enum WebMTestID {
    static let segment = WebMElementID.segment
    static let seekHead = WebMElementID.seekHead
    static let seek = WebMElementID.seek
    static let seekID = WebMElementID.seekID
    static let seekPosition = WebMElementID.seekPosition
    static let info = WebMElementID.info
    static let timestampScale = WebMElementID.timestampScale
    static let duration = WebMElementID.duration
    static let tracks = WebMElementID.tracks
    static let trackEntry = WebMElementID.trackEntry
    static let codecID = WebMElementID.codecID
    static let codecPrivate = WebMElementID.codecPrivate
    static let video = WebMElementID.video
    static let colour = WebMElementID.colour
    static let cluster = WebMElementID.cluster
    static let simpleBlock = WebMElementID.simpleBlock
    static let cues = WebMElementID.cues
    static let cuePoint = WebMElementID.cuePoint
    static let cueTime = WebMElementID.cueTime
    static let cueTrackPositions = WebMElementID.cueTrackPositions
    static let cueTrack = WebMElementID.cueTrack
    static let cueClusterPosition = WebMElementID.cueClusterPosition
}

enum WebMTestReaderError: Error, Equatable {
    case invalidElementHeader
    case invalidElementSize
    case invalidPayloadRange
    case missingElement(UInt64)
    case invalidFloat
}

private struct EBMLTestParser {
    private let bytes: [UInt8]

    init(data: Data) {
        bytes = Array(data)
    }

    func parseElements(in range: Range<Int>) throws -> [WebMTestElement] {
        var elements: [WebMTestElement] = []
        var offset = range.lowerBound

        while offset < range.upperBound {
            let id = try readID(at: offset)
            let size = try readSize(at: id.nextOffset)
            let payloadStart = size.nextOffset
            let payloadEnd = payloadStart + Int(size.value)
            guard payloadEnd <= range.upperBound else {
                throw WebMTestReaderError.invalidPayloadRange
            }

            elements.append(
                WebMTestElement(
                    id: id.value,
                    headerRange: offset..<payloadStart,
                    payloadRange: payloadStart..<payloadEnd,
                    size: size.value
                ))
            offset = payloadEnd
        }

        return elements
    }

    func unsigned(_ element: WebMTestElement) throws -> UInt64 {
        guard element.payloadRange.count <= 8 else {
            throw WebMTestReaderError.invalidElementSize
        }

        return bytes[element.payloadRange].reduce(UInt64(0)) { value, byte in
            (value << 8) | UInt64(byte)
        }
    }

    func string(_ element: WebMTestElement) -> String {
        String(bytes: bytes[element.payloadRange], encoding: .utf8) ?? ""
    }

    func binary(_ element: WebMTestElement) -> Data {
        Data(bytes[element.payloadRange])
    }

    func double(_ element: WebMTestElement) throws -> Double {
        guard element.payloadRange.count == 8 else {
            throw WebMTestReaderError.invalidFloat
        }

        let bits = bytes[element.payloadRange].reduce(UInt64(0)) { value, byte in
            (value << 8) | UInt64(byte)
        }
        return Double(bitPattern: bits)
    }

    func idValue(from data: Data) -> UInt64 {
        data.reduce(UInt64(0)) { value, byte in
            (value << 8) | UInt64(byte)
        }
    }

    private func readID(at offset: Int) throws -> (value: UInt64, nextOffset: Int) {
        let length = try vintLength(at: offset)
        guard offset + length <= bytes.count else {
            throw WebMTestReaderError.invalidElementHeader
        }

        let value = bytes[offset..<(offset + length)].reduce(UInt64(0)) { value, byte in
            (value << 8) | UInt64(byte)
        }
        return (value, offset + length)
    }

    private func readSize(at offset: Int) throws -> (value: UInt64, nextOffset: Int) {
        let length = try vintLength(at: offset)
        guard offset + length <= bytes.count else {
            throw WebMTestReaderError.invalidElementHeader
        }

        let firstByteMask = UInt8((1 << (8 - length)) - 1)
        var value = UInt64(bytes[offset] & firstByteMask)
        for index in (offset + 1)..<(offset + length) {
            value = (value << 8) | UInt64(bytes[index])
        }
        return (value, offset + length)
    }

    private func vintLength(at offset: Int) throws -> Int {
        guard offset < bytes.count else {
            throw WebMTestReaderError.invalidElementHeader
        }

        let firstByte = bytes[offset]
        guard firstByte != 0 else {
            throw WebMTestReaderError.invalidElementHeader
        }

        for length in 1...8 where firstByte & (0x80 >> UInt8(length - 1)) != 0 {
            return length
        }

        throw WebMTestReaderError.invalidElementHeader
    }
}
