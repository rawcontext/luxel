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
}

private struct StringCatalog: Decodable {
    struct Entry: Decodable {
        struct Localization: Decodable {
            struct StringUnit: Decodable {
                let state: String
                let value: String
            }

            let stringUnit: StringUnit
        }

        let localizations: [String: Localization]?
    }

    let sourceLanguage: String
    let strings: [String: Entry]

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
}

private let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private let nonLocalizedLiteralAllowlist: Set<String> = [
    " "
]

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
