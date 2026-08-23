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
        guard let payload = npyPayload(data, offset: offset, byteCount: byteCount) else {
            return nil
        }

        var raw = [Float](
            repeating: 0,
            count: payload.byteCount / MemoryLayout<Float>.size
        )
        _ = raw.withUnsafeMutableBytes { destination in
            data.copyBytes(
                to: destination,
                from: payload.start..<(payload.start + payload.byteCount)
            )
        }

        let fortranOrder = payload.header.contains("'fortran_order': True")
            || payload.header.contains("\"fortran_order\": True")
        guard fortranOrder else {
            return raw
        }
        guard let shape = parseShape(fromNPYHeader: payload.header),
              shape.count > 1,
              elementCount(of: shape, limit: raw.count) == raw.count
        else {
            return nil
        }

        return fortranToRowMajor(raw, shape: shape)
    }

    private static func npyPayload(
        _ data: Data,
        offset: Int,
        byteCount: Int
    ) -> DeepFilterNetNPYPayload? {
        guard offset >= 0,
              byteCount >= 10,
              offset + byteCount <= data.count,
              data[offset] == 0x93,
              data[offset + 1] == 0x4e
        else {
            return nil
        }

        let majorVersion = data[offset + 6]
        let headerLength: Int
        switch majorVersion {
        case 1:
            headerLength = Int(readUInt16(data, at: offset + 8))
        case 2, 3:
            guard byteCount >= 12 else {
                return nil
            }
            headerLength = Int(readUInt32(data, at: offset + 8))
        default:
            return nil
        }

        let headerSize = majorVersion == 1 ? 10 : 12
        let headerStart = offset + headerSize
        let floatStart = headerStart + headerLength
        let floatByteCount = byteCount - headerSize - headerLength
        guard headerLength > 0,
              floatStart <= offset + byteCount,
              floatByteCount > 0,
              floatByteCount.isMultiple(of: MemoryLayout<Float>.size),
              floatStart + floatByteCount <= data.count,
              let header = String(
                data: data[headerStart..<floatStart],
                encoding: .ascii
              )
        else {
            return nil
        }
        return DeepFilterNetNPYPayload(
            header: header,
            start: floatStart,
            byteCount: floatByteCount
        )
    }

    private static func elementCount(of shape: [Int], limit: Int) -> Int? {
        var count = 1
        for dimension in shape {
            guard dimension > 0, count <= limit / dimension else {
                return nil
            }
            count *= dimension
        }
        return count
    }

    private static func parseShape(fromNPYHeader header: String) -> [Int]? {
        guard let shapeKey = header.range(of: "shape"),
              let open = header[shapeKey.upperBound...].firstIndex(of: "("),
              let close = header[open...].firstIndex(of: ")")
        else {
            return nil
        }

        let contents = header[header.index(after: open)..<close]
        var dimensions: [Int] = []
        for part in contents.split(separator: ",") {
            let value = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let dimension = Int(value) else {
                return nil
            }
            dimensions.append(dimension)
        }
        return dimensions.isEmpty ? nil : dimensions
    }

    /// NumPy stores Fortran-order arrays column-major; Luxel's DSP expects row-major arrays.
    private static func fortranToRowMajor(_ input: [Float], shape: [Int]) -> [Float] {
        var rowMajorStrides = [Int](repeating: 1, count: shape.count)
        if shape.count > 1 {
            for dimension in stride(from: shape.count - 2, through: 0, by: -1) {
                rowMajorStrides[dimension] = rowMajorStrides[dimension + 1]
                    * shape[dimension + 1]
            }
        }

        var output = [Float](repeating: 0, count: input.count)
        for rowMajorIndex in output.indices {
            var remainder = rowMajorIndex
            var fortranIndex = 0
            var fortranStride = 1
            for dimension in shape.indices {
                let coordinate = remainder / rowMajorStrides[dimension]
                remainder %= rowMajorStrides[dimension]
                fortranIndex += coordinate * fortranStride
                fortranStride *= shape[dimension]
            }
            output[rowMajorIndex] = input[fortranIndex]
        }
        return output
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

private struct DeepFilterNetNPYPayload {
    let header: String
    let start: Int
    let byteCount: Int
}
