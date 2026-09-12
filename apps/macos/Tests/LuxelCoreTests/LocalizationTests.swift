import Foundation
import LuxelCore
import LuxelTestSupport
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
            let expected = (intentionalEnglishFallbackKeys[locale] ?? [])
                .union(sharedSpellingKeys[locale] ?? [])

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
            #"(?:(?:Text|Button|Label|Toggle|Picker|TextField|SecureField|Link|Menu|Section)\(\s*")"#
                + #"([^"\\]*(?:\\.[^"\\]*)*)""#,
            #"\.(?:help|accessibilityLabel|accessibilityValue|accessibilityHint)\(\s*"([^"\\]*(?:\\.[^"\\]*)*)""#,
            #"(?:(?:LocalizedStringResource|IntentDescription)\(\s*")([^"\\]*(?:\\.[^"\\]*)*)""#,
            #"(?:title|shortTitle):\s*"([^"\\]*(?:\\.[^"\\]*)*)""#,
            #"LuxelLocalization\.(?:string|format)\(\s*"([^"\\]*(?:\\.[^"\\]*)*)""#,
            #"(?:LocalizedStringResource|TypeDisplayRepresentation)\s*=\s*"([^"\\]*(?:\\.[^"\\]*)*)""#,
            #"(?:controlRow|timelineSliderRow|metadataField|editorDisclosureCard|SettingsRow|"#
                + #"LuxelGlassSectionHeader|LuxelGlassSectionFooter|SettingsCapsuleButtonLabel|"#
                + #"integerStepperField|doubleStepperField)\(\s*"([^"\\]*(?:\\.[^"\\]*)*)""#
        ]
        let patterns = try patternSources.map { try NSRegularExpression(pattern: $0) }

        var missing: [String] = []
        for root in sourceRoots {
            for fileURL in swiftFiles(under: packageRoot.appending(path: root)) {
                let source = try String(contentsOf: fileURL, encoding: .utf8)
                let range = NSRange(source.startIndex..<source.endIndex, in: source)
                let factoryPatterns = try localizationFactoryPatterns(for: fileURL.lastPathComponent)
                for pattern in patterns + factoryPatterns {
                    for match in pattern.matches(in: source, range: range) {
                        guard let matchRange = Range(match.range(at: 1), in: source) else {
                            continue
                        }

                        let key = String(source[matchRange])
                            .replacingOccurrences(of: #"\n"#, with: "\n")
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

    @Test("App Shortcut phrases are manually localized for every supported language")
    func shortcutPhrasesHaveCompleteLocalizations() throws {
        let source = try String(
            contentsOf: packageRoot.appending(path: "Sources/LuxelApp/Shortcuts/LuxelAutomationAppIntents.swift"),
            encoding: .utf8)
        let pattern = try NSRegularExpression(pattern: #""([^"\n]*\\\(\.applicationName\)[^"\n]*)""#)
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        let keys = Set(
            pattern.matches(in: source, range: range).compactMap { match -> String? in
                guard let range = Range(match.range(at: 1), in: source) else { return nil }
                return String(source[range]).replacingOccurrences(
                    of: #"\(.applicationName)"#, with: "${applicationName}")
            })
        #expect(keys.count == 10)
        for locale in LuxelLocalization.supportedLocales {
            let path = "Configuration/Luxel/Localizations/\(locale).lproj/AppShortcuts.strings"
            let data = try Data(contentsOf: packageRoot.appending(path: path))
            let phrases = try #require(
                PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
            #expect(Set(phrases.keys) == keys)
            for (key, phrase) in phrases {
                #expect(!phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                #expect(phrase.components(separatedBy: "${applicationName}").count == 2)
                if locale != "en" { #expect(phrase != key) }
            }
        }
    }
}

private func localizationFactoryPatterns(for fileName: String) throws -> [NSRegularExpression] {
    let pattern: String? =
        switch fileName {
        case "LuxelEditorNativeMenuController.swift":
            #"(?:item\(|menu\(named:)\s*"([^"\\]*(?:\\.[^"\\]*)*)""#
        case "NotchActivityPresentation.swift":
            #"action\([^,\n]+,\s*"([^"\\]*(?:\\.[^"\\]*)*)""#
        case "AppKeyboardShortcut.swift":
            #"systemConflict\([^,\n]+,\s*action:\s*"([^"\\]*(?:\\.[^"\\]*)*)""#
        case "LuxelSettingsView+Support.swift":
            #"(?:detail|group):\s*"([^"\\]*(?:\\.[^"\\]*)*)""#
        default: nil
        }
    return try pattern.map { [try NSRegularExpression(pattern: $0)] } ?? []
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

private let packageRoot = testSourceFileURL()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private let nonLocalizedLiteralAllowlist: Set<String> = [
    "", " ", "luxel.media", "h:mm:ss"
]

private let sharedSpellingKeys: [String: Set<String>] = [
    "de": [
        "Alpha", "App", "Audio %@", "Beta", "Diffusion", "Editor", "Notch", "OK",
        "Original", "Position", "Start", "Status", "System", "Version", "Version %@", "%.1f s", "%d min"
    ],
    "es": ["App", "Audio %@", "Beta", "Editor", "Error", "No", "Original", "%.1f s", "%d min"],
    "fr": [
        "Alpha", "App", "Audio %@", "Diffusion", "Dimensions", "Exact", "OK", "Original",
        "Position", "Stable", "Type", "Version", "Version %@", "%.1f s", "%d min"
    ],
    "it": [
        "App", "Area", "Audio %@", "Beta", "Buffer %@", "Continuity", "Editor", "File", "No",
        "Notch", "OK", "Timeline", "%.1f s", "%d min"
    ],
    "ja": ["OK"],
    "vi": ["Alpha", "Beta", "OK"],
    "zh-Hans": ["App"],
    "pt-BR": ["App", "Beta", "Buffer %@", "Editor", "OK", "Original", "Status", "%.1f s", "%d min"],
    "pt-PT": ["Beta", "Editor", "OK", "Original", "%.1f s", "%d min"]
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
