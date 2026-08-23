#!/usr/bin/env swift
import AppKit
import CryptoKit
import Foundation

private let requiredLocales = [
    "en-US", "de-DE", "es-ES", "fr-FR", "it", "ja", "ko", "vi", "zh-Hans", "pt-BR", "pt-PT"
]
private let expectedWidth = 2_880
private let expectedHeight = 1_800

private struct Configuration: Decodable {
    let screenshots: [Screenshot]
    let locales: [String: [String: String]]
}

private struct Screenshot: Decodable {
    let id: String
    let position: Int
    let source: String
    let outputStem: String
    let anchorTop: Int
    let anchorBottom: Int
    let textCenterY: Double
    let baseFontSize: Double
    let maxWidth: Double
    let textColor: String
}

private struct Manifest: Encodable {
    let schemaVersion = 1
    let width = expectedWidth
    let height = expectedHeight
    let locales: [String]
    let files: [ManifestFile]
}

private struct ManifestFile: Encodable {
    let locale: String
    let position: Int
    let id: String
    let source: String
    let output: String
    let heading: String
    let sha256: String
    let bytes: Int
}

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("Localized screenshot error: \(message)\n".utf8))
    exit(1)
}

private func argument(after name: String) -> String {
    guard let index = CommandLine.arguments.firstIndex(of: name), index + 1 < CommandLine.arguments.count else {
        fail("Missing required \(name) argument")
    }
    return CommandLine.arguments[index + 1]
}

private func parseColor(_ value: String) -> NSColor {
    let hex = value.hasPrefix("#") ? String(value.dropFirst()) : value
    guard hex.count == 6, let number = Int(hex, radix: 16) else {
        fail("Invalid sRGB color \(value)")
    }
    return NSColor(
        srgbRed: CGFloat((number >> 16) & 0xFF) / 255,
        green: CGFloat((number >> 8) & 0xFF) / 255,
        blue: CGFloat(number & 0xFF) / 255,
        alpha: 1
    )
}

private func clearEnglishHeading(_ image: NSBitmapImageRep, screenshot: Screenshot) {
    guard screenshot.anchorTop >= 0,
        screenshot.anchorBottom < image.pixelsHigh,
        screenshot.anchorTop < screenshot.anchorBottom
    else {
        fail("Invalid heading background anchors for \(screenshot.id)")
    }

    guard image.bitsPerSample == 8,
        image.samplesPerPixel == 4,
        image.bitsPerPixel == 32,
        !image.isPlanar,
        let pixels = image.bitmapData
    else {
        fail("Expected a non-planar 8-bit RGBA screenshot for \(screenshot.id)")
    }

    let topRow = screenshot.anchorTop
    let bottomRow = screenshot.anchorBottom
    let bandHeight = screenshot.anchorBottom - screenshot.anchorTop
    for topY in (screenshot.anchorTop + 1)..<screenshot.anchorBottom {
        let progress = Double(topY - screenshot.anchorTop) / Double(bandHeight)
        let targetOffset = topY * image.bytesPerRow
        let topOffset = topRow * image.bytesPerRow
        let bottomOffset = bottomRow * image.bytesPerRow
        for byte in 0..<(image.pixelsWide * 4) {
            let start = Double(pixels[topOffset + byte])
            let end = Double(pixels[bottomOffset + byte])
            pixels[targetOffset + byte] = UInt8((start + ((end - start) * progress)).rounded())
        }
    }
}

private func drawHeading(_ heading: String, on image: NSBitmapImageRep, screenshot: Screenshot) {
    let text = heading as NSString
    var fontSize = CGFloat(screenshot.baseFontSize)
    var font = NSFont.systemFont(ofSize: fontSize, weight: .ultraLight)
    var attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: parseColor(screenshot.textColor)
    ]
    var bounds = text.boundingRect(
        with: NSSize(width: 5_000, height: 500),
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        attributes: attributes
    )
    if bounds.width > screenshot.maxWidth {
        fontSize *= CGFloat(screenshot.maxWidth / bounds.width)
        font = NSFont.systemFont(ofSize: fontSize, weight: .ultraLight)
        attributes[.font] = font
        bounds = text.boundingRect(
            with: NSSize(width: 5_000, height: 500),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
    }
    guard fontSize >= 92, bounds.width <= screenshot.maxWidth + 1 else {
        fail("Localized heading does not fit \(screenshot.id): \(heading)")
    }

    guard let context = NSGraphicsContext(bitmapImageRep: image) else {
        fail("Could not create drawing context for \(screenshot.id)")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.shouldAntialias = true
    context.imageInterpolation = .high
    let horizontalOffset = (CGFloat(image.pixelsWide) - bounds.width) / 2
    let top = CGFloat(screenshot.textCenterY) - bounds.height / 2
    let verticalOffset = CGFloat(image.pixelsHigh) - top - bounds.height
    text.draw(
        in: NSRect(x: horizontalOffset, y: verticalOffset, width: bounds.width + 2, height: bounds.height + 2),
        withAttributes: attributes
    )
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
}

private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func normalizedImage(from data: Data) -> NSBitmapImageRep {
    guard let source = NSImage(data: data),
        let image = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: expectedWidth,
            pixelsHigh: expectedHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ),
        let context = NSGraphicsContext(bitmapImageRep: image)
    else {
        fail("Could not normalize screenshot into an sRGB bitmap")
    }
    image.size = NSSize(width: expectedWidth, height: expectedHeight)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = NSImageInterpolation.high
    source.draw(
        in: NSRect(x: 0, y: 0, width: expectedWidth, height: expectedHeight),
        from: .zero,
        operation: .copy,
        fraction: 1
    )
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return image
}

let fileManager = FileManager.default
let repositoryRoot = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
let configPath =
    CommandLine.arguments.contains("--config")
    ? argument(after: "--config")
    : "docs/ux/app-store/localized-screenshot-headings.json"
let outputPath = argument(after: "--output")
let manifestPath = argument(after: "--manifest")
let configURL = URL(fileURLWithPath: configPath, relativeTo: repositoryRoot).standardizedFileURL
let outputURL = URL(fileURLWithPath: outputPath, relativeTo: repositoryRoot).standardizedFileURL
let manifestURL = URL(fileURLWithPath: manifestPath, relativeTo: repositoryRoot).standardizedFileURL

private let configuration = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: configURL))
guard configuration.locales.keys.sorted() == requiredLocales.sorted() else {
    fail("Locale set must exactly match \(requiredLocales.joined(separator: ", "))")
}
let screenshotIDs = Set(configuration.screenshots.map(\.id))
guard configuration.screenshots.count == 6,
    screenshotIDs.count == 6,
    configuration.screenshots.map(\.position).sorted() == [1, 2, 3, 4, 5, 6]
else {
    fail("Screenshot configuration must define six unique ordered images")
}
for locale in requiredLocales {
    guard let headings = configuration.locales[locale], Set(headings.keys) == screenshotIDs else {
        fail("Locale \(locale) must define every screenshot heading exactly once")
    }
    if locale != "en-US" {
        guard headings.values.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
            headings != configuration.locales["en-US"]
        else {
            fail("Locale \(locale) contains empty or fallback English headings")
        }
    }
}

if fileManager.fileExists(atPath: outputURL.path) {
    let existing = try fileManager.contentsOfDirectory(atPath: outputURL.path)
    guard existing.isEmpty else {
        fail("Output directory must be empty: \(outputURL.path)")
    }
} else {
    try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)
}

private var manifestFiles = [ManifestFile]()
for locale in requiredLocales {
    let localeURL = outputURL.appendingPathComponent(locale, isDirectory: true)
    try fileManager.createDirectory(at: localeURL, withIntermediateDirectories: true)
}

for screenshot in configuration.screenshots.sorted(by: { $0.position < $1.position }) {
    let sourceURL = repositoryRoot.appendingPathComponent(screenshot.source).standardizedFileURL
    let sourceData = try Data(contentsOf: sourceURL)
    guard let sourceImage = NSBitmapImageRep(data: sourceData),
        sourceImage.pixelsWide == expectedWidth,
        sourceImage.pixelsHigh == expectedHeight,
        !sourceImage.hasAlpha
    else {
        fail("Source must be a 2880x1800 image without alpha: \(screenshot.source)")
    }
    let clearedImage = normalizedImage(from: sourceData)
    clearEnglishHeading(clearedImage, screenshot: screenshot)
    guard let clearedData = clearedImage.representation(using: .png, properties: [:]) else {
        fail("Could not create cleared screenshot base for \(screenshot.id)")
    }

    for locale in requiredLocales {
        let localeURL = outputURL.appendingPathComponent(locale, isDirectory: true)
        let headings = configuration.locales[locale]!
        let outputName: String
        let outputData: Data
        if locale == "en-US" {
            outputName = String(format: "%02d-%@.png", screenshot.position, screenshot.outputStem)
            outputData = sourceData
        } else {
            let image = normalizedImage(from: clearedData)
            drawHeading(headings[screenshot.id]!, on: image, screenshot: screenshot)
            guard let jpeg = image.representation(using: .jpeg, properties: [.compressionFactor: 0.96]) else {
                fail("Could not encode localized screenshot for \(locale)/\(screenshot.id)")
            }
            outputName = String(format: "%02d-%@.jpg", screenshot.position, screenshot.outputStem)
            outputData = jpeg
        }

        let destination = localeURL.appendingPathComponent(outputName)
        try outputData.write(to: destination, options: .atomic)
        guard let outputImage = NSBitmapImageRep(data: outputData),
            outputImage.pixelsWide == expectedWidth,
            outputImage.pixelsHigh == expectedHeight,
            !outputImage.hasAlpha
        else {
            fail("Generated screenshot failed App Store image validation: \(destination.path)")
        }
        manifestFiles.append(
            ManifestFile(
                locale: locale,
                position: screenshot.position,
                id: screenshot.id,
                source: screenshot.source,
                output: "\(locale)/\(outputName)",
                heading: headings[screenshot.id]!,
                sha256: sha256(outputData),
                bytes: outputData.count
            )
        )
    }
}

private let manifest = Manifest(locales: requiredLocales, files: manifestFiles)
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
print("Rendered \(manifestFiles.count) App Store screenshots across \(requiredLocales.count) locales.")
print("Screenshots: \(outputURL.path)")
print("Manifest: \(manifestURL.path)")
