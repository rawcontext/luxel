import Foundation

public struct BundleAppMetadataReader: AppMetadataReader {
    private let infoDictionary: [String: String]

    public init(bundle: Bundle = .main) {
        self.init(
            infoDictionary: bundle.infoDictionary?.compactMapValues { $0 as? String } ?? [:]
        )
    }

    public init(infoDictionary: [String: String]) {
        self.infoDictionary = infoDictionary
    }

    public func read() -> AppMetadata {
        AppMetadata(
            displayName: value(for: "CFBundleDisplayName", fallingBackTo: "CFBundleName", defaultValue: "Luxel"),
            version: value(for: "CFBundleShortVersionString", defaultValue: "0.0.0"),
            build: value(for: "CFBundleVersion", defaultValue: ""),
            copyright: value(for: "NSHumanReadableCopyright", defaultValue: "")
        )
    }

    private func value(
        for key: String,
        fallingBackTo fallbackKey: String? = nil,
        defaultValue: String
    ) -> String {
        if let value = infoDictionary[key], !value.isEmpty {
            return value
        }

        if let fallbackKey, let value = infoDictionary[fallbackKey], !value.isEmpty {
            return value
        }

        return defaultValue
    }
}
