import ArgumentParser
import Foundation
import LuxelCLI
import LuxelCore
import Testing

@Suite("Luxel CLI convert aliases")
struct LuxelCLIConvertAliasTests {
    @Test("convert command maps ffmpeg-style aliases to headless export options")
    func convertCommandMapsFFmpegStyleAliasesToHeadlessExportOptions() throws {
        let source = try headlessSourceMedia()
        let primary = try LuxelConvertCommand.parse([
            "input.mp4",
            "output.webm",
            "--start", "2",
            "--duration", "4",
            "--fps", "30",
            "--width", "1280",
            "--height", "720",
            "--mute",
            "--overwrite"
        ])
        let alias = try LuxelConvertCommand.parse([
            "input.mp4",
            "output.webm",
            "--ss", "2",
            "--t", "4",
            "-r", "30",
            "-s", "1280x720",
            "-an",
            "-y"
        ])

        #expect(try alias.exportRequest(for: source) == primary.exportRequest(for: source))
        #expect(alias.shouldOverwrite)
    }

    @Test("convert command maps ffmpeg-style end alias")
    func convertCommandMapsFFmpegStyleEndAlias() throws {
        let command = try LuxelConvertCommand.parse([
            "input.mp4",
            "output.webm",
            "--ss", "2",
            "--to", "6"
        ])

        let request = try command.exportRequest(for: headlessSourceMedia())

        #expect(request.timeRange == (try TimeRange(start: 2, end: 6)))
    }

    @Test("convert command rejects conflicting ffmpeg-style aliases")
    func convertCommandRejectsConflictingFFmpegStyleAliases() throws {
        let source = try headlessSourceMedia()
        let cases: [([String], LuxelCLIError)] = [
            (
                ["input.mp4", "output.webm", "--start", "2", "--ss", "3"],
                .invalidHeadlessExportOptions(
                    "--start and --ss cannot use different values.")
            ),
            (
                ["input.mp4", "output.webm", "--end", "6", "--to", "7"],
                .invalidHeadlessExportOptions(
                    "--end and --to cannot use different values.")
            ),
            (
                ["input.mp4", "output.webm", "--duration", "4", "--t", "5"],
                .invalidHeadlessExportOptions(
                    "--duration and --t cannot use different values.")
            ),
            (
                ["input.mp4", "output.webm", "--fps", "24", "-r", "30"],
                .invalidHeadlessExportOptions(
                    "--fps and -r cannot use different values.")
            ),
            (
                ["input.mp4", "output.webm", "--width", "640", "-s", "1280x720"],
                .invalidHeadlessExportOptions(
                    "--width and -s cannot use different values.")
            ),
            (
                ["input.mp4", "output.webm", "--height", "360", "-s", "1280x720"],
                .invalidHeadlessExportOptions(
                    "--height and -s cannot use different values.")
            )
        ]

        for (arguments, expectedError) in cases {
            #expect(throws: expectedError) {
                let command = try LuxelConvertCommand.parse(arguments)
                _ = try command.exportRequest(for: source)
            }
        }
    }

    @Test("convert command keeps end and duration aliases mutually exclusive")
    func convertCommandKeepsEndAndDurationAliasesMutuallyExclusive() throws {
        #expect(
            throws: LuxelCLIError.invalidHeadlessExportOptions(
                "--end and --duration cannot be combined (aliases: --to and --t)."
            )
        ) {
            let command = try LuxelConvertCommand.parse([
                "input.mp4",
                "output.webm",
                "--to", "6",
                "--t", "4"
            ])
            _ = try command.exportRequest(for: headlessSourceMedia())
        }
    }

    @Test("convert help mentions aliases without replacing primary options")
    func convertHelpMentionsAliasesWithoutReplacingPrimaryOptions() {
        let help = LuxelConvertCommand.helpMessage()

        #expect(help.contains("Aliases:"))
        #expect(help.contains("--ss for --start"))
        #expect(help.contains("-s"))
        #expect(help.contains("WIDTHxHEIGHT"))
        #expect(help.contains("not full ffmpeg compatibility"))
        #expect(help.contains("--width"))
        #expect(help.contains("--height"))
    }

    private func headlessSourceMedia() throws -> SourceMedia {
        try SourceMedia(
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            duration: 10,
            pixelSize: PixelSize(width: 1920, height: 1080),
            nominalFrameRate: FrameRate(60),
            hasAudio: true
        )
    }
}
