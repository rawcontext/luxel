import Foundation

enum DeepFilterNetNPZReader {
    static func load(from url: URL) throws -> DeepFilterNetAuxiliaryData {
        let arrays = try read(url: url)
        guard let erbFilterbank = arrays["erb_fb"],
              let inverseERBFilterbank = arrays["erb_inv_fb"],
              let window = arrays["window"],
              let meanNormalizationState = arrays["mean_norm_state"],
              let unitNormalizationState = arrays["unit_norm_state"],
              erbFilterbank.count == 481 * 32,
              inverseERBFilterbank.count == 32 * 481,
              window.count == 960,
              meanNormalizationState.count == 32,
              unitNormalizationState.count == 96
        else {
            throw StudioVoiceModelError.invalidAuxiliaryData
        }

        return DeepFilterNetAuxiliaryData(
            erbFilterbank: erbFilterbank,
            inverseERBFilterbank: inverseERBFilterbank,
            window: window,
            meanNormalizationState: meanNormalizationState,
            unitNormalizationState: unitNormalizationState
        )
    }

    private static func read(url: URL) throws -> [String: [Float]] {
        let data = try Data(contentsOf: url)
        var result: [String: [Float]] = [:]
        var offset = 0

        while offset + 30 <= data.count {
            guard data[offset] == 0x50,
                  data[offset + 1] == 0x4b,
                  data[offset + 2] == 0x03,
                  data[offset + 3] == 0x04
            else {
                break
            }

            let nameLength = Int(readUInt16(data, at: offset + 26))
            let extraLength = Int(readUInt16(data, at: offset + 28))
            let nameStart = offset + 30
            guard nameStart + nameLength <= data.count else {
                throw StudioVoiceModelError.invalidAuxiliaryData
            }

            var name = String(
                data: data.subdata(in: nameStart..<(nameStart + nameLength)),
                encoding: .utf8
            ) ?? ""
            if name.hasSuffix(".npy") {
                name.removeLast(4)
            }

            let sizes = try resolvedSizes(
                data: data,
                compressedSize: Int(readUInt32(data, at: offset + 18)),
                uncompressedSize: Int(readUInt32(data, at: offset + 22)),
                extraStart: nameStart + nameLength,
                extraLength: extraLength
            )

            guard sizes.compressed == sizes.uncompressed else {
                throw StudioVoiceModelError.invalidAuxiliaryData
            }
            let payloadStart = nameStart + nameLength + extraLength
            guard payloadStart + sizes.uncompressed <= data.count,
                  let floats = parseNPY(
                    data,
                    offset: payloadStart,
                    byteCount: sizes.uncompressed
                  )
            else {
                throw StudioVoiceModelError.invalidAuxiliaryData
            }

            result[name] = floats
            offset = payloadStart + sizes.compressed
        }

        return result
    }

    private static func resolvedSizes(
        data: Data,
        compressedSize: Int,
        uncompressedSize: Int,
        extraStart: Int,
        extraLength: Int
    ) throws -> (compressed: Int, uncompressed: Int) {
        guard compressedSize == 0xffff_ffff || uncompressedSize == 0xffff_ffff else {
            return (compressedSize, uncompressedSize)
        }
        guard extraLength >= 4, readUInt16(data, at: extraStart) == 0x0001 else {
            throw StudioVoiceModelError.invalidAuxiliaryData
        }
        var resolvedCompressedSize = compressedSize
        var resolvedUncompressedSize = uncompressedSize
        var extraOffset = extraStart + 4
        if uncompressedSize == 0xffff_ffff {
            resolvedUncompressedSize = Int(readUInt64(data, at: extraOffset))
            extraOffset += 8
        }
        if compressedSize == 0xffff_ffff {
            resolvedCompressedSize = Int(readUInt64(data, at: extraOffset))
        }
        return (resolvedCompressedSize, resolvedUncompressedSize)
    }

    private static func parseNPY(
        _ data: Data,
        offset: Int,
        byteCount: Int
    ) -> [Float]? {
        guard byteCount >= 10,
              data[offset] == 0x93,
              data[offset + 1] == 0x4e
        else {
            return nil
        }

        let majorVersion = data[offset + 6]
        let headerLength = majorVersion == 1
            ? Int(readUInt16(data, at: offset + 8))
            : Int(readUInt32(data, at: offset + 8))
        let headerSize = majorVersion == 1 ? 10 : 12
        let floatStart = offset + headerSize + headerLength
        let floatByteCount = byteCount - headerSize - headerLength
        guard floatByteCount >= 0, floatByteCount.isMultiple(of: 4) else {
            return nil
        }

        var floats = [Float](repeating: 0, count: floatByteCount / 4)
        _ = floats.withUnsafeMutableBytes { destination in
            data.copyBytes(
                to: destination,
                from: floatStart..<(floatStart + floatByteCount)
            )
        }
        return floats
    }

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self) }
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
    }

    private static func readUInt64(_ data: Data, at offset: Int) -> UInt64 {
        data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self) }
    }
}
