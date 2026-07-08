import Foundation
import LuxelCore

public enum AV1CodecError: Error, Equatable, LocalizedError {
    case unsupportedFormat(ExportFormat)
    case invalidConfiguration(String)
    case encoderFailure(String)
    case muxerFailure(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let format):
            "AV1 export does not support \(format.prettyName)."
        case .invalidConfiguration(let message),
             .encoderFailure(let message),
             .muxerFailure(let message):
            message
        }
    }
}

extension String {
    static func av1CodecErrorMessage(from buffer: [CChar]) -> String {
        let endIndex = buffer.firstIndex(of: 0) ?? buffer.endIndex
        let message = String(decoding: buffer[..<endIndex].map(UInt8.init(bitPattern:)), as: UTF8.self)
        return message.isEmpty ? "Unknown AV1 codec error." : message
    }
}
