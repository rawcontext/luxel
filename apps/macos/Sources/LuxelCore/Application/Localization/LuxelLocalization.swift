import Foundation

public enum LuxelLocalization {
    private static let bundleName = "Luxel_LuxelCore.bundle"

    public static let supportedLocales = [
        "en",
        "de",
        "es",
        "fr",
        "it",
        "ja",
        "ko",
        "vi",
        "zh-Hans",
        "pt-BR",
        "pt-PT"
    ]

    public static func resource(
        _ key: StaticString,
        defaultValue: String.LocalizationValue
    ) -> LocalizedStringResource {
        LocalizedStringResource(
            key,
            defaultValue: defaultValue,
            bundle: .atURL(localizationBundle.bundleURL)
        )
    }

    public static func string(_ key: String, defaultValue: String) -> String {
        NSLocalizedString(key, bundle: localizationBundle, value: defaultValue, comment: "")
    }

    public static func string(_ key: String) -> String {
        string(key, defaultValue: key)
    }

    public static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: Locale.current, arguments: arguments)
    }

    public static func format(
        _ key: String,
        defaultValue: String,
        _ arguments: CVarArg...
    ) -> String {
        String(
            format: string(key, defaultValue: defaultValue),
            locale: Locale.current,
            arguments: arguments
        )
    }

    private static var localizationBundle: Bundle {
        let executableContentsURL =
            Bundle.main.executableURL?
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let candidates = [
            Bundle.main.resourceURL?.appending(path: bundleName),
            Bundle.main.bundleURL.appending(path: "Contents/Resources").appending(path: bundleName),
            executableContentsURL?.appending(path: "Resources").appending(path: bundleName)
        ]

        for candidate in candidates {
            guard let candidate, let bundle = Bundle(url: candidate) else {
                continue
            }

            return bundle
        }

        return .module
    }
}
