import LuxelCore
import Testing

@Suite("Notch surface status presentation")
struct NotchSurfaceStatusPresentationTests {
    @Test("available notch display reports notch availability")
    func availableNotchDisplayReportsNotchAvailability() throws {
        let display = try testBuiltInNotchedDisplay()

        let presentation = NotchSurfaceStatusPresentation(displays: [display])

        #expect(presentation.statusText == "Notch Available")
        #expect(presentation.detailText == "Luxel can use the built-in notch display.")
        #expect(presentation.selection == .notch(try #require(NotchGeometry.resolve(from: display))))
        #expect(!presentation.showsStatus)
    }

    @Test("missing notch display reports HUD fallback")
    func missingNotchDisplayReportsHUDFallback() {
        let presentation = NotchSurfaceStatusPresentation(displays: [])

        #expect(presentation.statusText == "Floating HUD Fallback")
        #expect(presentation.detailText == "No built-in notched display is currently detected.")
        #expect(presentation.selection == .floatingHUD(.noNotchedDisplay))
        #expect(presentation.showsStatus)
    }

    @Test("disabled fallback reports menu bar only")
    func disabledFallbackReportsMenuBarOnly() {
        let presentation = NotchSurfaceStatusPresentation(
            displays: [],
            preferences: NotchSurfacePreferences(fallbackToFloatingHUDWhenUnavailable: false)
        )

        #expect(presentation.statusText == "Menu Bar Only")
        #expect(
            presentation.detailText
                == "No built-in notched display is detected, and floating HUD fallback is off."
        )
        #expect(presentation.selection == .menuBarOnly(.noNotchedDisplay))
        #expect(presentation.showsStatus)
    }

    @Test("disabled notch reports fallback reason")
    func disabledNotchReportsFallbackReason() throws {
        let presentation = NotchSurfaceStatusPresentation(
            displays: [try testBuiltInNotchedDisplay()],
            preferences: NotchSurfacePreferences(isEnabled: false)
        )

        #expect(presentation.statusText == "Floating HUD Fallback")
        #expect(
            presentation.detailText
                == "The notch surface is disabled, so recording controls will use the fallback surface."
        )
        #expect(presentation.selection == .floatingHUD(.notchDisabled))
        #expect(presentation.showsStatus)
    }

}
