import Foundation

public enum FrameGrabDestination: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case clipboard
    case file

    public var requiresFileURL: Bool {
        switch self {
        case .clipboard:
            false
        case .file:
            true
        }
    }
}

public struct FrameGrabImageData: Equatable, Sendable {
    public let data: Data
    public let pixelSize: PixelSize

    public init(data: Data, pixelSize: PixelSize) throws {
        guard !data.isEmpty else {
            throw FrameGrabError.emptyImageData
        }

        self.data = data
        self.pixelSize = pixelSize
    }
}

public struct FrameGrabRequest: Codable, Equatable, Sendable {
    public let sourceFileURL: URL
    public let time: TimeInterval
    public let cropRect: CaptureRect?

    public init(
        sourceFileURL: URL,
        time: TimeInterval,
        cropRect: CaptureRect? = nil
    ) throws {
        guard time.isFinite, time >= 0 else {
            throw FrameGrabError.invalidFrameTime
        }

        self.sourceFileURL = sourceFileURL
        self.time = time
        self.cropRect = cropRect
    }

    public var suggestedFileName: String {
        let sourceName = sourceFileURL.deletingPathExtension().lastPathComponent
        return "\(sourceName) (frame \(Self.frameTimeText(time))).png"
    }

    private static func frameTimeText(_ time: TimeInterval) -> String {
        let totalTenths = Int((time * 10).rounded(.down))
        let minutes = totalTenths / 600
        let seconds = (totalTenths / 10) % 60
        let tenths = totalTenths % 10

        return String(format: "%d.%02d.%d", minutes, seconds, tenths)
    }
}

public enum FrameGrabError: Error, Equatable {
    case emptyImageData
    case emptyFrameGrabDestinations
    case fileDestinationRequiresOutputURL
    case invalidFrameTime
}
