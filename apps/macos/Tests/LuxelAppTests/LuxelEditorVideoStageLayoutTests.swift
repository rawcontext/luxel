import AVKit
import AppKit
import Foundation
import LuxelCore
import SwiftUI
import Testing

@testable import LuxelPresentation

@MainActor
@Suite("Luxel editor video stage layout")
struct LuxelEditorVideoStageLayoutTests {
    @Test("video and transcript render inside a shared scroll region")
    func videoAndTranscriptShareScrollRegion() async throws {
        let helper = LuxelEditorModelTests()
        let transcript = try helper.sampleTranscript(source: .system)
        let model = helper.makeModel(
            audioTranscriptService: SpyAudioTranscriptService(transcript: transcript)
        )
        await model.open(
            fileURL: URL(fileURLWithPath: "/tmp/video.mp4"),
            outputDirectory: URL(fileURLWithPath: "/tmp")
        )
        model.transcript = transcript
        model.isTranscriptPanelVisible = true

        let hostingView = NSHostingView(rootView: LuxelEditorView(model: model))
        hostingView.frame = NSRect(x: 0, y: 0, width: 1_100, height: 700)
        hostingView.layoutSubtreeIfNeeded()

        let playerView = try #require(
            hostingView.descendants.compactMap { $0 as? AVPlayerView }.first
        )
        let sharedScrollView = try #require(
            playerView.ancestors.compactMap { $0 as? NSScrollView }.first
        )
        let transcriptScrollView = try #require(
            sharedScrollView.descendants.compactMap { $0 as? NSScrollView }.first
        )
        let documentView = try #require(sharedScrollView.documentView)
        let transcriptFrame = transcriptScrollView.convert(transcriptScrollView.bounds, to: documentView)
        let playerFrame = playerView.convert(playerView.bounds, to: documentView)

        #expect(transcriptFrame.maxY <= playerFrame.minY)
        #expect(playerFrame.height >= sharedScrollView.contentView.bounds.height)
    }
}

private extension NSView {
    var ancestors: [NSView] {
        var views: [NSView] = []
        var ancestor = superview

        while let current = ancestor {
            views.append(current)
            ancestor = current.superview
        }

        return views
    }

    var descendants: [NSView] {
        subviews + subviews.flatMap(\.descendants)
    }
}
