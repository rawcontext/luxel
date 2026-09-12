import AppKit
import LuxelCore
import SwiftUI

@MainActor
final class LuxelAboutWindowPresenter {
    private let metadata: AppMetadata
    private var window: NSWindow?

    init(metadata: AppMetadata) {
        self.metadata = metadata
    }

    func open() {
        let window = window ?? makeWindow()
        NSApplication.shared.unhide(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func makeWindow() -> NSWindow {
        let hostingController = NSHostingController(rootView: LuxelAboutView(metadata: metadata))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "About \(metadata.displayName)"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 360, height: 410))
        window.center()
        window.isReleasedWhenClosed = false
        self.window = window
        return window
    }
}

private struct LuxelAboutView: View {
    @State private var isShowingAcknowledgements = false

    let metadata: AppMetadata

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 88, height: 88)

            VStack(spacing: 6) {
                Text(metadata.displayName)
                    .font(.title2.weight(.semibold))

                Text("Version \(metadata.versionSummary)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if !metadata.copyright.isEmpty {
                Text(metadata.copyright)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                Link("luxel.media", destination: LuxelAboutLinks.website)

                HStack(spacing: 12) {
                    Link("GitHub Repository", destination: LuxelAboutLinks.repository)
                    Link("MIT License", destination: LuxelAboutLinks.license)
                }

                HStack(spacing: 12) {
                    Link("Report an Issue", destination: LuxelAboutLinks.support)
                    Link("Request a Feature", destination: LuxelAboutLinks.support)
                }

                Button("View on the App Store", action: openAppStoreListing)
                    .buttonStyle(.link)
            }
            .font(.callout)

            Button {
                isShowingAcknowledgements = true
            } label: {
                Label("Acknowledgements", systemImage: "doc.text")
            }
        }
        .padding(24)
        .frame(width: 360)
        .sheet(isPresented: $isShowingAcknowledgements) {
            CodecAcknowledgementsView(text: CodecAcknowledgementsResource.bundledText())
        }
    }

    private func openAppStoreListing() {
        guard
            let appStoreApplicationURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "com.apple.AppStore")
        else {
            return
        }

        NSWorkspace.shared.open(
            [LuxelAboutLinks.appStore],
            withApplicationAt: appStoreApplicationURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}

private enum LuxelAboutLinks {
    static let website = URL(string: "https://luxel.media")!
    static let repository = URL(string: "https://github.com/rawcontext/luxel")!
    static let license = URL(string: "https://github.com/rawcontext/luxel/blob/master/LICENSE")!
    static let support = URL(string: "https://luxel.media/support")!
    static let appStore = URL(
        string: "https://apps.apple.com/us/app/luxel/id6800438206?mt=12")!
}
