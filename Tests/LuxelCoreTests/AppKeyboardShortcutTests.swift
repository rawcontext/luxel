import LuxelCore
import Testing

@Suite("App keyboard shortcut")
struct AppKeyboardShortcutTests {
    @Test("shortcut normalizes modifiers and key")
    func shortcutNormalizesModifiersAndKey() throws {
        let shortcut = try AppKeyboardShortcut(
            key: "R",
            modifiers: [.shift, .command, .shift]
        )

        #expect(shortcut.key == "r")
        #expect(shortcut.modifiers == [.command, .shift])
        #expect(shortcut.rawValue == "command+shift+r")
        #expect(shortcut.displayName == "Command Shift R")
    }

    @Test("raw value parser accepts valid shortcuts")
    func rawValueParserAcceptsValidShortcuts() throws {
        let shortcut = try #require(AppKeyboardShortcut(rawValue: " control + option + 5 "))

        #expect(shortcut == (try AppKeyboardShortcut(key: "5", modifiers: [.control, .option])))
        #expect(shortcut.rawValue == "control+option+5")
    }

    @Test("raw value parser rejects empty invalid or modifier-only strings")
    func rawValueParserRejectsInvalidStrings() {
        #expect(AppKeyboardShortcut(rawValue: "") == nil)
        #expect(AppKeyboardShortcut(rawValue: "command") == nil)
        #expect(AppKeyboardShortcut(rawValue: "command+invalid+r") == nil)
        #expect(AppKeyboardShortcut(rawValue: "command+shift+return") == nil)
    }

    @Test("constructor rejects missing modifiers and multi-character keys")
    func constructorRejectsInvalidShortcuts() {
        #expect(throws: AppKeyboardShortcutError.invalidShortcut) {
            _ = try AppKeyboardShortcut(key: "r", modifiers: [])
        }
        #expect(throws: AppKeyboardShortcutError.invalidShortcut) {
            _ = try AppKeyboardShortcut(key: "return", modifiers: [.command])
        }
    }

    @Test("capture presets expose native shortcut choices")
    func capturePresetsExposeNativeShortcutChoices() {
        #expect(AppKeyboardShortcutPresets.capture.map(\.rawValue) == [
            "command+control+option+r"
        ])
        #expect(AppKeyboardShortcutPresets.toggleRecording.map(\.rawValue) == [
            "command+control+option+t"
        ])
        #expect(AppKeyboardShortcutPresets.recordActiveWindow.map(\.rawValue) == [
            "command+control+option+shift+w"
        ])
        #expect(AppKeyboardShortcutPresets.recordFullscreen.map(\.rawValue) == [
            "command+control+option+shift+f"
        ])
        #expect(AppKeyboardShortcutPresets.audioOnlyRecording.map(\.rawValue) == [
            "command+control+option+a"
        ])
        #expect(AppKeyboardShortcutPresets.quickRecordLast.map(\.rawValue) == [
            "command+control+option+q"
        ])
        #expect(AppKeyboardShortcutPresets.captureScreenshot.map(\.rawValue) == [
            "command+control+option+s"
        ])
        #expect(AppKeyboardShortcutPresets.screenshotActiveWindow.map(\.rawValue) == [
            "command+control+option+w"
        ])
        #expect(AppKeyboardShortcutPresets.screenshotFullscreen.map(\.rawValue) == [
            "command+control+option+f"
        ])
    }

    @Test("conflict detector warns for macOS screenshot shortcuts")
    func conflictDetectorWarnsForSystemScreenshotShortcuts() throws {
        let detector = AppKeyboardShortcutConflictDetector()

        let screenshotAppConflict = try #require(detector.conflict(forRawValue: "shift + command + 5"))
        let clipboardConflict = try #require(detector.conflict(forRawValue: "command+control+shift+4"))

        #expect(screenshotAppConflict.shortcut.rawValue == "command+shift+5")
        #expect(screenshotAppConflict.systemAction == "macOS Screenshot")
        #expect(clipboardConflict.shortcut.rawValue == "command+control+shift+4")
        #expect(clipboardConflict.systemAction == "macOS selection screenshot to Clipboard")
    }

    @Test("conflict detector ignores empty invalid and Luxel default shortcuts")
    func conflictDetectorIgnoresNonConflictingShortcuts() {
        let detector = AppKeyboardShortcutConflictDetector()

        #expect(detector.conflict(forRawValue: "") == nil)
        #expect(detector.conflict(forRawValue: "command+invalid+r") == nil)
        #expect(detector.conflict(forRawValue: "command+control+option+r") == nil)
    }
}
