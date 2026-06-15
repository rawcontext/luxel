import Foundation

public enum CaptureAspectRatioPreset: String, CaseIterable, Codable, Equatable, Sendable {
    case free
    case widescreen16x9
    case standard4x3
    case square1x1
    case vertical9x16
    case ultrawide21x9

    public var title: String {
        switch self {
        case .free:
            "Free"
        case .widescreen16x9:
            "16:9"
        case .standard4x3:
            "4:3"
        case .square1x1:
            "1:1"
        case .vertical9x16:
            "9:16"
        case .ultrawide21x9:
            "21:9"
        }
    }

    public var aspectRatio: CaptureAspectRatio? {
        switch self {
        case .free:
            nil
        case .widescreen16x9:
            .widescreen16x9
        case .standard4x3:
            .standard4x3
        case .square1x1:
            .square1x1
        case .vertical9x16:
            .vertical9x16
        case .ultrawide21x9:
            .ultrawide21x9
        }
    }
}

public struct CaptureSizePreset: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var pixelSize: PixelSize

    public init(id: UUID = UUID(), name: String, pixelSize: PixelSize) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw CaptureModelError.invalidDimensions
        }

        self.id = id
        self.name = trimmedName
        self.pixelSize = pixelSize
    }

    public static let builtInDefaults: [CaptureSizePreset] = [
        CaptureSizePreset(
            uncheckedID: UUID(uuidString: "00000000-0000-0000-0000-000000000701")!,
            name: "1280x720",
            pixelSize: .hd1280x720
        ),
        CaptureSizePreset(
            uncheckedID: UUID(uuidString: "00000000-0000-0000-0000-000000000702")!,
            name: "1920x1080",
            pixelSize: .fullHD1920x1080
        ),
        CaptureSizePreset(
            uncheckedID: UUID(uuidString: "00000000-0000-0000-0000-000000000703")!,
            name: "800x600",
            pixelSize: .svga800x600
        ),
        CaptureSizePreset(
            uncheckedID: UUID(uuidString: "00000000-0000-0000-0000-000000000704")!,
            name: "X/Twitter 1280x720",
            pixelSize: .hd1280x720
        ),
        CaptureSizePreset(
            uncheckedID: UUID(uuidString: "00000000-0000-0000-0000-000000000705")!,
            name: "App Store Preview 1920x1080",
            pixelSize: .fullHD1920x1080
        )
    ]

    private init(uncheckedID id: UUID, name: String, pixelSize: PixelSize) {
        self.id = id
        self.name = name
        self.pixelSize = pixelSize
    }
}
