import Foundation
import LuxelCore
import Testing

@Suite("Automation commands")
struct AutomationCommandTests {
    @Test("parser reads record URL with display preset countdown and callbacks")
    func parserReadsRecordURLWithDisplayPresetCountdownAndCallbacks() throws {
        let url = try #require(
            URL(
                string:
                    "luxel://record?target=display&display=main&preset=Quick%20GIF&countdown=3&x-success=luxel-callback://done"
            ))

        let invocation = try AutomationCommandParser.parse(url)

        #expect(
            invocation.command
                == .record(
                    AutomationRecordingOptions(
                        target: .display(.main),
                        presetName: "Quick GIF",
                        countdownSeconds: 3
                    )))
        #expect(invocation.callbacks.success == URL(string: "luxel-callback://done"))
        #expect(invocation.callbacks.error == nil)
    }

    @Test("URL builder composes automation invocations")
    func urlBuilderComposesAutomationInvocations() throws {
        let invocation = AutomationInvocation(
            command: .record(
                AutomationRecordingOptions(
                    target: .display(.main),
                    presetName: "Quick GIF",
                    countdownSeconds: 3,
                    outputDirectory: URL(fileURLWithPath: "/tmp/Luxel Exports")
                )),
            callbacks: AutomationCallbacks(
                success: URL(string: "luxel-callback://done"),
                error: URL(string: "luxel-callback://failed")
            )
        )

        let url = AutomationInvocationURLBuilder.url(for: invocation)

        #expect(
            url.absoluteString
                == [
                    "luxel://record?target=display&display=main&preset=Quick%20GIF",
                    "countdown=3",
                    "saveTo=/tmp/Luxel%20Exports",
                    "x-success=luxel-callback://done",
                    "x-error=luxel-callback://failed"
                ].joined(separator: "&"))
        #expect(try AutomationCommandParser.parse(url) == invocation)
    }

    @Test("URL builder composes simple commands")
    func urlBuilderComposesSimpleCommands() throws {
        #expect(
            AutomationInvocationURLBuilder.url(for: AutomationInvocation(command: .stop)).absoluteString
                == "luxel://stop")
        #expect(
            AutomationInvocationURLBuilder.url(for: AutomationInvocation(command: .clip(seconds: 30)))
                .absoluteString
                == "luxel://clip?seconds=30"
        )
        #expect(
            AutomationInvocationURLBuilder.url(for: AutomationInvocation(command: .preferences(.presets)))
                .absoluteString
                == "luxel://preferences?pane=presets"
        )
        #expect(
            AutomationInvocationURLBuilder.url(for: AutomationInvocation(command: .latest(reveal: true)))
                .absoluteString
                == "luxel://latest?reveal=true"
        )
    }

    @Test("parser reads last-area recording URL")
    func parserReadsLastAreaRecordingURL() throws {
        let url = try #require(
            URL(string: "luxel://record?target=lastArea&saveTo=file:///tmp/Luxel%20Exports"))

        let invocation = try AutomationCommandParser.parse(url)

        #expect(
            invocation.command
                == .record(
                    AutomationRecordingOptions(
                        target: .lastArea,
                        outputDirectory: URL(fileURLWithPath: "/tmp/Luxel Exports")
                    )))
    }

    @Test("parser rejects removed still image URL action")
    func parserRejectsRemovedStillImageURLAction() throws {
        let action = ["screen", "shot"].joined()
        let url = try #require(URL(string: "luxel://\(action)?target=activeWindow&format=heic"))

        #expect(throws: AutomationCommandParseError.unknownAction(action)) {
            _ = try AutomationCommandParser.parse(url)
        }
    }

    @Test("parser reads stop toggle clip and preferences URLs")
    func parserReadsSimpleCommandURLs() throws {
        #expect(
            try AutomationCommandParser.parse(#require(URL(string: "luxel://stop"))).command == .stop)
        #expect(
            try AutomationCommandParser.parse(#require(URL(string: "luxel://toggle"))).command
                == .toggle(nil))
        #expect(
            try AutomationCommandParser.parse(#require(URL(string: "luxel://clip?seconds=30"))).command
                == .clip(seconds: 30))
        #expect(
            try AutomationCommandParser.parse(#require(URL(string: "luxel://preferences?pane=presets")))
                .command
                == .preferences(.presets)
        )
        #expect(
            try AutomationCommandParser.parse(#require(URL(string: "luxel://latest?reveal=1"))).command
                == .latest(reveal: true)
        )
        #expect(
            try AutomationCommandParser.parse(#require(URL(string: "luxel://latest"))).command
                == .latest(reveal: false)
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
            _ = try AutomationCommandParser.parse(
                #require(URL(string: "luxel://record?target=lastArea&countdown=-1")))
        }

        #expect(throws: AutomationCommandParseError.invalidParameter("countdown")) {
            _ = try AutomationCommandParser.parse(
                #require(URL(string: "luxel://record?target=lastArea&countdown=61")))
        }

        #expect(throws: AutomationCommandParseError.invalidParameter("reveal")) {
            _ = try AutomationCommandParser.parse(#require(URL(string: "luxel://latest?reveal=maybe")))
        }

        #expect(throws: AutomationCommandParseError.invalidParameter("saveTo")) {
            _ = try AutomationCommandParser.parse(
                #require(URL(string: "luxel://record?target=lastArea&saveTo=relative")))
        }
    }

    @Test("parser rejects duplicate parameters and file callbacks")
    func parserRejectsDuplicateParametersAndFileCallbacks() throws {
        #expect(throws: AutomationCommandParseError.duplicateParameter("target")) {
            _ = try AutomationCommandParser.parse(
                #require(URL(string: "luxel://record?target=lastArea&target=activeWindow")))
        }

        #expect(throws: AutomationCommandParseError.invalidCallbackURL("x-success")) {
            _ = try AutomationCommandParser.parse(
                #require(
                    URL(
                        string: "luxel://stop?x-success=file:///tmp/output.json"
                    )))
        }
    }

    @Test("callback builder appends success result details")
    func callbackBuilderAppendsSuccessResultDetails() throws {
        let base = try #require(URL(string: "luxel-callback://done?token=abc"))
        let fileURL = URL(fileURLWithPath: "/tmp/Luxel Recording.mp4")

        #expect(AutomationCallbackURLBuilder.successURL(for: .accepted, callback: base) == base)
        #expect(
            AutomationCallbackURLBuilder.successURL(for: .recording(id: "recording-1"), callback: base)?
                .absoluteString == "luxel-callback://done?token=abc&recordingID=recording-1"
        )
        #expect(
            AutomationCallbackURLBuilder.successURL(for: .file(fileURL), callback: base)?
                .absoluteString == "luxel-callback://done?token=abc&filePath=/tmp/Luxel%20Recording.mp4"
        )
    }

    @Test("callback builder appends error messages")
    func callbackBuilderAppendsErrorMessages() throws {
        let base = try #require(URL(string: "luxel-callback://error"))

        #expect(
            AutomationCallbackURLBuilder.errorURL(message: "Recording failed", callback: base)?
                .absoluteString == "luxel-callback://error?errorMessage=Recording%20failed"
        )
    }

    @Test("policy allows safe commands by default")
    func policyAllowsSafeCommandsByDefault() {
        let settings = AppSettings.defaults(recordingsDirectory: URL(fileURLWithPath: "/tmp/luxel"))

        #expect(
            AutomationPolicy.evaluate(
                command: .preferences(.presets),
                settings: settings,
                context: AutomationPolicyContext()
            ) == .allow)
        #expect(
            AutomationPolicy.evaluate(
                command: .stop,
                settings: settings,
                context: AutomationPolicyContext()
            ) == .allow)
        #expect(
            AutomationPolicy.evaluate(
                command: .latest(reveal: false),
                settings: settings,
                context: AutomationPolicyContext()
            ) == .allow)
        #expect(
            AutomationPolicy.evaluate(
                command: .toggle(nil),
                settings: settings,
                context: AutomationPolicyContext(hasActiveRecording: true)
            ) == .allow)
    }

    @Test("policy confirms ungranted start commands by default")
    func policyConfirmsUngrantedStartCommandsByDefault() {
        let settings = AppSettings.defaults(recordingsDirectory: URL(fileURLWithPath: "/tmp/luxel"))

        #expect(
            AutomationPolicy.evaluate(
                command: .record(AutomationRecordingOptions(target: .lastArea)),
                settings: settings,
                context: AutomationPolicyContext()
            )
            == .confirm(
                AutomationPolicyPrompt(
                    title: "Allow Automation Request?",
                    message: "Another app wants to start a screen recording."
                )))
        #expect(
            AutomationPolicy.evaluate(
                command: .toggle(nil),
                settings: settings,
                context: AutomationPolicyContext(hasActiveRecording: false)
            )
            == .confirm(
                AutomationPolicyPrompt(
                    title: "Allow Automation Request?",
                    message: "Another app wants to toggle recording."
                )))
    }

    @Test("policy confirms ungranted named callers")
    func policyConfirmsUngrantedNamedCallers() {
        let settings = AppSettings.defaults(recordingsDirectory: URL(fileURLWithPath: "/tmp/luxel"))

        let decision = AutomationPolicy.evaluate(
            command: .record(AutomationRecordingOptions(target: .lastArea)),
            settings: settings,
            context: AutomationPolicyContext(
                callerID: "com.example.terminal",
                callerDisplayName: "Terminal"
            )
        )

        #expect(
            decision
                == .confirm(
                    AutomationPolicyPrompt(
                        title: "Allow Automation Request?",
                        message: "Terminal wants to start a screen recording."
                    )))
    }

    @Test("policy allows granted callers")
    func policyAllowsGrantedCallers() {
        let settings = AppSettings(
            recordingsDirectory: URL(fileURLWithPath: "/tmp/luxel"),
            urlAutomationGrants: ["com.example.terminal"]
        )

        let decision = AutomationPolicy.evaluate(
            command: .record(AutomationRecordingOptions(target: .activeWindow)),
            settings: settings,
            context: AutomationPolicyContext(callerID: "com.example.terminal")
        )

        #expect(decision == .allow)
    }
}
