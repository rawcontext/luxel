import LuxelCore
import Testing

@Suite("Notch surface status presentation")
struct NotchSurfaceStatusPresentationTests {
    @Test("available notch display reports notch availability")
    func availableNotchDisplayReportsNotchAvailability() throws {
        let display = try builtInNotchedDisplay()

        let presentation = NotchSurfaceStatusPresentation(displays: [display])

        #expect(presentation.statusText == "Notch Available")
        #expect(presentation.detailText == "Luxel can use the built-in notch display.")
        #expect(presentation.selection == .notch(try #require(NotchGeometry.resolve(from: display))))
    }

    @Test("missing notch display reports HUD fallback")
    func missingNotchDisplayReportsHUDFallback() {
        let presentation = NotchSurfaceStatusPresentation(displays: [])

        #expect(presentation.statusText == "Floating HUD Fallback")
        #expect(presentation.detailText == "No built-in notched display is currently detected.")
        #expect(presentation.selection == .floatingHUD(.noNotchedDisplay))
    }

    @Test("disabled fallback reports menu bar only")
    func disabledFallbackReportsMenuBarOnly() {
        let presentation = NotchSurfaceStatusPresentation(
            displays: [],
            preferences: NotchSurfacePreferences(fallbackToFloatingHUDWhenUnavailable: false)
        )

        #expect(presentation.statusText == "Menu Bar Only")
        #expect(
            presentation.detailText == "No built-in notched display is detected, and floating HUD fallback is off."
        )
        #expect(presentation.selection == .menuBarOnly(.noNotchedDisplay))
    }

    @Test("disabled notch reports fallback reason")
    func disabledNotchReportsFallbackReason() throws {
        let presentation = NotchSurfaceStatusPresentation(
            displays: [try builtInNotchedDisplay()],
            preferences: NotchSurfacePreferences(isEnabled: false)
        )

        #expect(presentation.statusText == "Floating HUD Fallback")
        #expect(
            presentation.detailText == "The notch surface is disabled, so recording controls will use the fallback surface."
        )
        #expect(presentation.selection == .floatingHUD(.notchDisabled))
    }

    private func builtInNotchedDisplay() throws -> NotchDisplayDescriptor {
        try NotchDisplayDescriptor(
            displayID: DisplayID(1),
            frame: rect(x: 0, y: 0, width: 1512, height: 982),
            safeAreaInsets: NotchSafeAreaInsets(top: 34),
            auxiliaryTopLeftArea: rect(x: 0, y: 948, width: 640, height: 34),
            auxiliaryTopRightArea: rect(x: 872, y: 948, width: 640, height: 34),
            isBuiltIn: true
        )
    }

    private func rect(
        x originX: Double,
        y originY: Double,
        width: Double,
        height: Double
    ) throws -> NotchScreenRect {
        try NotchScreenRect(x: originX, y: originY, width: width, height: height)
    }
}
