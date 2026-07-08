import AVKit
import SwiftUI

struct LuxelPlayerView: NSViewRepresentable {
    let player: AVPlayer
    let usesAlphaBackground: Bool

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        view.player = player
        updateBackground(for: view)
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }

        updateBackground(for: nsView)
    }

    private func updateBackground(for view: AVPlayerView) {
        view.wantsLayer = true
        view.layer?.backgroundColor =
            usesAlphaBackground
            ? NSColor.clear.cgColor
            : NSColor.black.cgColor
    }
}
