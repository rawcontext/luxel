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

    @Test("shortcut exposes compact symbol display")
    func shortcutExposesCompactSymbolDisplay() throws {
        let shortcut = try AppKeyboardShortcut(
            key: "p",
            modifiers: [.command, .option, .shift]
        )

        #expect(shortcut.compactDisplayName == "\u{2325}\u{21E7}\u{2318}P")
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
        #expect(
            AppKeyboardShortcutPresets.capture.map(\.rawValue) == [
                "command+control+option+r"
            ])
        #expect(
            AppKeyboardShortcutPresets.toggleRecording.map(\.rawValue) == [
                "command+control+option+t"
            ])
        #expect(
            AppKeyboardShortcutPresets.recordActiveWindow.map(\.rawValue) == [
                "command+control+option+shift+w"
            ])
        #expect(
            AppKeyboardShortcutPresets.recordFullscreen.map(\.rawValue) == [
                "command+control+option+shift+f"
            ])
        #expect(
            AppKeyboardShortcutPresets.audioOnlyRecording.map(\.rawValue) == [
                "command+control+option+a"
            ])
        #expect(
            AppKeyboardShortcutPresets.quickRecordLast.map(\.rawValue) == [
                "command+control+option+q"
            ])
        #expect(
            AppKeyboardShortcutPresets.clipReplayBuffer.map(\.rawValue) == [
                "command+control+option+c"
            ])
    }

    @Test("conflict detector warns for macOS capture shortcuts")
    func conflictDetectorWarnsForSystemCaptureShortcuts() throws {
        let detector = AppKeyboardShortcutConflictDetector()

        let captureControlConflict = try #require(detector.conflict(forRawValue: "shift + command + 5"))
        let clipboardConflict = try #require(detector.conflict(forRawValue: "command+control+shift+4"))

        #expect(captureControlConflict.shortcut.rawValue == "command+shift+5")
        #expect(captureControlConflict.systemAction == "macOS capture controls")
        #expect(clipboardConflict.shortcut.rawValue == "command+control+shift+4")
        #expect(clipboardConflict.systemAction == "macOS selection capture to Clipboard")
    }

    @Test("conflict detector ignores empty invalid and Luxel default shortcuts")
    func conflictDetectorIgnoresNonConflictingShortcuts() {
        let detector = AppKeyboardShortcutConflictDetector()

        #expect(detector.conflict(forRawValue: "") == nil)
        #expect(detector.conflict(forRawValue: "command+invalid+r") == nil)
        #expect(detector.conflict(forRawValue: "command+control+option+r") == nil)
    }
}
