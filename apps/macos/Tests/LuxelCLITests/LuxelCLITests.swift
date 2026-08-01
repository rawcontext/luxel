import ArgumentParser
import Foundation
import LuxelCLI
import LuxelCore
import LuxelTestSupport
import Testing

@Suite("Luxel CLI")
struct LuxelCLITests {
    @Test("root help advertises version and complete automation surface")
    func rootHelpAdvertisesVersionAndCompleteAutomationSurface() {
        let help = LuxelCLI.helpMessage()

        #expect(help.contains("--version"))
        #expect(help.contains("record"))
        #expect(help.contains("stop"))
        #expect(help.contains("toggle"))
        #expect(help.contains("clip"))
        #expect(help.contains("latest"))
        #expect(help.contains("editor"))
        #expect(help.contains("convert"))
        #expect(help.contains("export"))
        #expect(help.contains("transcribe"))
        #expect(help.contains("preferences"))
        #expect(!help.contains("completions"))
    }

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

        #expect(invocation == testRecordAutomationInvocation())
        #expect(
            AutomationInvocationURLBuilder.url(for: invocation).absoluteString
                == "luxel://record?target=display&display=main&preset=Quick%20GIF&countdown=3"
                + "&saveTo=/tmp/Luxel%20Exports&x-success=luxel-callback://done"
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

    @Test("record command accepts fixed and display-matched frame rates")
    func recordCommandAcceptsFrameRateModes() throws {
        let fixed = try LuxelRecordCommand.parse([
            "--display", "main", "--fps", "120"
        ])
        let matched = try LuxelRecordCommand.parse([
            "--active-window", "--fps", "display"
        ])

        #expect(
            try fixed.invocation
                == AutomationInvocation(
                    command: .record(
                        AutomationRecordingOptions(
                            target: .display(.main),
                            frameRate: .fixed(FrameRate(120))
                        ))))
        #expect(
            try AutomationInvocationURLBuilder.url(for: fixed.invocation).absoluteString
                == "luxel://record?target=display&display=main&fps=120"
        )
        #expect(
            try matched.invocation
                == AutomationInvocation(
                    command: .record(
                        AutomationRecordingOptions(
                            target: .activeWindow,
                            frameRate: .matchDisplay
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

        #expect(throws: LuxelCLIError.invalidRecordingFrameRate) {
            let command = try LuxelRecordCommand.parse(["--last-area", "--fps", "121"])
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

extension LuxelCLITests {
    @Test("convert command maps headless editor export options")
    func convertCommandMapsHeadlessEditorExportOptions() throws {
        let command = try LuxelConvertCommand.parse([
            "input.mp4",
            "output.webm",
            "--width", "1280",
            "--height", "720",
            "--fps", "30",
            "--start", "2",
            "--duration", "4",
            "--speed", "2",
            "--mute",
            "--crop", "10,20,640,360",
            "--quality", "high",
            "--quiet"
        ])
        let source = try SourceMedia(
            fileURL: URL(fileURLWithPath: "/tmp/ignored.mp4"),
            duration: 10,
            pixelSize: PixelSize(width: 1920, height: 1080),
            nominalFrameRate: FrameRate(60),
            hasAudio: true
        )

        let request = try command.exportRequest(for: source)

        #expect(request.inputFileURL.path.hasSuffix("/input.mp4"))
        #expect(request.format == .webm)
        #expect(request.pixelSize == (try PixelSize(width: 1280, height: 720)))
        #expect(request.frameRate == (try FrameRate(30)))
        #expect(request.timeRange == (try TimeRange(start: 2, end: 6)))
        #expect(request.speed == (try PlaybackSpeed(2)))
        #expect(request.shouldMute)
        #expect(request.shouldCrop)
        #expect(request.cropRect == (try CaptureRect(x: 10, y: 20, width: 640, height: 360)))
        #expect(request.quality == .high)
        #expect(command.quiet)
    }

    @Test("convert command validates ambiguous formats and dimensions")
    func convertCommandValidatesAmbiguousFormatsAndDimensions() throws {
        let source = try SourceMedia(
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            duration: 10,
            pixelSize: PixelSize(width: 1920, height: 1080),
            nominalFrameRate: FrameRate(60),
            hasAudio: true
        )

        #expect(
            throws: LuxelCLIError.invalidHeadlessExportOptions(
                "Use --format prores422 or --format prores4444 for .mov output."
            )
        ) {
            let command = try LuxelConvertCommand.parse(["input.mp4", "output.mov"])
            _ = try command.exportRequest(for: source)
        }

        #expect(
            throws: LuxelCLIError.invalidHeadlessExportOptions(
                "Use both --width and --height, or neither."
            )
        ) {
            let command = try LuxelConvertCommand.parse(["input.mp4", "output.mp4", "--width", "1280"])
            _ = try command.exportRequest(for: source)
        }

        #expect(
            throws: LuxelCLIError.invalidHeadlessExportOptions(
                "--format webm requires .webm output."
            )
        ) {
            let command = try LuxelConvertCommand.parse([
                "input.mp4", "output.mp4", "--format", "webm"
            ])
            _ = try command.exportRequest(for: source)
        }
    }

    @Test("convert command accepts explicit AV1 for MP4 output")
    func convertCommandAcceptsExplicitAV1ForMP4Output() throws {
        let source = try SourceMedia(
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            duration: 10,
            pixelSize: PixelSize(width: 1920, height: 1080),
            nominalFrameRate: FrameRate(60),
            hasAudio: true
        )
        let command = try LuxelConvertCommand.parse([
            "input.mp4", "output.mp4", "--format", "av1"
        ])

        let request = try command.exportRequest(for: source)

        #expect(request.format == .av1)
    }

    @Test("explicit convert formats cover native and external exports")
    func explicitConvertFormatsCoverNativeAndExternalExports() throws {
        #expect(LuxelHeadlessExportFormat.allValueStrings.contains("av1"))
        #expect(LuxelHeadlessExportFormat.allValueStrings.contains("webm"))
        #expect(LuxelHeadlessExportFormat.allValueStrings.contains("prores422"))
        #expect(LuxelHeadlessExportFormat.allValueStrings.contains("flac"))
    }

    @Test("progress renderer builds a stable terminal bar")
    func progressRendererBuildsStableTerminalBar() {
        #expect(
            LuxelProgressBarRenderer.line(label: "Exporting WebM", progress: 0.5, width: 10)
                == "Exporting WebM [#####-----]  50%"
        )
        #expect(
            LuxelProgressBarRenderer.line(label: "Exporting WebM", progress: 2, width: 10)
                == "Exporting WebM [##########] 100%"
        )
    }

    @Test("editor opener finds containing app bundle")
    func editorOpenerFindsContainingAppBundle() {
        let executableURL = URL(fileURLWithPath: "/Applications/Luxel.app/Contents/MacOS/luxel-cli")

        #expect(
            SystemLuxelEditorOpener.containingAppBundleURL(executableURL: executableURL)?
                .path == "/Applications/Luxel.app"
        )
    }

    @Test("transcript formatter emits turn text")
    func transcriptFormatterEmitsTurnText() throws {
        let firstSpan = try TimedTranscriptSpan(
            id: "span-0",
            text: "Hello",
            start: 0,
            end: 1
        )
        let secondSpan = try TimedTranscriptSpan(
            id: "span-1",
            text: "World",
            start: 1,
            end: 2
        )
        let transcript = try TurnSegmentedTranscript(
            spans: [firstSpan, secondSpan],
            turns: [
                try TranscriptTurn(
                    id: "turn-0",
                    spanIDs: ["span-0"],
                    start: 0,
                    end: 1,
                    text: "Hello"
                ),
                try TranscriptTurn(
                    id: "turn-1",
                    spanIDs: ["span-1"],
                    start: 1,
                    end: 2,
                    text: "World"
                )
            ],
            localeIdentifier: "en_US"
        )

        #expect(LuxelTranscriptFormatter.plainText(transcript) == "Hello\nWorld")
    }
}
