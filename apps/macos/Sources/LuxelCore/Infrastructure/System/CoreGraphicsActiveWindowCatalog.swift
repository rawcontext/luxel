import AppKit
import CoreGraphics
import Foundation

@MainActor
public final class CoreGraphicsActiveWindowCatalog: ActiveWindowCatalog {
    public init() {}

    public func orderedActiveWindowIDs() -> [UInt32] {
        let frontmostProcessID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let currentProcessID = ProcessInfo.processInfo.processIdentifier
        let windows = windowInfos()

        let frontmostApplicationWindows = windows.filter { window in
            window.ownerProcessID == frontmostProcessID
        }

        if !frontmostApplicationWindows.isEmpty, frontmostProcessID != currentProcessID {
            return frontmostApplicationWindows.map(\.id)
        }

        return
            windows
            .filter { $0.ownerProcessID != currentProcessID }
            .map(\.id)
    }

    private func windowInfos() -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard
            let dictionaries = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else {
            return []
        }

        return dictionaries.compactMap(WindowInfo.init(dictionary:))
    }

    private struct WindowInfo {
        let id: UInt32
        let ownerProcessID: pid_t

        init?(dictionary: [String: Any]) {
            guard let id = dictionary.uint32Value(for: kCGWindowNumber),
                  dictionary.intValue(for: kCGWindowLayer) == 0,
                  dictionary.doubleValue(for: kCGWindowAlpha, default: 1) > 0
            else {
                return nil
            }

            self.id = id
            self.ownerProcessID = pid_t(dictionary.intValue(for: kCGWindowOwnerPID) ?? 0)
        }
    }
}

extension Dictionary where Key == String, Value == Any {
    fileprivate func intValue(for key: CFString) -> Int? {
        if let value = self[key as String] as? Int {
            return value
        }

        if let value = self[key as String] as? NSNumber {
            return value.intValue
        }

        return nil
    }

    fileprivate func uint32Value(for key: CFString) -> UInt32? {
        guard let value = intValue(for: key), value >= 0 else {
            return nil
        }

        return UInt32(value)
    }

    fileprivate func doubleValue(for key: CFString, default defaultValue: Double) -> Double {
        if let value = self[key as String] as? Double {
            return value
        }

        if let value = self[key as String] as? NSNumber {
            return value.doubleValue
        }

        return defaultValue
    }
}
