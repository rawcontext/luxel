import LuxelCore
import Testing

@Suite("Notch geometry models")
struct NotchGeometryModelTests {
    @Test("geometry derives camera housing from auxiliary top areas")
    func geometryDerivesCameraHousingFromAuxiliaryTopAreas() throws {
        let display = try builtInNotchedDisplay(safeAreaTopInset: 37)

        let geometry = try #require(NotchGeometry.resolve(from: display))

        #expect(geometry.displayID == DisplayID(1))
        #expect(geometry.safeAreaTopInset == 37)
        #expect(geometry.cameraHousingRect == (try rect(x: 640, y: 948, width: 232, height: 34)))
    }

    @Test("geometry is unavailable without a visible built-in notched display")
    func geometryRequiresVisibleBuiltInNotchedDisplay() throws {
        var display = try builtInNotchedDisplay(safeAreaTopInset: 0)
        #expect(NotchGeometry.resolve(from: display) == nil)

        display = try builtInNotchedDisplay(isBuiltIn: false)
        #expect(NotchGeometry.resolve(from: display) == nil)

        display = try builtInNotchedDisplay(isVisible: false)
        #expect(NotchGeometry.resolve(from: display) == nil)
    }

    @Test("geometry rejects missing or overlapping auxiliary areas")
    func geometryRejectsMissingOrOverlappingAuxiliaryAreas() throws {
        let missingRightArea = try NotchDisplayDescriptor(
            displayID: DisplayID(1),
            frame: rect(x: 0, y: 0, width: 1512, height: 982),
            safeAreaInsets: NotchSafeAreaInsets(top: 34),
            auxiliaryTopLeftArea: rect(x: 0, y: 948, width: 640, height: 34),
            isBuiltIn: true
        )
        let overlappingAreas = try NotchDisplayDescriptor(
            displayID: DisplayID(1),
            frame: rect(x: 0, y: 0, width: 1512, height: 982),
            safeAreaInsets: NotchSafeAreaInsets(top: 34),
            auxiliaryTopLeftArea: rect(x: 0, y: 948, width: 760, height: 34),
            auxiliaryTopRightArea: rect(x: 740, y: 948, width: 772, height: 34),
            isBuiltIn: true
        )

        #expect(NotchGeometry.resolve(from: missingRightArea) == nil)
        #expect(NotchGeometry.resolve(from: overlappingAreas) == nil)
    }

    @Test("selector prefers notch geometry when available")
    func selectorPrefersNotchGeometryWhenAvailable() throws {
        let externalNotchedDisplay = try builtInNotchedDisplay(displayID: DisplayID(2), isBuiltIn: false)
        let builtInDisplay = try builtInNotchedDisplay(displayID: DisplayID(1))

        let selection = RecordingSurfaceSelector.select(from: [externalNotchedDisplay, builtInDisplay])

        if case .notch(let geometry) = selection {
            #expect(geometry.displayID == DisplayID(1))
        } else {
            Issue.record("Expected notch surface selection")
        }
    }

    @Test("selector falls back to HUD when notch is disabled or unavailable")
    func selectorFallsBackToHUD() throws {
        let display = try builtInNotchedDisplay()

        #expect(
            RecordingSurfaceSelector.select(
                from: [display],
                preferences: NotchSurfacePreferences(isEnabled: false)
            ) == .floatingHUD(.notchDisabled)
        )
        #expect(
            RecordingSurfaceSelector.select(from: []) == .floatingHUD(.noNotchedDisplay)
        )
    }

    @Test("selector can suppress the floating HUD fallback")
    func selectorCanSuppressFloatingHUDFallback() throws {
        let selection = RecordingSurfaceSelector.select(
            from: [],
            preferences: NotchSurfacePreferences(fallbackToFloatingHUDWhenUnavailable: false)
        )

        #expect(selection == .menuBarOnly(.noNotchedDisplay))
    }

    @Test("rects and insets validate finite positive geometry")
    func rectsAndInsetsValidateFinitePositiveGeometry() {
        #expect(throws: NotchGeometryError.invalidRect) {
            _ = try NotchScreenRect(x: 0, y: 0, width: 0, height: 34)
        }
        #expect(throws: NotchGeometryError.invalidRect) {
            _ = try NotchScreenRect(x: .nan, y: 0, width: 100, height: 34)
        }
        #expect(throws: NotchGeometryError.invalidInsets) {
            _ = try NotchSafeAreaInsets(top: -1)
        }
    }

    private func builtInNotchedDisplay(
        displayID: DisplayID = DisplayID(1),
        safeAreaTopInset: Double = 34,
        isBuiltIn: Bool = true,
        isVisible: Bool = true
    ) throws -> NotchDisplayDescriptor {
        try NotchDisplayDescriptor(
            displayID: displayID,
            frame: rect(x: 0, y: 0, width: 1512, height: 982),
            safeAreaInsets: NotchSafeAreaInsets(top: safeAreaTopInset),
            auxiliaryTopLeftArea: rect(x: 0, y: 948, width: 640, height: 34),
            auxiliaryTopRightArea: rect(x: 872, y: 948, width: 640, height: 34),
            isBuiltIn: isBuiltIn,
            isVisible: isVisible
        )
    }

    private func rect(
        x: Double,
        y: Double,
        width: Double,
        height: Double
    ) throws -> NotchScreenRect {
        try NotchScreenRect(x: x, y: y, width: width, height: height)
    }
}
