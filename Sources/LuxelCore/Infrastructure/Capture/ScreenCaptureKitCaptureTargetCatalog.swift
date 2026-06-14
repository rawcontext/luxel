import CoreGraphics
import Foundation
import ScreenCaptureKit

public struct ScreenCaptureKitCaptureTargetCatalog: CaptureTargetCatalog {
    public init() {}

    public func availableDisplays() async throws -> [DisplayBounds] {
        let snapshot = try await snapshot()
        return snapshot.displays
    }

    public func availableTargets() async throws -> [CaptureTargetOption] {
        let snapshot = try await snapshot()
        return snapshot.targets
    }

    public func snapshot() async throws -> CaptureTargetCatalogSnapshot {
        let content = try await SCShareableContent.current
        let displayItems = try content.displays.enumerated().map { index, display -> (
            bounds: DisplayBounds,
            target: CaptureTargetOption
        ) in
            let bounds = try displayBounds(for: display)
            return (bounds, try displayTarget(for: bounds, index: index))
        }
        let windowTargets = try content.windows.compactMap(windowTarget)

        return CaptureTargetCatalogSnapshot(
            displays: displayItems.map(\.bounds),
            targets: displayItems.map(\.target) + windowTargets
        )
    }

    private func displayTarget(for bounds: DisplayBounds, index: Int) throws -> CaptureTargetOption {
        let size = try PixelSize(width: bounds.width, height: bounds.height)
        let frame = try CaptureRect(x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height)

        return CaptureTargetOption(
            id: "display-\(bounds.id.rawValue)",
            kind: .display,
            title: "Display \(index + 1)",
            subtitle: "\(bounds.width)x\(bounds.height)",
            target: .display(bounds.id),
            pixelSize: size,
            frame: frame
        )
    }

    private func windowTarget(for window: SCWindow) throws -> CaptureTargetOption? {
        guard window.isOnScreen, window.windowLayer == 0 else {
            return nil
        }

        let frame = roundedRect(window.frame)
        guard frame.width > 0, frame.height > 0 else {
            return nil
        }

        let appName = window.owningApplication?.applicationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let windowTitle = window.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = nonEmpty(windowTitle)
            ?? nonEmpty(appName)
            ?? "Window \(window.windowID)"

        return try CaptureTargetOption(
            id: "window-\(window.windowID)",
            kind: .window,
            title: title,
            subtitle: nonEmpty(appName),
            target: .window(id: window.windowID),
            pixelSize: PixelSize(width: frame.width, height: frame.height),
            frame: CaptureRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
        )
    }

    private func displayBounds(for display: SCDisplay) throws -> DisplayBounds {
        let frame = roundedRect(display.frame)

        return try DisplayBounds(
            id: DisplayID(display.displayID),
            x: frame.x,
            y: frame.y,
            width: display.width,
            height: display.height
        )
    }

    private func roundedRect(_ rect: CGRect) -> (x: Int, y: Int, width: Int, height: Int) {
        (
            x: Int(rect.origin.x.rounded()),
            y: Int(rect.origin.y.rounded()),
            width: Int(rect.width.rounded()),
            height: Int(rect.height.rounded())
        )
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }

        return value
    }
}
