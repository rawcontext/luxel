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
    @Test("transcript docks left of the video without covering it")
    func transcriptDocksLeftOfVideo() async throws {
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
        #expect(playerView.ancestors.compactMap { $0 as? NSScrollView }.isEmpty)

        let transcriptTableView = try #require(
            hostingView.descendants.compactMap { $0 as? NSTableView }.first
        )
        let transcriptScrollView = try #require(
            transcriptTableView.ancestors.compactMap { $0 as? NSScrollView }.first
        )
        let transcriptFrame = transcriptScrollView.convert(
            transcriptScrollView.bounds, to: hostingView
        )
        let playerFrame = playerView.convert(playerView.bounds, to: hostingView)

        #expect(transcriptFrame.maxX <= playerFrame.minX)
        #expect(transcriptFrame.minY < playerFrame.maxY)
        #expect(playerFrame.minY < transcriptFrame.maxY)
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
