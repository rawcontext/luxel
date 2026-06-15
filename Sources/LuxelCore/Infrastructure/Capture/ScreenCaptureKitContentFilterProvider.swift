import Foundation
import ScreenCaptureKit

public protocol ScreenCaptureKitContentFilterProvider: Sendable {
    func contentFilter(for target: CaptureTarget) async throws -> SCContentFilter
}

public struct ShareableContentFilterProvider: ScreenCaptureKitContentFilterProvider {
    private let exclusionRegistry: CaptureExclusionRegistry?

    public init(exclusionRegistry: CaptureExclusionRegistry? = nil) {
        self.exclusionRegistry = exclusionRegistry
    }

    public func contentFilter(for target: CaptureTarget) async throws -> SCContentFilter {
        let content = try await SCShareableContent.current

        switch target {
        case .display(let displayID), .area(let displayID, _):
            guard let display = content.displays.first(where: { $0.displayID == displayID.rawValue }) else {
                throw SCKContentFilterProviderError.displayUnavailable(displayID)
            }

            return SCContentFilter(
                display: display,
                excludingWindows: await excludedWindows(from: content)
            )

        case .window(let id):
            guard let window = content.windows.first(where: { $0.windowID == id }) else {
                throw SCKContentFilterProviderError.windowUnavailable(id)
            }

            return SCContentFilter(desktopIndependentWindow: window)
        }
    }

    private func excludedWindows(from content: SCShareableContent) async -> [SCWindow] {
        guard let exclusionRegistry else {
            return []
        }

        let excludedWindowIDs = Set(await exclusionRegistry.excludedWindowIDs())
        return content.windows.filter { excludedWindowIDs.contains($0.windowID) }
    }
}

public enum SCKContentFilterProviderError: Error, Equatable {
    case displayUnavailable(DisplayID)
    case windowUnavailable(UInt32)
}
