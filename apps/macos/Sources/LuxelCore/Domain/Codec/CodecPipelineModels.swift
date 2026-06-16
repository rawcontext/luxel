import Foundation

public struct I420Frame: Equatable, Sendable {
    public let pixelSize: PixelSize
    public let yPlane: Data
    public let uPlane: Data
    public let vPlane: Data

    public init(pixelSize: PixelSize, yPlane: Data, uPlane: Data, vPlane: Data) throws {
        let chromaWidth = pixelSize.width / 2
        let chromaHeight = pixelSize.height / 2
        guard pixelSize.width.isMultiple(of: 2),
              pixelSize.height.isMultiple(of: 2),
              yPlane.count == pixelSize.width * pixelSize.height,
              uPlane.count == chromaWidth * chromaHeight,
              vPlane.count == chromaWidth * chromaHeight else {
            throw CodecPipelineModelError.invalidI420Frame
        }

        self.pixelSize = pixelSize
        self.yPlane = yPlane
        self.uPlane = uPlane
        self.vPlane = vPlane
    }
}

public struct CodecVideoFrame: Equatable, Sendable {
    public let frame: I420Frame
    public let presentationTime: TimeInterval
    public let duration: TimeInterval

    public init(frame: I420Frame, presentationTime: TimeInterval, duration: TimeInterval) throws {
        guard presentationTime >= 0, duration > 0 else {
            throw CodecPipelineModelError.invalidFrameTiming
        }

        self.frame = frame
        self.presentationTime = presentationTime
        self.duration = duration
    }
}

public struct CodecAudioChunk: Equatable, Sendable {
    public let pcmData: Data
    public let presentationTime: TimeInterval
    public let duration: TimeInterval

    public init(pcmData: Data, presentationTime: TimeInterval, duration: TimeInterval) throws {
        guard !pcmData.isEmpty, presentationTime >= 0, duration > 0 else {
            throw CodecPipelineModelError.invalidAudioChunk
        }

        self.pcmData = pcmData
        self.presentationTime = presentationTime
        self.duration = duration
    }
}

public struct CodecColorInfo: Codable, Equatable, Sendable {
    public static let bt709Limited = CodecColorInfo(
        primaries: "BT.709",
        transferFunction: "BT.709",
        matrix: "BT.709",
        isFullRange: false
    )

    public let primaries: String
    public let transferFunction: String
    public let matrix: String
    public let isFullRange: Bool

    public init(primaries: String, transferFunction: String, matrix: String, isFullRange: Bool) {
        self.primaries = primaries
        self.transferFunction = transferFunction
        self.matrix = matrix
        self.isFullRange = isFullRange
    }
}

public struct EncodedPacket: Equatable, Sendable {
    public let data: Data
    public let presentationTime: TimeInterval
    public let duration: TimeInterval
    public let isKeyFrame: Bool

    public init(
        data: Data,
        presentationTime: TimeInterval,
        duration: TimeInterval,
        isKeyFrame: Bool
    ) throws {
        guard !data.isEmpty, presentationTime >= 0, duration >= 0 else {
            throw CodecPipelineModelError.invalidEncodedPacket
        }

        self.data = data
        self.presentationTime = presentationTime
        self.duration = duration
        self.isKeyFrame = isKeyFrame
    }
}

public enum CodecTrack: String, Codable, Equatable, Sendable {
    case video
    case audio
}

public struct CodecVideoEncoderConfiguration: Equatable, Sendable {
    public let pixelSize: PixelSize
    public let frameRate: FrameRate
    public let colorInfo: CodecColorInfo
    public let quality: ExportQuality

    public init(
        pixelSize: PixelSize,
        frameRate: FrameRate,
        colorInfo: CodecColorInfo = .bt709Limited,
        quality: ExportQuality
    ) {
        self.pixelSize = pixelSize
        self.frameRate = frameRate
        self.colorInfo = colorInfo
        self.quality = quality
    }
}

public struct CodecAudioEncoderConfiguration: Equatable, Sendable {
    public let sampleRate: Int
    public let channelCount: Int
    public let quality: ExportQuality

    public init(sampleRate: Int, channelCount: Int, quality: ExportQuality) throws {
        guard sampleRate > 0, channelCount > 0 else {
            throw CodecPipelineModelError.invalidAudioConfiguration
        }

        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.quality = quality
    }
}

public struct CodecMuxerConfiguration: Equatable, Sendable {
    public let outputFileURL: URL
    public let format: ExportFormat
    public let tracks: [CodecTrack]
    public let pixelSize: PixelSize?

    public init(
        outputFileURL: URL,
        format: ExportFormat,
        tracks: [CodecTrack],
        pixelSize: PixelSize? = nil
    ) throws {
        guard !tracks.isEmpty else {
            throw CodecPipelineModelError.invalidMuxerConfiguration
        }

        self.outputFileURL = outputFileURL
        self.format = format
        self.tracks = tracks
        self.pixelSize = pixelSize
    }
}

public struct CodecMediaSourceDescription: Equatable, Sendable {
    public let videoFrameCount: Int
    public let audioChunkCount: Int
    public let audioSampleRate: Int?
    public let audioChannelCount: Int?

    public init(
        videoFrameCount: Int,
        audioChunkCount: Int = 0,
        audioSampleRate: Int? = nil,
        audioChannelCount: Int? = nil
    ) throws {
        guard videoFrameCount >= 0, audioChunkCount >= 0 else {
            throw CodecPipelineModelError.invalidMediaSourceDescription
        }

        if audioChunkCount > 0 {
            guard let audioSampleRate, audioSampleRate > 0,
                  let audioChannelCount, audioChannelCount > 0 else {
                throw CodecPipelineModelError.invalidMediaSourceDescription
            }
        }

        self.videoFrameCount = videoFrameCount
        self.audioChunkCount = audioChunkCount
        self.audioSampleRate = audioSampleRate
        self.audioChannelCount = audioChannelCount
    }

    public var hasAudio: Bool {
        audioChunkCount > 0
    }
}

public enum CodecPipelineModelError: Error, Equatable {
    case invalidI420Frame
    case invalidFrameTiming
    case invalidAudioChunk
    case invalidEncodedPacket
    case invalidAudioConfiguration
    case invalidMuxerConfiguration
    case invalidMediaSourceDescription
}
