import AppKit
import Foundation
import ScreenCaptureKit

public protocol ScreenCaptureKitContentFilterProvider: Sendable {
    func contentFilter(for target: CaptureTarget) async throws -> SCContentFilter
}

public struct ShareableContentFilterProvider: ScreenCaptureKitContentFilterProvider {
    private let exclusionRegistry: CaptureExclusionRegistry?
    private let activatesWindowTargetsBeforeCapture: Bool
    private let windowActivationSettleDuration: Duration

    public init(
        exclusionRegistry: CaptureExclusionRegistry? = nil,
        activatesWindowTargetsBeforeCapture: Bool = true,
        windowActivationSettleDuration: Duration = .milliseconds(300)
    ) {
        self.exclusionRegistry = exclusionRegistry
        self.activatesWindowTargetsBeforeCapture = activatesWindowTargetsBeforeCapture
        self.windowActivationSettleDuration = windowActivationSettleDuration
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
            let content = try await contentByPreparingWindowTarget(id, from: content)
            guard let window = content.windows.first(where: { $0.windowID == id }) else {
                throw SCKContentFilterProviderError.windowUnavailable(id)
            }

            return SCContentFilter(desktopIndependentWindow: window)
        }
    }

    private func contentByPreparingWindowTarget(
        _ windowID: UInt32,
        from content: SCShareableContent
    ) async throws -> SCShareableContent {
        guard activatesWindowTargetsBeforeCapture,
              let window = content.windows.first(where: { $0.windowID == windowID }),
              let processID = window.owningApplication?.processID,
              await activateOwningApplicationIfNeeded(processID: processID) else {
            return content
        }

        try await Task.sleep(for: windowActivationSettleDuration)
        return try await SCShareableContent.current
    }

    private func activateOwningApplicationIfNeeded(processID: pid_t) async -> Bool {
        await MainActor.run {
            guard processID != NSRunningApplication.current.processIdentifier,
                  let application = NSRunningApplication(processIdentifier: processID),
                  !application.isActive else {
                return false
            }

            return application.activate(options: .activateAllWindows)
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
