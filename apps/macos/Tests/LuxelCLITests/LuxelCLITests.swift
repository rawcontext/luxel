import ArgumentParser
import Foundation
import LuxelCLI
import LuxelCore
import Testing

@Suite("Luxel CLI")
struct LuxelCLITests {
    @Test("record command maps display preset countdown and callbacks")
    func recordCommandMapsDisplayPresetCountdownAndCallbacks() throws {
        let command = try LuxelRecordCommand.parse([
            "--display", "main",
            "--preset", "Quick GIF",
            "--countdown", "3",
            "--save-to", "/tmp/Luxel Exports",
            "--x-success", "luxel-callback://done"
        ])

        let invocation = try command.invocation

        #expect(
            invocation
                == AutomationInvocation(
                    command: .record(
                        AutomationRecordingOptions(
                            target: .display(.main),
                            presetName: "Quick GIF",
                            countdownSeconds: 3,
                            outputDirectory: URL(fileURLWithPath: "/tmp/Luxel Exports")
                        )),
                    callbacks: AutomationCallbacks(success: URL(string: "luxel-callback://done"))
                ))
        #expect(
            AutomationInvocationURLBuilder.url(for: invocation).absoluteString
                == "luxel://record?target=display&display=main&preset=Quick%20GIF&countdown=3&saveTo=/tmp/Luxel%20Exports&x-success=luxel-callback://done"
        )
    }

    @Test("toggle command omits options when no target is provided")
    func toggleCommandOmitsOptionsWhenNoTargetIsProvided() throws {
        let command = try LuxelToggleCommand.parse([])

        #expect(try command.invocation == AutomationInvocation(command: .toggle(nil)))
    }

    @Test("toggle command maps last-area quick start options")
    func toggleCommandMapsLastAreaQuickStartOptions() throws {
        let command = try LuxelToggleCommand.parse([
            "--last-area",
            "--preset", "Quick GIF",
            "--countdown", "5",
            "--save-to", "/tmp/Luxel Exports"
        ])

        #expect(
            try command.invocation
                == AutomationInvocation(
                    command: .toggle(
                        AutomationRecordingOptions(
                            target: .lastArea,
                            presetName: "Quick GIF",
                            countdownSeconds: 5,
                            outputDirectory: URL(fileURLWithPath: "/tmp/Luxel Exports")
                        ))))
    }

    @Test("record command accepts file URL save destination")
    func recordCommandAcceptsFileURLSaveDestination() throws {
        let command = try LuxelRecordCommand.parse([
            "--last-area",
            "--save-to", "file:///tmp/Luxel%20Exports"
        ])

        #expect(
            try command.invocation
                == AutomationInvocation(
                    command: .record(
                        AutomationRecordingOptions(
                            target: .lastArea,
                            outputDirectory: URL(fileURLWithPath: "/tmp/Luxel Exports")
                        ))))
    }

    @Test("clip latest and preferences commands map URL-backed actions")
    func clipLatestAndPreferencesCommandsMapURLBackedActions() throws {
        let clip = try LuxelClipCommand.parse(["--seconds", "30"])
        let latest = try LuxelLatestCommand.parse(["--reveal", "--x-success", "luxel-callback://done"])
        let preferences = try LuxelPreferencesCommand.parse(["--pane", "presets"])

        #expect(try clip.invocation == AutomationInvocation(command: .clip(seconds: 30)))
        #expect(
            try latest.invocation
                == AutomationInvocation(
                    command: .latest(reveal: true),
                    callbacks: AutomationCallbacks(success: URL(string: "luxel-callback://done"))
                ))
        #expect(
            try AutomationInvocationURLBuilder.url(for: latest.invocation).absoluteString
                == "luxel://latest?reveal=true&x-success=luxel-callback://done"
        )
        #expect(try preferences.invocation == AutomationInvocation(command: .preferences(.presets)))
    }

    @Test("target and numeric validation rejects invalid command options")
    func targetAndNumericValidationRejectsInvalidCommandOptions() throws {
        #expect(throws: LuxelCLIError.conflictingTargets) {
            let command = try LuxelRecordCommand.parse(["--display", "main", "--active-window"])
            _ = try command.invocation
        }

        #expect(throws: LuxelCLIError.invalidCountdown) {
            let command = try LuxelRecordCommand.parse(["--last-area", "--countdown", "61"])
            _ = try command.invocation
        }

        #expect(throws: LuxelCLIError.missingTarget) {
            let command = try LuxelToggleCommand.parse(["--preset", "Quick GIF"])
            _ = try command.invocation
        }

        #expect(throws: LuxelCLIError.missingTarget) {
            let command = try LuxelToggleCommand.parse(["--save-to", "/tmp/Luxel Exports"])
            _ = try command.invocation
        }

        #expect(throws: LuxelCLIError.invalidOutputDirectory) {
            let command = try LuxelRecordCommand.parse(["--last-area", "--save-to", ""])
            _ = try command.invocation
        }

        #expect(throws: LuxelCLIError.invalidOutputDirectory) {
            let command = try LuxelRecordCommand.parse([
                "--last-area", "--save-to", "https://example.com"
            ])
            _ = try command.invocation
        }

        #expect(throws: LuxelCLIError.invalidClipDuration) {
            let command = try LuxelClipCommand.parse(["--seconds", "0"])
            _ = try command.invocation
        }
    }
}
