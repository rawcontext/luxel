import Foundation

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
    static let ebml: UInt64 = 0x1A45_DFA3
    static let docType: UInt64 = 0x4282
    static let segment: UInt64 = 0x1853_8067
    static let seekHead: UInt64 = 0x114D_9B74
    static let seek: UInt64 = 0x4DBB
    static let seekID: UInt64 = 0x53AB
    static let seekPosition: UInt64 = 0x53AC
    static let info: UInt64 = 0x1549_A966
    static let timestampScale: UInt64 = 0x2AD7_B1
    static let duration: UInt64 = 0x4489
    static let tracks: UInt64 = 0x1654_AE6B
    static let trackEntry: UInt64 = 0xAE
    static let codecID: UInt64 = 0x86
    static let codecPrivate: UInt64 = 0x63A2
    static let video: UInt64 = 0xE0
    static let colour: UInt64 = 0x55B0
    static let cluster: UInt64 = 0x1F43_B675
    static let clusterTimecode: UInt64 = 0xE7
    static let simpleBlock: UInt64 = 0xA3
    static let cues: UInt64 = 0x1C53_BB6B
    static let cuePoint: UInt64 = 0xBB
    static let cueTime: UInt64 = 0xB3
    static let cueTrackPositions: UInt64 = 0xB7
    static let cueTrack: UInt64 = 0xF7
    static let cueClusterPosition: UInt64 = 0xF1
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
