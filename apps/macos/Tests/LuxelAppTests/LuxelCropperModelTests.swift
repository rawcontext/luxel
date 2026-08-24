import Foundation
import LuxelCore
import Testing

@testable import LuxelApp

@Suite("Luxel cropper model")
@MainActor
struct LuxelCropperModelTests {
    @Test("custom stop duration applies the entered value")
    func customStopDurationAppliesEnteredValue() throws {
        var observedDuration: TimeInterval?
        let model = LuxelCropperModel(
            display: try DisplayBounds(
                id: DisplayID(1),
                x: 0,
                y: 0,
                width: 1_920,
                height: 1_080
            ),
            onStopAfterDurationChange: { observedDuration = $0 }
        )

        model.setCustomStopAfterText("2:30")

        #expect(model.applyCustomStopAfterDuration())
        #expect(model.stopAfterDuration == 150)
        #expect(model.customStopAfterText == "2:30")
        #expect(observedDuration == 150)
    }

    @Test("invalid custom stop duration preserves the previous selection")
    func invalidCustomStopDurationPreservesPreviousSelection() throws {
        let model = LuxelCropperModel(
            display: try DisplayBounds(
                id: DisplayID(1),
                x: 0,
                y: 0,
                width: 1_920,
                height: 1_080
            ),
            stopAfterDuration: 10
        )
        model.setCustomStopAfterText("1:99")

        #expect(!model.applyCustomStopAfterDuration())
        #expect(model.stopAfterDuration == 10)
    }
}
