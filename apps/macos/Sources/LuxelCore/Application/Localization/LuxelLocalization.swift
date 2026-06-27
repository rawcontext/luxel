import Foundation

public enum LuxelLocalization {
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
            bundle: .atURL(Bundle.module.bundleURL)
        )
    }

    public static func string(_ key: String, defaultValue: String) -> String {
        NSLocalizedString(key, bundle: .module, value: defaultValue, comment: "")
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
}
