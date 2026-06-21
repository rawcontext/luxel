import AppKit
import LuxelCore

extension LuxelStatusItemController {
    func symbolImage(named name: String, accessibilityLabel: String) -> NSImage? {
        guard
            let baseImage = NSImage(systemSymbolName: name, accessibilityDescription: accessibilityLabel)
        else {
            return nil
        }

        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let image = baseImage.withSymbolConfiguration(configuration) ?? baseImage
        image.isTemplate = true
        image.size = iconSize
        return image
    }

    func makeActiveRecordingFrame(
        elapsedText: String,
        audioLevel: AudioLevelSample
    ) -> NSImage {
        let width = activeStatusItemWidth(elapsedText: elapsedText)
        let size = NSSize(width: width, height: activeIconHeight)
        let image = NSImage(size: size)
        image.lockFocus()

        drawActiveRecordingFrame(
            in: NSRect(origin: .zero, size: size),
            elapsedText: elapsedText,
            audioLevel: audioLevel
        )

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    func countdownStatusItemWidth(countdownText: String) -> CGFloat {
        let textWidth = ceil(countdownAttributedText(countdownText).size().width)
        return max(NSStatusItem.squareLength, textWidth + 12)
    }

    func countdownTextImage(text: String, accessibilityLabel: String) -> NSImage {
        let width = countdownStatusItemWidth(countdownText: text)
        let size = NSSize(width: width, height: iconSize.height)
        let image = NSImage(size: size)
        image.accessibilityDescription = accessibilityLabel
        image.lockFocus()

        let attributedText = countdownAttributedText(text)
        let textSize = attributedText.size()
        attributedText.draw(
            at: NSPoint(
                x: (width - textSize.width) / 2,
                y: (iconSize.height - textSize.height) / 2
            ))

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    func activeStatusItemWidth(elapsedText: String) -> CGFloat {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        let text = NSAttributedString(
            string: elapsedText,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.white.withAlphaComponent(0.9)
            ]
        )
        let textWidth = elapsedText.isEmpty ? 0 : ceil(text.size().width)
        let waveformWidth: CGFloat = 46
        let contentWidth = 12 + 11 + 12 + waveformWidth + 12 + textWidth + 14 + 11 + 12
        return max(activeIconMinWidth, contentWidth)
    }

    private func countdownAttributedText(_ text: String) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor.black
            ]
        )
    }

    private func drawActiveRecordingFrame(
        in rect: NSRect,
        elapsedText: String,
        audioLevel: AudioLevelSample
    ) {
        let width = rect.width
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        let text = NSAttributedString(
            string: elapsedText,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.white.withAlphaComponent(0.9)
            ]
        )
        let waveformWidth: CGFloat = 46

        NSColor.black.withAlphaComponent(0.82).setFill()
        NSBezierPath(
            roundedRect: NSRect(x: 1, y: 1, width: width - 2, height: activeIconHeight - 2),
            xRadius: activeIconHeight / 2,
            yRadius: activeIconHeight / 2
        ).fill()

        NSColor.white.withAlphaComponent(0.18).setStroke()
        let strokePath = NSBezierPath(
            roundedRect: NSRect(x: 1.5, y: 1.5, width: width - 3, height: activeIconHeight - 3),
            xRadius: (activeIconHeight - 3) / 2,
            yRadius: (activeIconHeight - 3) / 2
        )
        strokePath.lineWidth = 1
        strokePath.stroke()

        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: NSRect(x: 12, y: 6.5, width: 11, height: 11)).fill()

        drawWaveform(
            in: NSRect(x: 35, y: 4, width: waveformWidth, height: 16),
            audioLevel: audioLevel
        )

        if !elapsedText.isEmpty {
            text.draw(at: NSPoint(x: 93, y: 4.5))
        }

        NSColor.white.withAlphaComponent(0.86).setFill()
        NSBezierPath(
            roundedRect: NSRect(x: width - 23, y: 7, width: 10, height: 10),
            xRadius: 2,
            yRadius: 2
        ).fill()
    }

    private func drawWaveform(
        in rect: NSRect,
        audioLevel: AudioLevelSample
    ) {
        let bars: [CGFloat] = [
            0.30, 0.72, 0.42, 0.88, 0.56, 0.78, 0.34,
            0.64, 0.92, 0.50, 0.76, 0.44, 0.70, 0.36
        ]
        let level = min(1, max(CGFloat(audioLevel.rms), CGFloat(audioLevel.peak)))
        let barWidth: CGFloat = 2
        let step = rect.width / CGFloat(bars.count)

        for (index, bar) in bars.enumerated() {
            let height = max(2, rect.height * min(1, bar * (0.2 + level)))
            let barX = rect.minX + (CGFloat(index) * step) + ((step - barWidth) / 2)
            let barY = rect.midY - (height / 2)

            if index < 6 {
                NSColor.systemRed.withAlphaComponent(0.95).setFill()
            } else {
                NSColor.white.withAlphaComponent(0.76).setFill()
            }

            NSBezierPath(
                roundedRect: NSRect(x: barX, y: barY, width: barWidth, height: height),
                xRadius: 1,
                yRadius: 1
            ).fill()
        }
    }
}
