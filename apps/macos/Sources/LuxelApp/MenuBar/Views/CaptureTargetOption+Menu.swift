import AppKit
import LuxelCore
import SwiftUI

struct CaptureTargetMenuLabel: View {
    let target: CaptureTargetOption

    var body: some View {
        Label {
            Text(target.title)
        } icon: {
            CaptureTargetMenuIcon(target: target)
        }
    }
}

private struct CaptureTargetMenuIcon: View {
    let target: CaptureTargetOption

    var body: some View {
        if let appIcon = target.owningApplicationIcon {
            Image(nsImage: appIcon)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
        } else {
            Image(systemName: target.systemImage)
                .symbolRenderingMode(.hierarchical)
        }
    }
}

extension CaptureTargetOption {
    var systemImage: String {
        switch kind {
        case .display:
            "display"
        case .window:
            "macwindow"
        }
    }

    @MainActor
    fileprivate var owningApplicationIcon: NSImage? {
        guard kind == .window else {
            return nil
        }

        if let processIdentifier = owningApplicationProcessIdentifier,
           let icon = NSRunningApplication(processIdentifier: processIdentifier)?.icon {
            icon.size = NSSize(width: 18, height: 18)
            return icon
        }

        guard let bundleIdentifier = owningApplicationBundleIdentifier,
              let applicationURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleIdentifier)
        else {
            return nil
        }

        let icon = NSWorkspace.shared.icon(forFile: applicationURL.path)
        icon.size = NSSize(width: 18, height: 18)
        return icon
    }
}
