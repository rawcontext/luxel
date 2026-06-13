import Foundation
import ScreenCaptureKit

public protocol ScreenCaptureKitContentFilterProvider: Sendable {
    func contentFilter(for target: CaptureTarget) async throws -> SCContentFilter
}

public struct ShareableContentFilterProvider: ScreenCaptureKitContentFilterProvider {
    public init() {}

    public func contentFilter(for target: CaptureTarget) async throws -> SCContentFilter {
        let content = try await SCShareableContent.current

        switch target {
        case .display(let displayID), .area(let displayID, _):
            guard let display = content.displays.first(where: { $0.displayID == displayID.rawValue }) else {
                throw ScreenCaptureKitContentFilterProviderError.displayUnavailable(displayID)
            }

            return SCContentFilter(display: display, excludingWindows: [])

        case .window(let id):
            guard let window = content.windows.first(where: { $0.windowID == id }) else {
                throw ScreenCaptureKitContentFilterProviderError.windowUnavailable(id)
            }

            return SCContentFilter(desktopIndependentWindow: window)
        }
    }
}

public enum ScreenCaptureKitContentFilterProviderError: Error, Equatable {
    case displayUnavailable(DisplayID)
    case windowUnavailable(UInt32)
}
