import LuxelCore

@MainActor
extension LuxelMenuModel {
    func refreshNotchDisplays() {
        notchDisplays = notchDisplayProvider.displays()
    }

    func watchNotchDisplayUpdates() async {
        for await displays in notchDisplayProvider.displayUpdates {
            notchDisplays = displays
        }
    }

    var notchSurfaceStatusPresentation: NotchSurfaceStatusPresentation {
        NotchSurfaceStatusPresentation(
            displays: notchDisplays,
            preferences: settings.notchSurfacePreferences
        )
    }
}
