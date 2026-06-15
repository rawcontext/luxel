#!/usr/bin/env swift

import AppKit
import Foundation

enum IconGenerationError: Error {
    case missingOutputPath
    case failedToRenderPNG
}

guard let outputPath = CommandLine.arguments.dropFirst().first else {
    throw IconGenerationError.missingOutputPath
}

let canvas: CGFloat = 1024
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvas),
    pixelsHigh: Int(canvas),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    throw IconGenerationError.failedToRenderPNG
}

bitmap.size = NSSize(width: canvas, height: canvas)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

let bounds = NSRect(x: 0, y: 0, width: canvas, height: canvas)
NSColor.clear.setFill()
bounds.fill()

let iconRect = bounds.insetBy(dx: 64, dy: 64)
let iconPath = NSBezierPath(roundedRect: iconRect, xRadius: 216, yRadius: 216)
let gradient = NSGradient(colorsAndLocations:
    (NSColor(calibratedRed: 0.04, green: 0.07, blue: 0.10, alpha: 1), 0.0),
    (NSColor(calibratedRed: 0.00, green: 0.48, blue: 0.56, alpha: 1), 0.58),
    (NSColor(calibratedRed: 0.97, green: 0.76, blue: 0.28, alpha: 1), 1.0)
)!
gradient.draw(in: iconPath, angle: -38)

let insetPath = NSBezierPath(roundedRect: iconRect.insetBy(dx: 92, dy: 92), xRadius: 132, yRadius: 132)
NSColor.white.withAlphaComponent(0.13).setFill()
insetPath.fill()

let letter = "L" as NSString
let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 520, weight: .black),
    .foregroundColor: NSColor.white,
    .paragraphStyle: paragraph
]
let letterSize = letter.size(withAttributes: attributes)
let letterOrigin = NSPoint(
    x: (canvas - letterSize.width) / 2,
    y: (canvas - letterSize.height) / 2 + 16
)
letter.draw(at: letterOrigin, withAttributes: attributes)

let dotRect = NSRect(x: 674, y: 264, width: 108, height: 108)
NSColor(calibratedRed: 1.0, green: 0.34, blue: 0.28, alpha: 1).setFill()
NSBezierPath(ovalIn: dotRect).fill()

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    throw IconGenerationError.failedToRenderPNG
}

let outputURL = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try png.write(to: outputURL)
