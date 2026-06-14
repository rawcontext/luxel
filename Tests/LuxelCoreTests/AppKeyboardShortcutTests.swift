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
}
