import Foundation
import LuxelCore
import Testing

@Suite("Localization")
struct LocalizationTests {
    @Test("string catalog includes every supported locale for every key")
    func stringCatalogHasCompleteLocales() throws {
        let catalog = try StringCatalog.load(from: packageRoot)

        #expect(catalog.sourceLanguage == "en")
        #expect(Set(LuxelLocalization.supportedLocales).isSubset(of: catalog.availableLocales))

        for key in catalog.strings.keys.sorted() {
            let missing = Set(LuxelLocalization.supportedLocales)
                .subtracting(catalog.locales(forKey: key))
            #expect(missing.isEmpty, "Missing localizations for \(key): \(missing.sorted())")
        }
    }

    @Test("string catalog entries are translated and preserve format placeholders")
    func stringCatalogEntriesAreReadyForRelease() throws {
        let catalog = try StringCatalog.load(from: packageRoot)

        for key in catalog.strings.keys.sorted() {
            let sourceUnit = try #require(catalog.stringUnit(forKey: key, locale: "en"))
            let sourcePlaceholders = try formatPlaceholders(in: sourceUnit.value)

            for locale in LuxelLocalization.supportedLocales {
                let unit = try #require(catalog.stringUnit(forKey: key, locale: locale))
                let value = unit.value.trimmingCharacters(in: .whitespacesAndNewlines)

                #expect(unit.state == "translated", "\(key) is not marked translated for \(locale)")
                #expect(!value.isEmpty, "\(key) is empty for \(locale)")
                #expect(
                    try formatPlaceholders(in: unit.value) == sourcePlaceholders,
                    "\(key) has mismatched format placeholders for \(locale)"
                )
            }
        }
    }

    @Test("non-English catalog entries do not silently fall back to English")
    func stringCatalogHasNoUnexpectedEnglishFallbacks() throws {
        let catalog = try StringCatalog.load(from: packageRoot)

        for locale in LuxelLocalization.supportedLocales where locale != "en" {
            let fallbackKeys = Set(
                try catalog.strings.keys.compactMap { key in
                    let source = try #require(catalog.stringUnit(forKey: key, locale: "en"))
                    let localized = try #require(catalog.stringUnit(forKey: key, locale: locale))
                    return source.value == localized.value ? key : nil
                }
            )
            let expected = intentionalEnglishFallbackKeys[locale] ?? []

            #expect(
                fallbackKeys == expected,
                "Unexpected English fallbacks for \(locale): \(fallbackKeys.subtracting(expected).sorted())"
            )
        }
    }

    @Test("InfoPlist strings include TCC descriptions for every supported locale")
    func infoPlistStringsHaveRequiredKeys() throws {
        let requiredKeys = [
            "CFBundleDisplayName",
            "CFBundleName",
            "NSCameraUsageDescription",
            "NSMicrophoneUsageDescription",
            "NSScreenCaptureUsageDescription",
            "NSSpeechRecognitionUsageDescription",
            "NSHumanReadableCopyright"
        ]

        let localizationsURL =
            packageRoot
            .appending(path: "Configuration/Luxel/Localizations")
        let englishData = try Data(
            contentsOf:
                localizationsURL
                .appending(path: "en.lproj")
                .appending(path: "InfoPlist.strings")
        )
        let englishPlist = try #require(
            PropertyListSerialization.propertyList(
                from: englishData,
                format: nil
            ) as? [String: String]
        )

        for locale in LuxelLocalization.supportedLocales {
            let fileURL =
                localizationsURL
                .appending(path: "\(locale).lproj")
                .appending(path: "InfoPlist.strings")
            let data = try Data(contentsOf: fileURL)
            let plist =
                try PropertyListSerialization.propertyList(
                    from: data,
                    format: nil
                ) as? [String: String]

            #expect(plist != nil, "\(fileURL.path) should parse as a strings file")
            for key in requiredKeys {
                let value = plist?[key]?.trimmingCharacters(in: .whitespacesAndNewlines)
                #expect(value?.isEmpty == false, "\(fileURL.path) is missing \(key)")
            }

            if locale != "en" {
                for key in requiredKeys where !infoPlistEnglishFallbackKeys.contains(key) {
                    #expect(
                        plist?[key] != englishPlist[key],
                        "\(fileURL.path) falls back to English for \(key)"
                    )
                }
            }
        }
    }

    @Test("common user-facing literal APIs are covered by the catalog")
    func userFacingLiteralAPIsAreCataloged() throws {
        let catalog = try StringCatalog.load(from: packageRoot)
        let sourceRoots = [
            "Sources/LuxelApp",
            "Sources/LuxelPresentation",
            "Sources/LuxelCore"
        ]
        let patternSources = [
            #"(?:(?:Text|Button|Label|Toggle|Picker)\(\s*")([^"\\]*(?:\\.[^"\\]*)*)""#,
            #"\.(?:help|accessibilityLabel|accessibilityValue|accessibilityHint)\(\s*"([^"\\]*(?:\\.[^"\\]*)*)""#,
            #"(?:(?:LocalizedStringResource|IntentDescription)\(\s*")([^"\\]*(?:\\.[^"\\]*)*)""#,
            #"(?:title|shortTitle):\s*"([^"\\]*(?:\\.[^"\\]*)*)""#
        ]
        let patterns = try patternSources.map { try NSRegularExpression(pattern: $0) }

        var missing: [String] = []
        for root in sourceRoots {
            for fileURL in swiftFiles(under: packageRoot.appending(path: root)) {
                let source = try String(contentsOf: fileURL, encoding: .utf8)
                let range = NSRange(source.startIndex..<source.endIndex, in: source)
                for pattern in patterns {
                    for match in pattern.matches(in: source, range: range) {
                        guard let matchRange = Range(match.range(at: 1), in: source) else {
                            continue
                        }

                        let key = String(source[matchRange])
                        guard !key.contains(#"\("#),
                            !nonLocalizedLiteralAllowlist.contains(key),
                            !catalog.strings.keys.contains(key)
                        else {
                            continue
                        }

                        missing.append("\(relativePath(fileURL)) -> \(key)")
                    }
                }
            }
        }

        #expect(missing.isEmpty, "Missing catalog keys:\n\(missing.joined(separator: "\n"))")
    }

    @Test("localization lookup prefers packaged app resource bundle")
    func localizationLookupPrefersPackagedAppResourceBundle() throws {
        let sourceURL =
            packageRoot
            .appending(path: "Sources/LuxelCore/Application/Localization/LuxelLocalization.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("Contents/Resources"))
        #expect(source.contains("return .module"))
        #expect(LuxelLocalization.string("common.ok", defaultValue: "OK") == "OK")
    }
}

private struct StringCatalog: Decodable {
    let sourceLanguage: String
    let strings: [String: StringCatalogEntry]

    var availableLocales: Set<String> {
        Set(
            strings.values.flatMap { entry in
                entry.localizations.map { Array($0.keys) } ?? []
            })
    }

    static func load(from packageRoot: URL) throws -> StringCatalog {
        let url =
            packageRoot
            .appending(path: "Sources/LuxelCore/Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(StringCatalog.self, from: data)
    }

    func locales(forKey key: String) -> Set<String> {
        Set(
            strings[key]?.localizations?.compactMap { locale, localization in
                localization.stringUnit.value.isEmpty ? nil : locale
            } ?? [])
    }

    func stringUnit(forKey key: String, locale: String) -> StringCatalogStringUnit? {
        strings[key]?.localizations?[locale]?.stringUnit
    }
}

private struct StringCatalogEntry: Decodable {
    let localizations: [String: StringCatalogLocalization]?
}

private struct StringCatalogLocalization: Decodable {
    let stringUnit: StringCatalogStringUnit
}

private struct StringCatalogStringUnit: Decodable {
    let state: String
    let value: String
}

private let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private let nonLocalizedLiteralAllowlist: Set<String> = [
    " "
]

private let infoPlistEnglishFallbackKeys: Set<String> = [
    "CFBundleDisplayName",
    "CFBundleName"
]

private let intentionalEnglishFallbackKeys: [String: Set<String>] = [
    "de": [
        "10 s", "3 s", "30 s", "5 s", "Audio", "Countdown", "Dithering", "FPS", "Format",
        "Name", "Studio Voice", "common.ok", "recording.countdown.seconds",
        "replayBuffer.detail.durationFPS", "replayBuffer.duration.oneMinute", "⌫"
    ],
    "es": [
        "1 min", "10 s", "3 s", "30 s", "5 min", "5 s", "Audio", "FPS",
        "recording.countdown.seconds", "replayBuffer.detail.durationFPS", "⌫"
    ],
    "fr": [
        "1 min", "10 s", "3 s", "30 s", "5 min", "5 s", "Audio", "Destination", "Format",
        "Microphone", "Source", "common.ok", "recording.countdown.seconds",
        "settings.notifications.sidebar.title", "⌫"
    ],
    "it": [
        "1 min", "10 s", "3 s", "30 s", "5 min", "5 s", "Audio", "FPS", "Preset", "common.ok",
        "recording.countdown.seconds", "replayBuffer.detail.durationFPS", "⌫"
    ],
    "ja": ["FPS", "common.ok", "⌫"],
    "ko": ["FPS", "replayBuffer.detail.durationFPS", "⌫"],
    "vi": ["Camera", "FPS", "common.ok", "replayBuffer.detail.durationFPS", "⌫"],
    "zh-Hans": ["FPS", "replayBuffer.detail.durationFPS", "⌫"],
    "pt-BR": [
        "1 min", "10 s", "3 s", "30 s", "5 min", "5 s", "FPS", "common.ok",
        "recording.countdown.seconds", "replayBuffer.detail.durationFPS", "⌫"
    ],
    "pt-PT": [
        "1 min", "10 s", "3 s", "30 s", "5 min", "5 s", "FPS", "common.ok",
        "recording.countdown.seconds", "replayBuffer.detail.durationFPS", "⌫"
    ]
]

private func formatPlaceholders(in value: String) throws -> [String] {
    let pattern = try NSRegularExpression(pattern: #"%(?:\d+\$)?(?:@|d|%)"#)
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    return pattern.matches(in: value, range: range).compactMap { match in
        Range(match.range, in: value).map { String(value[$0]) }
    }.sorted()
}

private func swiftFiles(under root: URL) -> [URL] {
    guard
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
    else {
        return []
    }

    return enumerator.compactMap { item in
        guard let url = item as? URL, url.pathExtension == "swift" else {
            return nil
        }

        return url
    }
}

private func relativePath(_ url: URL) -> String {
    url.path.replacingOccurrences(of: packageRoot.path + "/", with: "")
}
