import Foundation

public struct BundledVoiceActivityModelLocator: Sendable {
    public static let modelDirectoryName = "silero-vad-unified-256ms-v6.2.1.mlmodelc"

    private let resourceURL: URL?

    public init(bundle: Bundle = .main) {
        resourceURL = bundle.resourceURL
    }

    init(resourceURL: URL?) {
        self.resourceURL = resourceURL
    }

    public var modelURL: URL? {
        guard let candidate = resourceURL?
                .appendingPathComponent("Models", isDirectory: true)
                .appendingPathComponent("voice-activity-detection", isDirectory: true)
                .appendingPathComponent(Self.modelDirectoryName, isDirectory: true),
              FileManager.default.fileExists(atPath: candidate.path)
        else {
            return nil
        }

        return candidate
    }
}
