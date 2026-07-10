import Foundation

extension WebMStreamingWriter {
    var currentSegmentPosition: UInt64 {
        fileOffset - segmentDataStartOffset
    }

    func ebmlHeader() -> Data {
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

    func infoElement(durationMilliseconds: Double) -> (data: Data, durationPayloadOffset: Int) {
        var payload = Data()
        payload.append(
            EBML.unsignedElement(id: WebMElementID.timestampScale, value: Self.timestampScale))
        payload.append(EBML.stringElement(id: WebMElementID.muxingApp, value: "Luxel"))
        payload.append(EBML.stringElement(id: WebMElementID.writingApp, value: "Luxel"))
        let durationPayloadOffset =
            payload.count + EBML.idBytes(WebMElementID.duration).count
            + EBML.fixedSizeVint(8, length: 1).count
        payload.append(EBML.floatElement(id: WebMElementID.duration, value: durationMilliseconds))

        let header = EBML.idBytes(WebMElementID.info) + EBML.vint(UInt64(payload.count))
        var data = Data()
        data.append(header)
        data.append(payload)
        return (data, header.count + durationPayloadOffset)
    }

    func tracksElement() -> Data {
        var payload = Data()
        payload.append(videoTrackElement())
        if hasAudio {
            payload.append(audioTrackElement())
        }
        return EBML.element(id: WebMElementID.tracks, payload: payload)
    }

    func videoTrackElement() -> Data {
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
        video.append(
            EBML.unsignedElement(id: WebMElementID.pixelHeight, value: UInt64(pixelSize.height)))
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

    func audioTrackElement() -> Data {
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

    var opusHead: Data {
        var data = Data("OpusHead".utf8)
        data.append(1)
        data.append(2)
        data.appendLittleEndian(UInt16(312))
        data.appendLittleEndian(UInt32(48_000))
        data.appendLittleEndian(UInt16(0))
        data.append(0)
        return data
    }

    func simpleBlock(packet: WebMPacket, clusterTimecode: Int64) throws -> Data {
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

    func simpleBlockPayloadSize(packet: WebMPacket) -> Int {
        EBML.vint(packet.trackNumber).count + 3 + packet.packet.data.count
    }

    func simpleBlockFlags(_ packet: WebMPacket) -> UInt8 {
        switch packet.track {
        case .video:
            packet.packet.isKeyFrame ? 0x80 : 0x00
        case .audio:
            0x80
        }
    }

    func cuesElement() -> Data {
        var payload = Data()
        for cuePoint in cuePoints {
            var trackPositions = Data()
            trackPositions.append(EBML.unsignedElement(id: WebMElementID.cueTrack, value: 1))
            trackPositions.append(
                EBML.unsignedElement(id: WebMElementID.cueClusterPosition, value: cuePoint.clusterPosition))

            var cue = Data()
            cue.append(EBML.unsignedElement(id: WebMElementID.cueTime, value: UInt64(cuePoint.timecode)))
            cue.append(EBML.element(id: WebMElementID.cueTrackPositions, payload: trackPositions))
            payload.append(EBML.element(id: WebMElementID.cuePoint, payload: cue))
        }
        return EBML.element(id: WebMElementID.cues, payload: payload)
    }

    func seekEntry(targetID: UInt64, position: UInt64) -> Data {
        var payload = Data()
        payload.append(EBML.binaryElement(id: WebMElementID.seekID, payload: EBML.idBytes(targetID)))
        payload.append(
            EBML.unsignedElement(id: WebMElementID.seekPosition, value: position, byteWidth: 8))
        return EBML.element(id: WebMElementID.seek, payload: payload)
    }
}
