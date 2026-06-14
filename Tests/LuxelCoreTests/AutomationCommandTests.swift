import Foundation
import LuxelCore
import Testing

@Suite("Automation commands")
struct AutomationCommandTests {
    @Test("parser reads record URL with display preset countdown and callbacks")
    func parserReadsRecordURLWithDisplayPresetCountdownAndCallbacks() throws {
        let url = try #require(URL(
            string: "luxel://record?target=display&display=main&preset=Quick%20GIF&countdown=3&x-success=luxel-callback://done"
        ))

        let invocation = try AutomationCommandParser.parse(url)

        #expect(invocation.command == .record(AutomationRecordingOptions(
            target: .display(.main),
            presetName: "Quick GIF",
            countdownSeconds: 3
        )))
        #expect(invocation.callbacks.success == URL(string: "luxel-callback://done"))
        #expect(invocation.callbacks.error == nil)
    }

    @Test("parser reads last-area recording URL")
    func parserReadsLastAreaRecordingURL() throws {
        let url = try #require(URL(string: "luxel://record?target=lastArea"))

        let invocation = try AutomationCommandParser.parse(url)

        #expect(invocation.command == .record(AutomationRecordingOptions(target: .lastArea)))
    }

    @Test("parser reads screenshot URL with active window and format")
    func parserReadsScreenshotURLWithActiveWindowAndFormat() throws {
        let url = try #require(URL(string: "luxel://screenshot?target=activeWindow&format=heic"))

        let invocation = try AutomationCommandParser.parse(url)

        #expect(invocation.command == .screenshot(AutomationScreenshotOptions(
            target: .activeWindow,
            format: .heic
        )))
    }

    @Test("parser reads stop toggle clip and preferences URLs")
    func parserReadsSimpleCommandURLs() throws {
        #expect(try AutomationCommandParser.parse(#require(URL(string: "luxel://stop"))).command == .stop)
        #expect(try AutomationCommandParser.parse(#require(URL(string: "luxel://toggle"))).command == .toggle(nil))
        #expect(try AutomationCommandParser.parse(#require(URL(string: "luxel://clip?seconds=30"))).command == .clip(seconds: 30))
        #expect(
            try AutomationCommandParser.parse(#require(URL(string: "luxel://preferences?pane=presets"))).command
                == .preferences(.presets)
        )
    }

    @Test("parser rejects unknown actions and invalid parameters")
    func parserRejectsUnknownActionsAndInvalidParameters() throws {
        #expect(throws: AutomationCommandParseError.unknownAction("erase")) {
            _ = try AutomationCommandParser.parse(#require(URL(string: "luxel://erase")))
        }

        #expect(throws: AutomationCommandParseError.missingParameter("target")) {
            _ = try AutomationCommandParser.parse(#require(URL(string: "luxel://record")))
        }

        #expect(throws: AutomationCommandParseError.missingParameter("display")) {
            _ = try AutomationCommandParser.parse(#require(URL(string: "luxel://record?target=display")))
        }

        #expect(throws: AutomationCommandParseError.invalidParameter("countdown")) {
            _ = try AutomationCommandParser.parse(#require(URL(string: "luxel://record?target=lastArea&countdown=-1")))
        }
    }

    @Test("parser rejects duplicate parameters and file callbacks")
    func parserRejectsDuplicateParametersAndFileCallbacks() throws {
        #expect(throws: AutomationCommandParseError.duplicateParameter("target")) {
            _ = try AutomationCommandParser.parse(#require(URL(string: "luxel://record?target=lastArea&target=activeWindow")))
        }

        #expect(throws: AutomationCommandParseError.invalidCallbackURL("x-success")) {
            _ = try AutomationCommandParser.parse(#require(URL(
                string: "luxel://stop?x-success=file:///tmp/output.json"
            )))
        }
    }

    @Test("policy allows safe commands while automation is disabled")
    func policyAllowsSafeCommandsWhileAutomationIsDisabled() {
        let settings = AppSettings.defaults(recordingsDirectory: URL(fileURLWithPath: "/tmp/luxel"))

        #expect(AutomationPolicy.evaluate(
            command: .preferences(.presets),
            settings: settings,
            context: AutomationPolicyContext()
        ) == .allow)
        #expect(AutomationPolicy.evaluate(
            command: .stop,
            settings: settings,
            context: AutomationPolicyContext()
        ) == .allow)
        #expect(AutomationPolicy.evaluate(
            command: .toggle(nil),
            settings: settings,
            context: AutomationPolicyContext(hasActiveRecording: true)
        ) == .allow)
    }

    @Test("policy denies start commands while automation is disabled")
    func policyDeniesStartCommandsWhileAutomationIsDisabled() {
        let settings = AppSettings.defaults(recordingsDirectory: URL(fileURLWithPath: "/tmp/luxel"))

        #expect(AutomationPolicy.evaluate(
            command: .record(AutomationRecordingOptions(target: .lastArea)),
            settings: settings,
            context: AutomationPolicyContext()
        ) == .deny("URL automation is disabled"))
        #expect(AutomationPolicy.evaluate(
            command: .toggle(nil),
            settings: settings,
            context: AutomationPolicyContext(hasActiveRecording: false)
        ) == .deny("URL automation is disabled"))
    }

    @Test("policy confirms ungranted start commands when automation is enabled")
    func policyConfirmsUngrantedStartCommandsWhenAutomationIsEnabled() {
        let settings = AppSettings(
            recordingsDirectory: URL(fileURLWithPath: "/tmp/luxel"),
            allowURLAutomation: true
        )

        let decision = AutomationPolicy.evaluate(
            command: .record(AutomationRecordingOptions(target: .lastArea)),
            settings: settings,
            context: AutomationPolicyContext(
                callerID: "com.example.terminal",
                callerDisplayName: "Terminal"
            )
        )

        #expect(decision == .confirm(AutomationPolicyPrompt(
            title: "Allow URL Automation?",
            message: "Terminal wants to start a screen recording."
        )))
    }

    @Test("policy allows granted callers when automation is enabled")
    func policyAllowsGrantedCallersWhenAutomationIsEnabled() {
        let settings = AppSettings(
            recordingsDirectory: URL(fileURLWithPath: "/tmp/luxel"),
            allowURLAutomation: true,
            urlAutomationGrants: ["com.example.terminal"]
        )

        let decision = AutomationPolicy.evaluate(
            command: .screenshot(AutomationScreenshotOptions(target: .activeWindow)),
            settings: settings,
            context: AutomationPolicyContext(callerID: "com.example.terminal")
        )

        #expect(decision == .allow)
    }
}
