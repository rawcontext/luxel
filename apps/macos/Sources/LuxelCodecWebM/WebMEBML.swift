import Foundation
import LuxelCore

struct WebMCluster {
    let timecode: Int64
    var blocks = Data()
    var firstVideoKeyframeTimecode: Int64?

    mutating func append(block: Data, packet: WebMPacket, packetTimecode: Int64) throws {
        blocks.append(block)
        if packet.track == .video, packet.packet.isKeyFrame, firstVideoKeyframeTimecode == nil {
            firstVideoKeyframeTimecode = packetTimecode
        }
    }
}

struct WebMCuePoint {
    let timecode: Int64
    let clusterPosition: UInt64
}

enum WebMElementID {
    static let ebml: UInt64 = 0x1A45_DFA3
    static let ebmlVersion: UInt64 = 0x4286
    static let ebmlReadVersion: UInt64 = 0x42F7
    static let ebmlMaxIDLength: UInt64 = 0x42F2
    static let ebmlMaxSizeLength: UInt64 = 0x42F3
    static let docType: UInt64 = 0x4282
    static let docTypeVersion: UInt64 = 0x4287
    static let docTypeReadVersion: UInt64 = 0x4285
    static let segment: UInt64 = 0x1853_8067
    static let seekHead: UInt64 = 0x114D_9B74
    static let seek: UInt64 = 0x4DBB
    static let seekID: UInt64 = 0x53AB
    static let seekPosition: UInt64 = 0x53AC
    static let info: UInt64 = 0x1549_A966
    static let timestampScale: UInt64 = 0x2AD7_B1
    static let duration: UInt64 = 0x4489
    static let muxingApp: UInt64 = 0x4D80
    static let writingApp: UInt64 = 0x5741
    static let tracks: UInt64 = 0x1654_AE6B
    static let trackEntry: UInt64 = 0xAE
    static let trackNumber: UInt64 = 0xD7
    static let trackUID: UInt64 = 0x73C5
    static let trackType: UInt64 = 0x83
    static let codecID: UInt64 = 0x86
    static let codecName: UInt64 = 0x2586_88
    static let codecPrivate: UInt64 = 0x63A2
    static let video: UInt64 = 0xE0
    static let pixelWidth: UInt64 = 0xB0
    static let pixelHeight: UInt64 = 0xBA
    static let colour: UInt64 = 0x55B0
    static let matrixCoefficients: UInt64 = 0x55B1
    static let bitsPerChannel: UInt64 = 0x55B2
    static let chromaSubsamplingHorz: UInt64 = 0x55B3
    static let chromaSubsamplingVert: UInt64 = 0x55B4
    static let range: UInt64 = 0x55B9
    static let transferCharacteristics: UInt64 = 0x55BA
    static let primaries: UInt64 = 0x55BB
    static let audio: UInt64 = 0xE1
    static let samplingFrequency: UInt64 = 0xB5
    static let channels: UInt64 = 0x9F
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

enum EBML {
    static func element(id: UInt64, payload: Data, sizeLength: Int? = nil) -> Data {
        var data = Data()
        data.append(idBytes(id))
        if let sizeLength {
            data.append(fixedSizeVint(UInt64(payload.count), length: sizeLength))
        } else {
            data.append(vint(UInt64(payload.count)))
        }
        data.append(payload)
        return data
    }

    static func unsignedElement(id: UInt64, value: UInt64, byteWidth: Int? = nil) -> Data {
        if let byteWidth {
            return element(id: id, payload: unsignedBytes(value, width: byteWidth))
        }
        return element(id: id, payload: unsignedBytes(value))
    }

    static func stringElement(id: UInt64, value: String) -> Data {
        element(id: id, payload: Data(value.utf8))
    }

    static func floatElement(id: UInt64, value: Double) -> Data {
        var data = Data()
        data.appendUInt64BigEndian(value.bitPattern)
        return element(id: id, payload: data)
    }

    static func binaryElement(id: UInt64, payload: Data) -> Data {
        element(id: id, payload: payload)
    }

    static func voidElement(totalSize: Int) -> Data {
        guard totalSize > 0 else {
            return Data()
        }

        for sizeLength in 1...8 {
            let payloadSize = totalSize - 1 - sizeLength
            guard payloadSize >= 0, UInt64(payloadSize) <= maxVintValue(length: sizeLength) else {
                continue
            }

            var data = Data([0xEC])
            data.append(fixedSizeVint(UInt64(payloadSize), length: sizeLength))
            data.append(Data(repeating: 0, count: payloadSize))
            return data
        }

        preconditionFailure("Cannot encode EBML Void element of \(totalSize) bytes.")
    }

    static func vint(_ value: UInt64) -> Data {
        for length in 1...8 {
            guard value <= maxVintValue(length: length) else {
                continue
            }

            return fixedSizeVint(value, length: length)
        }

        return fixedSizeVint(maxVintValue(length: 8), length: 8)
    }

    static func fixedSizeVint(_ value: UInt64, length: Int) -> Data {
        precondition((1...8).contains(length), "EBML VINT length must be 1...8.")
        precondition(value <= maxVintValue(length: length), "EBML VINT value is too large.")

        var bytes = [UInt8](repeating: 0, count: length)
        var remaining = value
        for index in stride(from: length - 1, through: 0, by: -1) {
            bytes[index] = UInt8(remaining & 0xFF)
            remaining >>= 8
        }
        bytes[0] |= UInt8(1 << (8 - length))
        return Data(bytes)
    }

    static func idBytes(_ id: UInt64) -> Data {
        var bytes: [UInt8] = []
        var started = false
        for shift in stride(from: 56, through: 0, by: -8) {
            let byte = UInt8((id >> UInt64(shift)) & 0xFF)
            if byte != 0 || started {
                bytes.append(byte)
                started = true
            }
        }
        return Data(bytes.isEmpty ? [0] : bytes)
    }

    static func maxVintValue(length: Int) -> UInt64 {
        (UInt64(1) << UInt64(7 * length)) - 2
    }

    static func unsignedBytes(_ value: UInt64) -> Data {
        var bytes: [UInt8] = []
        var started = false
        for shift in stride(from: 56, through: 0, by: -8) {
            let byte = UInt8((value >> UInt64(shift)) & 0xFF)
            if byte != 0 || started {
                bytes.append(byte)
                started = true
            }
        }
        return Data(bytes.isEmpty ? [0] : bytes)
    }

    static func unsignedBytes(_ value: UInt64, width: Int) -> Data {
        precondition((1...8).contains(width), "EBML unsigned integer width must be 1...8.")

        var data = Data()
        for shift in stride(from: (width - 1) * 8, through: 0, by: -8) {
            data.append(UInt8((value >> UInt64(shift)) & 0xFF))
        }
        return data
    }
}

extension Data {
    mutating func append(_ byte: UInt8) {
        append(contentsOf: [byte])
    }

    mutating func appendLittleEndian(_ value: UInt16) {
        append(UInt8(value & 0x00FF))
        append(UInt8((value >> 8) & 0x00FF))
    }

    mutating func appendLittleEndian(_ value: UInt32) {
        append(UInt8(value & 0x0000_00FF))
        append(UInt8((value >> 8) & 0x0000_00FF))
        append(UInt8((value >> 16) & 0x0000_00FF))
        append(UInt8((value >> 24) & 0x0000_00FF))
    }

    mutating func appendUInt16BigEndian(_ value: UInt16) {
        append(UInt8((value >> 8) & 0x00FF))
        append(UInt8(value & 0x00FF))
    }

    mutating func appendUInt64BigEndian(_ value: UInt64) {
        for shift in stride(from: 56, through: 0, by: -8) {
            append(UInt8((value >> UInt64(shift)) & 0xFF))
        }
    }
}
