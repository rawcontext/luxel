import CWebMCodecShims

func mapCodecPackets<Result>(
    _ packetList: LuxelCodecPacketList,
    transform: (LuxelCodecPacket) throws -> Result
) rethrows -> [Result] {
    guard let packets = packetList.packets else {
        return []
    }
    return try (0..<packetList.count).map { index in
        try transform(packets[index])
    }
}
