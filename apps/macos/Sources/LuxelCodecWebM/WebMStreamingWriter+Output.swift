import Foundation

extension WebMStreamingWriter {
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
        let packetEndTimecode = Int64(
            ((packet.packet.presentationTime + packet.packet.duration) * 1_000).rounded(.up))
        maxEndTimecode = max(maxEndTimecode, packetEndTimecode)

        if var cluster = currentCluster {
            let relativeTimecode = packetTimecode - cluster.timecode
            if relativeTimecode >= Self.clusterDurationLimit
                || cluster.blocks.count + simpleBlockPayloadSize(packet: packet) > Self.clusterPayloadLimit
            {
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

    func startCluster(timecode: Int64, packet: WebMPacket) throws {
        let block = try simpleBlock(packet: packet, clusterTimecode: timecode)
        var cluster = WebMCluster(timecode: timecode)
        try cluster.append(block: block, packet: packet, packetTimecode: timecode)
        currentCluster = cluster
    }

    func flushCurrentCluster() throws {
        guard let cluster = currentCluster else {
            return
        }

        let clusterPosition = currentSegmentPosition
        var payload = Data()
        payload.append(
            EBML.unsignedElement(id: WebMElementID.clusterTimecode, value: UInt64(cluster.timecode)))
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

    func writeDuration() throws {
        guard maxEndTimecode > 0 else {
            return
        }

        var duration = Data()
        duration.appendUInt64BigEndian(Double(maxEndTimecode).bitPattern)
        try write(duration, at: durationPayloadOffset)
    }

    func writeSegmentSize(_ size: UInt64) throws {
        try write(EBML.fixedSizeVint(size, length: 8), at: segmentSizeOffset)
    }

    func writeSeekHead() throws {
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

        let payloadCapacity =
            Self.seekHeadReservationSize - EBML.idBytes(WebMElementID.seekHead).count - 8
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

    func write(_ data: Data) throws {
        guard let fileHandle else {
            throw WebMCodecError.muxerFailure("WebM output file is not open.")
        }

        try fileHandle.write(contentsOf: data)
        fileOffset += UInt64(data.count)
    }

    func write(_ data: Data, at offset: UInt64) throws {
        guard let fileHandle else {
            throw WebMCodecError.muxerFailure("WebM output file is not open.")
        }

        try fileHandle.seek(toOffset: offset)
        try fileHandle.write(contentsOf: data)
        try fileHandle.seek(toOffset: fileOffset)
    }

    func close() throws {
        try fileHandle?.close()
        fileHandle = nil
    }
}
