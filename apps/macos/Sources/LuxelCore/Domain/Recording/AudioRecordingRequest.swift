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
    public let captureKeystrokes: Bool

    public init(
        outputFileURL: URL,
        audio: RecordingAudioMode,
        format: AudioRecordingFormat = .aac,
        captureKeystrokes: Bool = false
    ) throws {
        guard audio != .none else {
            throw AudioRecordingRequestError.missingAudioSource
        }

        self.outputFileURL = outputFileURL
        self.audio = audio
        self.format = format
        self.captureKeystrokes = captureKeystrokes
    }

    public var recordingOptions: RecordingOptions {
        RecordingOptions(
            frameRate: 0,
            captureKeystrokes: captureKeystrokes,
            audio: audio,
            isAudioOnly: true
        )
    }

    public func replacingOutputFileURL(_ outputFileURL: URL) throws -> AudioRecordingRequest {
        try AudioRecordingRequest(
            outputFileURL: outputFileURL,
            audio: audio,
            format: format,
            captureKeystrokes: captureKeystrokes
        )
    }

    private enum CodingKeys: String, CodingKey {
        case outputFileURL
        case audio
        case format
        case captureKeystrokes
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            outputFileURL: container.decode(URL.self, forKey: .outputFileURL),
            audio: container.decode(RecordingAudioMode.self, forKey: .audio),
            format: container.decodeIfPresent(AudioRecordingFormat.self, forKey: .format) ?? .aac,
            captureKeystrokes: container.decodeIfPresent(
                Bool.self,
                forKey: .captureKeystrokes
            ) ?? false
        )
    }
}

public enum AudioRecordingRequestError: Error, Equatable {
    case missingAudioSource
}
