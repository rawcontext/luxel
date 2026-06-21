public struct NotchSurfaceStatusPresentation: Equatable, Sendable {
    public let statusText: String
    public let detailText: String
    public let selection: RecordingSurfaceSelection
    public let showsStatus: Bool

    public init(
        displays: [NotchDisplayDescriptor],
        preferences: NotchSurfacePreferences = .defaults
    ) {
        let selection = RecordingSurfaceSelector.select(
            from: displays,
            preferences: preferences
        )

        self.selection = selection

        switch selection {
        case .notch:
            showsStatus = false
            statusText = "Notch Available"
            detailText = "Luxel can use the built-in notch display."
        case .floatingHUD(.notchDisabled):
            showsStatus = true
            statusText = "Floating HUD Fallback"
            detailText =
                "The notch surface is disabled, so recording controls will use the fallback surface."
        case .floatingHUD(.noNotchedDisplay):
            showsStatus = true
            statusText = "Floating HUD Fallback"
            detailText = "No built-in notched display is currently detected."
        case .menuBarOnly(.notchDisabled):
            showsStatus = true
            statusText = "Menu Bar Only"
            detailText = "The notch surface and floating HUD fallback are disabled."
        case .menuBarOnly(.noNotchedDisplay):
            showsStatus = true
            statusText = "Menu Bar Only"
            detailText = "No built-in notched display is detected, and floating HUD fallback is off."
        }
    }
}
