import CoreGraphics
import Foundation
import LuxelCore
import LuxelTestSupport
import Testing

@Suite("Keystroke renderer")
struct KeystrokeRendererTests {
    @MainActor
    @Test("themes and sizes render cached chip images")
    func themesAndSizesRenderCachedChipImages() throws {
        let chip = try KeystrokeChip(
            timeRange: TimeRange(start: 0, end: 1),
            text: "⌘⇧K",
            kind: .shortcut
        )
        let renderer = KeystrokeChipImageRenderer()
        var widths: [Int] = []

        for size in KeystrokeOverlaySize.allCases {
            for theme in KeystrokeOverlayTheme.allCases {
                let options = try KeystrokeRenderOptions(size: size, theme: theme)
                let first = try #require(renderer.image(for: chip, options: options))
                let cached = try #require(renderer.image(for: chip, options: options))
                #expect(first === cached)
                #expect(first.width > 0)
                #expect(first.height > 0)
                if theme == .darkGlass {
                    widths.append(first.width)
                }
            }
        }

        #expect(widths[0] < widths[1])
        #expect(widths[1] < widths[2])
    }

    @MainActor
    @Test("frame compositor changes only frames with active chips")
    func frameCompositorChangesOnlyFramesWithActiveChips() throws {
        let frame = try makeFrame(width: 320, height: 200)
        let timeline = try KeystrokeTimeline(events: [
            KeystrokeEvent(
                time: 0.5,
                kind: .keyDown,
                keyCode: 8,
                characters: "c",
                modifiers: [.command]
            )
        ])
        let compositor = KeystrokeFrameCompositor()

        let before = compositor.composite(
            frame,
            timeline: timeline,
            options: .standard,
            at: 0.25
        )
        let active = compositor.composite(
            frame,
            timeline: timeline,
            options: .standard,
            at: 0.75
        )

        #expect(pixelData(before) == pixelData(frame))
        #expect(pixelData(active) != pixelData(frame))
    }

    @Test("six anchors stay inside the output frame")
    func sixAnchorsStayInsideOutputFrame() {
        let overlay = CGSize(width: 80, height: 40)
        let frame = CGSize(width: 320, height: 200)

        for anchor in KeystrokeOverlayAnchor.allCases {
            let origin = KeystrokeOverlayLayout.origin(
                overlaySize: overlay,
                frameSize: frame,
                anchor: anchor
            )
            #expect(origin.x >= 0)
            #expect(origin.y >= 0)
            #expect(origin.x + overlay.width <= frame.width)
            #expect(origin.y + overlay.height <= frame.height)
        }
    }

    @Test("timeline cuts split and retime exported keystroke chips")
    func timelineCutsSplitAndRetimeExportedKeystrokeChips() throws {
        let chip = try KeystrokeChip(
            timeRange: TimeRange(start: 1, end: 7),
            text: "⌘K",
            kind: .shortcut
        )
        let mapper = EditedTimelineMapper(
            trimRange: try TimeRange(start: 0, end: 8),
            editPlan: try TimelineEditPlan(cuts: [
                TimelineCut(
                    id: "cut",
                    sourceRange: TimeRange(start: 3, end: 5),
                    kind: .transcriptSentence
                )
            ]),
            speed: try PlaybackSpeed(2)
        )

        #expect(try mapper.mapSourceRange(chip.timeRange) == [
            TimeRange(start: 0.5, end: 1.5),
            TimeRange(start: 1.5, end: 2.5)
        ])
    }

    private func makeFrame(width: Int, height: Int) throws -> CGImage {
        try makeTestImage(width: width, height: height) { context in
            context.setFillColor(CGColor(gray: 0.1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private func pixelData(_ image: CGImage) -> Data? {
        image.dataProvider?.data as Data?
    }
}
