import Foundation

public enum AudioRecordingFormat: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case aac
    case alac

    public var fileExtension: String {
        "m4a"
    }

    public var label: String {
        switch self {
        case .aac:
            "AAC"
        case .alac:
            "ALAC"
        }
    }
}

public struct AudioRecordingRequest: Codable, Equatable, Sendable {
    public let outputFileURL: URL
    public let audio: RecordingAudioMode
    public let format: AudioRecordingFormat

    public init(
        outputFileURL: URL,
        audio: RecordingAudioMode,
        format: AudioRecordingFormat = .aac
    ) throws {
        guard audio != .none else {
            throw AudioRecordingRequestError.missingAudioSource
        }

        self.outputFileURL = outputFileURL
        self.audio = audio
        self.format = format
    }

    public var recordingOptions: RecordingOptions {
        RecordingOptions(
            frameRate: 0,
            audio: audio,
            isAudioOnly: true
        )
    }

    public func replacingOutputFileURL(_ outputFileURL: URL) throws -> AudioRecordingRequest {
        try AudioRecordingRequest(
            outputFileURL: outputFileURL,
            audio: audio,
            format: format
        )
    }
}

public enum AudioRecordingRequestError: Error, Equatable {
    case missingAudioSource
}
