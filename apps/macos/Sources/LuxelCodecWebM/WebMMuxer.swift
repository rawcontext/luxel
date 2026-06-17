import Foundation
import LuxelCore

public actor WebMMuxer: CodecContainerMuxer {
    private let fileSystem: FileManager
    private var writer: WebMStreamingWriter?
    private var tracks: Set<CodecTrack> = []

    public init(fileSystem: FileManager = .default) {
        self.fileSystem = fileSystem
    }

    public func begin(_ configuration: CodecMuxerConfiguration) async throws {
        guard configuration.format == .webm else {
            throw WebMCodecError.unsupportedFormat(configuration.format)
        }
        guard configuration.tracks.contains(.video) else {
            throw WebMCodecError.muxerFailure("WebM export requires a video track.")
        }
        guard let pixelSize = configuration.pixelSize else {
            throw WebMCodecError.muxerFailure("WebM muxer requires output pixel size metadata.")
        }

        tracks = Set(configuration.tracks)
        let writer = WebMStreamingWriter(
            outputFileURL: configuration.outputFileURL,
            pixelSize: pixelSize,
            hasAudio: tracks.contains(.audio),
            fileSystem: fileSystem
        )
        try writer.begin()
        self.writer = writer
    }

    public func write(_ packet: EncodedPacket, to track: CodecTrack) async throws {
        guard let writer else {
            throw WebMCodecError.muxerFailure("WebM muxer was used before begin.")
        }
        guard tracks.contains(track) else {
            throw WebMCodecError.muxerFailure("WebM muxer received an undeclared \(track.rawValue) packet.")
        }

        try writer.append(WebMPacket(track: track, packet: packet))
    }

    public func finalize() async throws {
        guard let writer else {
            throw WebMCodecError.muxerFailure("WebM muxer was finalized before begin.")
        }

        try writer.finalize()
        reset()
    }

    public func cancel() async {
        writer?.cancel()
        reset()
    }

    private func reset() {
        writer = nil
        tracks.removeAll(keepingCapacity: true)
    }
}

private struct WebMPacket {
    let track: CodecTrack
    let packet: EncodedPacket

    var trackNumber: UInt64 {
        switch track {
        case .video:
            1
        case .audio:
            2
        }
    }
}

private final class WebMStreamingWriter {
    private static let timestampScale: UInt64 = 1_000_000
    private static let seekHeadReservationSize = 512
    private static let clusterDurationLimit: Int64 = 2_000
    private static let clusterPayloadLimit = 1_000_000

    private let outputFileURL: URL
    private let pixelSize: PixelSize
    private let hasAudio: Bool
    private let fileSystem: FileManager

    private var fileHandle: FileHandle?
    private var fileOffset: UInt64 = 0
    private var segmentSizeOffset: UInt64 = 0
    private var segmentDataStartOffset: UInt64 = 0
    private var infoPosition: UInt64 = 0
    private var tracksPosition: UInt64 = 0
    private var firstClusterPosition: UInt64?
    private var cuesPosition: UInt64?
    private var durationPayloadOffset: UInt64 = 0
    private var maxEndTimecode: Int64 = 0
    private var currentCluster: WebMCluster?
    private var cuePoints: [WebMCuePoint] = []

    init(
        outputFileURL: URL,
        pixelSize: PixelSize,
        hasAudio: Bool,
        fileSystem: FileManager
    ) {
        self.outputFileURL = outputFileURL
        self.pixelSize = pixelSize
        self.hasAudio = hasAudio
        self.fileSystem = fileSystem
    }

    func begin() throws {
        let directory = outputFileURL.deletingLastPathComponent()
        try fileSystem.createDirectory(at: directory, withIntermediateDirectories: true)
        if fileSystem.fileExists(atPath: outputFileURL.path) {
            try fileSystem.removeItem(at: outputFileURL)
        }
        guard fileSystem.createFile(atPath: outputFileURL.path, contents: nil) else {
            throw WebMCodecError.muxerFailure("Could not create WebM output file.")
        }

        fileHandle = try FileHandle(forWritingTo: outputFileURL)

        try write(ebmlHeader())
        try write(EBML.idBytes(WebMElementID.segment))
        segmentSizeOffset = fileOffset
        try write(EBML.fixedSizeVint(0, length: 8))
        segmentDataStartOffset = fileOffset

        try write(EBML.voidElement(totalSize: Self.seekHeadReservationSize))

        infoPosition = currentSegmentPosition
        let info = infoElement(durationMilliseconds: 0)
        durationPayloadOffset = fileOffset + UInt64(info.durationPayloadOffset)
        try write(info.data)

        tracksPosition = currentSegmentPosition
        try write(tracksElement())
    }

    func append(_ packet: WebMPacket) throws {
        let packetTimecode = Int64((packet.packet.presentationTime * 1_000).rounded())
        let packetEndTimecode = Int64(((packet.packet.presentationTime + packet.packet.duration) * 1_000).rounded(.up))
        maxEndTimecode = max(maxEndTimecode, packetEndTimecode)

        if var cluster = currentCluster {
            let relativeTimecode = packetTimecode - cluster.timecode
            if relativeTimecode >= Self.clusterDurationLimit ||
                cluster.blocks.count + simpleBlockPayloadSize(packet: packet) > Self.clusterPayloadLimit {
                try flushCurrentCluster()
                try startCluster(timecode: packetTimecode, packet: packet)
                return
            }

            let block = try simpleBlock(packet: packet, clusterTimecode: cluster.timecode)
            try cluster.append(block: block, packet: packet, packetTimecode: packetTimecode)
            currentCluster = cluster
        } else {
            try startCluster(timecode: packetTimecode, packet: packet)
        }
    }

    func finalize() throws {
        try flushCurrentCluster()

        if !cuePoints.isEmpty {
            cuesPosition = currentSegmentPosition
            try write(cuesElement())
        }

        let finalOffset = fileOffset
        try writeDuration()
        try writeSegmentSize(finalOffset - segmentDataStartOffset)
        try writeSeekHead()
        try close()
    }

    func cancel() {
        try? close()
        try? fileSystem.removeItem(at: outputFileURL)
    }

    private func startCluster(timecode: Int64, packet: WebMPacket) throws {
        let block = try simpleBlock(packet: packet, clusterTimecode: timecode)
        var cluster = WebMCluster(timecode: timecode)
        try cluster.append(block: block, packet: packet, packetTimecode: timecode)
        currentCluster = cluster
    }

    private func flushCurrentCluster() throws {
        guard let cluster = currentCluster else {
            return
        }

        let clusterPosition = currentSegmentPosition
        var payload = Data()
        payload.append(EBML.unsignedElement(id: WebMElementID.clusterTimecode, value: UInt64(cluster.timecode)))
        payload.append(cluster.blocks)
        try write(EBML.element(id: WebMElementID.cluster, payload: payload))

        if firstClusterPosition == nil {
            firstClusterPosition = clusterPosition
        }
        if let cueTimecode = cluster.firstVideoKeyframeTimecode {
            cuePoints.append(WebMCuePoint(timecode: cueTimecode, clusterPosition: clusterPosition))
        }
        currentCluster = nil
    }

    private func writeDuration() throws {
        guard maxEndTimecode > 0 else {
            return
        }

        var duration = Data()
        duration.appendUInt64BigEndian(Double(maxEndTimecode).bitPattern)
        try write(duration, at: durationPayloadOffset)
    }

    private func writeSegmentSize(_ size: UInt64) throws {
        try write(EBML.fixedSizeVint(size, length: 8), at: segmentSizeOffset)
    }

    private func writeSeekHead() throws {
        var entries: [(id: UInt64, position: UInt64)] = [
            (WebMElementID.info, infoPosition),
            (WebMElementID.tracks, tracksPosition)
        ]
        if let firstClusterPosition {
            entries.append((WebMElementID.cluster, firstClusterPosition))
        }
        if let cuesPosition {
            entries.append((WebMElementID.cues, cuesPosition))
        }

        var payload = Data()
        for entry in entries {
            payload.append(seekEntry(targetID: entry.id, position: entry.position))
        }

        let payloadCapacity = Self.seekHeadReservationSize - EBML.idBytes(WebMElementID.seekHead).count - 8
        guard payload.count <= payloadCapacity else {
            throw WebMCodecError.muxerFailure("Reserved WebM SeekHead space was too small.")
        }
        payload.append(EBML.voidElement(totalSize: payloadCapacity - payload.count))

        let seekHead = EBML.element(id: WebMElementID.seekHead, payload: payload, sizeLength: 8)
        guard seekHead.count == Self.seekHeadReservationSize else {
            throw WebMCodecError.muxerFailure("WebM SeekHead backpatch size changed unexpectedly.")
        }
        try write(seekHead, at: segmentDataStartOffset)
    }

    private func write(_ data: Data) throws {
        guard let fileHandle else {
            throw WebMCodecError.muxerFailure("WebM output file is not open.")
        }

        try fileHandle.write(contentsOf: data)
        fileOffset += UInt64(data.count)
    }

    private func write(_ data: Data, at offset: UInt64) throws {
        guard let fileHandle else {
            throw WebMCodecError.muxerFailure("WebM output file is not open.")
        }

        try fileHandle.seek(toOffset: offset)
        try fileHandle.write(contentsOf: data)
        try fileHandle.seek(toOffset: fileOffset)
    }

    private func close() throws {
        try fileHandle?.close()
        fileHandle = nil
    }

    private var currentSegmentPosition: UInt64 {
        fileOffset - segmentDataStartOffset
    }

    private func ebmlHeader() -> Data {
        var payload = Data()
        payload.append(EBML.unsignedElement(id: WebMElementID.ebmlVersion, value: 1))
        payload.append(EBML.unsignedElement(id: WebMElementID.ebmlReadVersion, value: 1))
        payload.append(EBML.unsignedElement(id: WebMElementID.ebmlMaxIDLength, value: 4))
        payload.append(EBML.unsignedElement(id: WebMElementID.ebmlMaxSizeLength, value: 8))
        payload.append(EBML.stringElement(id: WebMElementID.docType, value: "webm"))
        payload.append(EBML.unsignedElement(id: WebMElementID.docTypeVersion, value: 4))
        payload.append(EBML.unsignedElement(id: WebMElementID.docTypeReadVersion, value: 2))
        return EBML.element(id: WebMElementID.ebml, payload: payload)
    }

    private func infoElement(durationMilliseconds: Double) -> (data: Data, durationPayloadOffset: Int) {
        var payload = Data()
        payload.append(EBML.unsignedElement(id: WebMElementID.timestampScale, value: Self.timestampScale))
        payload.append(EBML.stringElement(id: WebMElementID.muxingApp, value: "Luxel"))
        payload.append(EBML.stringElement(id: WebMElementID.writingApp, value: "Luxel"))
        let durationPayloadOffset = payload.count +
            EBML.idBytes(WebMElementID.duration).count +
            EBML.fixedSizeVint(8, length: 1).count
        payload.append(EBML.floatElement(id: WebMElementID.duration, value: durationMilliseconds))

        let header = EBML.idBytes(WebMElementID.info) + EBML.vint(UInt64(payload.count))
        var data = Data()
        data.append(header)
        data.append(payload)
        return (data, header.count + durationPayloadOffset)
    }

    private func tracksElement() -> Data {
        var payload = Data()
        payload.append(videoTrackElement())
        if hasAudio {
            payload.append(audioTrackElement())
        }
        return EBML.element(id: WebMElementID.tracks, payload: payload)
    }

    private func videoTrackElement() -> Data {
        var colour = Data()
        colour.append(EBML.unsignedElement(id: WebMElementID.matrixCoefficients, value: 1))
        colour.append(EBML.unsignedElement(id: WebMElementID.bitsPerChannel, value: 8))
        colour.append(EBML.unsignedElement(id: WebMElementID.chromaSubsamplingHorz, value: 1))
        colour.append(EBML.unsignedElement(id: WebMElementID.chromaSubsamplingVert, value: 1))
        colour.append(EBML.unsignedElement(id: WebMElementID.range, value: 1))
        colour.append(EBML.unsignedElement(id: WebMElementID.transferCharacteristics, value: 1))
        colour.append(EBML.unsignedElement(id: WebMElementID.primaries, value: 1))

        var video = Data()
        video.append(EBML.unsignedElement(id: WebMElementID.pixelWidth, value: UInt64(pixelSize.width)))
        video.append(EBML.unsignedElement(id: WebMElementID.pixelHeight, value: UInt64(pixelSize.height)))
        video.append(EBML.element(id: WebMElementID.colour, payload: colour))

        var payload = Data()
        payload.append(EBML.unsignedElement(id: WebMElementID.trackNumber, value: 1))
        payload.append(EBML.unsignedElement(id: WebMElementID.trackUID, value: 1))
        payload.append(EBML.unsignedElement(id: WebMElementID.trackType, value: 1))
        payload.append(EBML.stringElement(id: WebMElementID.codecID, value: "V_VP9"))
        payload.append(EBML.stringElement(id: WebMElementID.codecName, value: "VP9"))
        payload.append(EBML.element(id: WebMElementID.video, payload: video))
        return EBML.element(id: WebMElementID.trackEntry, payload: payload)
    }

    private func audioTrackElement() -> Data {
        var audio = Data()
        audio.append(EBML.floatElement(id: WebMElementID.samplingFrequency, value: 48_000))
        audio.append(EBML.unsignedElement(id: WebMElementID.channels, value: 2))

        var payload = Data()
        payload.append(EBML.unsignedElement(id: WebMElementID.trackNumber, value: 2))
        payload.append(EBML.unsignedElement(id: WebMElementID.trackUID, value: 2))
        payload.append(EBML.unsignedElement(id: WebMElementID.trackType, value: 2))
        payload.append(EBML.stringElement(id: WebMElementID.codecID, value: "A_OPUS"))
        payload.append(EBML.stringElement(id: WebMElementID.codecName, value: "Opus"))
        payload.append(EBML.binaryElement(id: WebMElementID.codecPrivate, payload: opusHead))
        payload.append(EBML.element(id: WebMElementID.audio, payload: audio))
        return EBML.element(id: WebMElementID.trackEntry, payload: payload)
    }

    private var opusHead: Data {
        var data = Data("OpusHead".utf8)
        data.append(1)
        data.append(2)
        data.appendLittleEndian(UInt16(312))
        data.appendLittleEndian(UInt32(48_000))
        data.appendLittleEndian(UInt16(0))
        data.append(0)
        return data
    }

    private func simpleBlock(packet: WebMPacket, clusterTimecode: Int64) throws -> Data {
        let packetTimecode = Int64((packet.packet.presentationTime * 1_000).rounded())
        let relativeTimecode = packetTimecode - clusterTimecode
        guard relativeTimecode >= Int64(Int16.min), relativeTimecode <= Int64(Int16.max) else {
            throw WebMCodecError.muxerFailure("WebM packet was too far from its cluster timecode.")
        }

        var block = Data()
        block.append(EBML.vint(packet.trackNumber))
        block.appendUInt16BigEndian(UInt16(bitPattern: Int16(relativeTimecode)))
        block.append(simpleBlockFlags(packet))
        block.append(packet.packet.data)
        return EBML.binaryElement(id: WebMElementID.simpleBlock, payload: block)
    }

    private func simpleBlockPayloadSize(packet: WebMPacket) -> Int {
        EBML.vint(packet.trackNumber).count + 3 + packet.packet.data.count
    }

    private func simpleBlockFlags(_ packet: WebMPacket) -> UInt8 {
        switch packet.track {
        case .video:
            packet.packet.isKeyFrame ? 0x80 : 0x00
        case .audio:
            0x80
        }
    }

    private func cuesElement() -> Data {
        var payload = Data()
        for cuePoint in cuePoints {
            var trackPositions = Data()
            trackPositions.append(EBML.unsignedElement(id: WebMElementID.cueTrack, value: 1))
            trackPositions.append(EBML.unsignedElement(id: WebMElementID.cueClusterPosition, value: cuePoint.clusterPosition))

            var cue = Data()
            cue.append(EBML.unsignedElement(id: WebMElementID.cueTime, value: UInt64(cuePoint.timecode)))
            cue.append(EBML.element(id: WebMElementID.cueTrackPositions, payload: trackPositions))
            payload.append(EBML.element(id: WebMElementID.cuePoint, payload: cue))
        }
        return EBML.element(id: WebMElementID.cues, payload: payload)
    }

    private func seekEntry(targetID: UInt64, position: UInt64) -> Data {
        var payload = Data()
        payload.append(EBML.binaryElement(id: WebMElementID.seekID, payload: EBML.idBytes(targetID)))
        payload.append(EBML.unsignedElement(id: WebMElementID.seekPosition, value: position, byteWidth: 8))
        return EBML.element(id: WebMElementID.seek, payload: payload)
    }
}

private struct WebMCluster {
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

private struct WebMCuePoint {
    let timecode: Int64
    let clusterPosition: UInt64
}

private enum WebMElementID {
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

private enum EBML {
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

    private static func maxVintValue(length: Int) -> UInt64 {
        (UInt64(1) << UInt64(7 * length)) - 2
    }

    private static func unsignedBytes(_ value: UInt64) -> Data {
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

    private static func unsignedBytes(_ value: UInt64, width: Int) -> Data {
        precondition((1...8).contains(width), "EBML unsigned integer width must be 1...8.")

        var data = Data()
        for shift in stride(from: (width - 1) * 8, through: 0, by: -8) {
            data.append(UInt8((value >> UInt64(shift)) & 0xFF))
        }
        return data
    }
}

private extension Data {
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
