import FirebaseCore
import FirebaseCrashlytics
import Foundation
import LuxelCore

@MainActor
final class LuxelCrashReporter: ErrorReporter {
    static let shared = LuxelCrashReporter()

    private var isConfigured = false

    private init() {}

    func configure(bundle: Bundle = .main, appMetadata: AppMetadata) {
        guard !isConfigured else {
            return
        }

        if FirebaseApp.app() == nil {
            guard
                let optionsPath = bundle.path(forResource: "GoogleService-Info", ofType: "plist"),
                let options = FirebaseOptions(contentsOfFile: optionsPath)
            else {
                return
            }

            FirebaseApp.configure(options: options)
        }

        isConfigured = FirebaseApp.app() != nil

        guard isConfigured else {
            return
        }

        let crashlytics = Crashlytics.crashlytics()
        crashlytics.setCustomValue(appMetadata.displayName, forKey: "app_name")
        crashlytics.setCustomValue(appMetadata.version, forKey: "app_version")
        crashlytics.setCustomValue(appMetadata.build, forKey: "app_build")
    }

    func record(_ error: any Error, context: String) {
        guard isConfigured else {
            return
        }

        Crashlytics.crashlytics().record(
            error: error,
            userInfo: [
                "context": context
            ])
    }
}
