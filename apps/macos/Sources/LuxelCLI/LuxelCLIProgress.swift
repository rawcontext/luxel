import Darwin
import Foundation

public enum LuxelProgressBarRenderer {
    public static func line(label: String, progress: Double, width: Int = 28) -> String {
        let clampedProgress = min(max(progress, 0), 1)
        let filledWidth = Int((clampedProgress * Double(width)).rounded(.down))
        let emptyWidth = max(width - filledWidth, 0)
        let percent = Int((clampedProgress * 100).rounded())
        let bar =
            String(repeating: "#", count: filledWidth)
            + String(repeating: "-", count: emptyWidth)

        return "\(label) [\(bar)] \(String(format: "%3d", percent))%"
    }
}

final class LuxelTerminalProgressReporter: @unchecked Sendable {
    private let label: String
    private let isEnabled: Bool
    private let output: @Sendable (Data) -> Void
    private let lock = NSLock()
    private var lastRenderedPercent: Int?
    private var previousLineLength = 0
    private var hasRendered = false

    init(
        label: String,
        isEnabled: Bool = LuxelTerminalProgressReporter.defaultIsEnabled,
        output: @escaping @Sendable (Data) -> Void = { FileHandle.standardError.write($0) }
    ) {
        self.label = label
        self.isEnabled = isEnabled
        self.output = output
    }

    static var defaultIsEnabled: Bool {
        isatty(STDERR_FILENO) == 1
    }

    func start() {
        render(progress: 0, force: true)
    }

    func update(_ progress: Double) {
        render(progress: progress, force: false)
    }

    func finish() {
        render(progress: 1, force: true)
        writeLineBreakIfNeeded()
    }

    func fail() {
        writeLineBreakIfNeeded()
    }

    private func render(progress: Double, force: Bool) {
        guard isEnabled else {
            return
        }

        let clampedProgress = min(max(progress, 0), 1)
        let percent = Int((clampedProgress * 100).rounded())

        lock.lock()
        defer {
            lock.unlock()
        }

        guard force || percent != lastRenderedPercent else {
            return
        }

        let line = LuxelProgressBarRenderer.line(label: label, progress: clampedProgress)
        let padding = String(repeating: " ", count: max(previousLineLength - line.count, 0))
        output(Data("\r\(line)\(padding)".utf8))
        previousLineLength = line.count
        lastRenderedPercent = percent
        hasRendered = true
    }

    private func writeLineBreakIfNeeded() {
        guard isEnabled else {
            return
        }

        lock.lock()
        let shouldWriteLineBreak = hasRendered
        hasRendered = false
        lock.unlock()

        if shouldWriteLineBreak {
            output(Data("\n".utf8))
        }
    }
}
