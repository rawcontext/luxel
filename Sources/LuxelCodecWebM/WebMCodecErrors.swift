import Foundation
import LuxelCore

public enum WebMCodecError: Error, Equatable {
    case unsupportedFormat(ExportFormat)
    case invalidConfiguration(String)
    case encoderFailure(String)
    case muxerFailure(String)
}

extension String {
    static func codecErrorMessage(from buffer: [CChar]) -> String {
        let endIndex = buffer.firstIndex(of: 0) ?? buffer.endIndex
        let message = String(decoding: buffer[..<endIndex].map(UInt8.init(bitPattern:)), as: UTF8.self)
        return message.isEmpty ? "Unknown codec error." : message
    }
}
