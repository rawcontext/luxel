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
        window.setContentSize(NSSize(width: 360, height: 300))
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
}
