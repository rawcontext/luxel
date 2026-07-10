import Testing

@testable import LuxelPresentation

@Suite("Transcript speaker palette")
struct TranscriptSpeakerPaletteTests {
    @Test("normalizes speaker names before assigning a stable color")
    func normalizesNames() {
        #expect(
            TranscriptSpeakerPalette.paletteIndex(for: "Jordan Smith")
                == TranscriptSpeakerPalette.paletteIndex(for: "  JORDAN   SMITH  ")
        )
    }

    @Test("provides distinct colors for the reported known speakers")
    func distinguishesReportedSpeakers() {
        let names = [
            "Taylor Reed",
            "Morgan Lee",
            "ccheney",
            "Jordan Smith",
            "Alex Rivera",
            "Avery Chen",
            "Riley Quinn"
        ]

        #expect(Set(names.map(TranscriptSpeakerPalette.paletteIndex(for:))).count == names.count)
        #expect(TranscriptSpeakerPalette.colorCount >= 50)
    }
}
