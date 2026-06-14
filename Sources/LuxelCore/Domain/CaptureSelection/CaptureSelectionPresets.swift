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
            try! CaptureAspectRatio(width: 16, height: 9)
        case .standard4x3:
            try! CaptureAspectRatio(width: 4, height: 3)
        case .square1x1:
            try! CaptureAspectRatio(width: 1, height: 1)
        case .vertical9x16:
            try! CaptureAspectRatio(width: 9, height: 16)
        case .ultrawide21x9:
            try! CaptureAspectRatio(width: 21, height: 9)
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
        try! CaptureSizePreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000701")!,
            name: "1280x720",
            pixelSize: PixelSize(width: 1280, height: 720)
        ),
        try! CaptureSizePreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000702")!,
            name: "1920x1080",
            pixelSize: PixelSize(width: 1920, height: 1080)
        ),
        try! CaptureSizePreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000703")!,
            name: "800x600",
            pixelSize: PixelSize(width: 800, height: 600)
        ),
        try! CaptureSizePreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000704")!,
            name: "X/Twitter 1280x720",
            pixelSize: PixelSize(width: 1280, height: 720)
        ),
        try! CaptureSizePreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000705")!,
            name: "App Store Preview 1920x1080",
            pixelSize: PixelSize(width: 1920, height: 1080)
        )
    ]
}
