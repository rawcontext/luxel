import ArgumentParser
import Foundation
import LuxelCodecAV1
import LuxelCodecWebM
import LuxelCore

public struct LuxelEditorCommand: ParsableCommand, Sendable {
    public static let configuration = CommandConfiguration(
        commandName: "editor",
        abstract: "Open a media file in Luxel's editor."
    )

    @Argument(help: "Media file to open.", completion: .file())
    public var file: LuxelFilePath

    public init() {}

    public mutating func run() throws {
        try validateInputFile(file.url)
        try SystemLuxelEditorOpener().openEditor(fileURL: file.url)
    }
}

public struct LuxelConvertCommand: ParsableCommand, Sendable {
    public static let configuration = CommandConfiguration(
        commandName: "convert",
        abstract: "Convert or edit media headlessly through Luxel's exporter.",
        discussion: """
      The output format is inferred from the output file extension unless --format is \
      provided. Use --format for ambiguous extensions such as .mp4, .mov, or .m4a.

      Aliases: --ss for --start, --to for --end, --t for --duration, -r for \
      --fps, -s WIDTHxHEIGHT for --width/--height, -an for --mute, and -y for \
      --overwrite. These are convenience shortcuts, not full ffmpeg compatibility.
      """
    )

    @Argument(help: "Input media file.", completion: .file())
    public var input: LuxelFilePath

    @Argument(help: "Output media file.", completion: .file())
    public var output: LuxelFilePath

    @Option(
        help:
            "Output format. Values: \(LuxelHeadlessExportFormat.allValueStrings.joined(separator: ", "))."
    )
    public var format: LuxelHeadlessExportFormat?

    @Option(help: "Output width in pixels. Must be used with --height.")
    public var width: Int?

    @Option(help: "Output height in pixels. Must be used with --width.")
    public var height: Int?

    @Option(name: .customShort("s"), help: .hidden)
    public var sizeAlias: LuxelVideoSizeArgument?

    @Option(help: "Output frame rate.")
    public var fps: Int?

    @Option(name: .customShort("r"), help: .hidden)
    public var fpsAlias: Int?

    @Option(help: "Trim start time in seconds.")
    public var start: Double?

    @Option(name: .customLong("ss"), help: .hidden)
    public var startAlias: Double?

    @Option(help: "Trim end time in seconds.")
    public var end: Double?

    @Option(name: .customLong("to"), help: .hidden)
    public var endAlias: Double?

    @Option(help: "Trim duration in seconds. Cannot be combined with --end.")
    public var duration: Double?

    @Option(name: .customLong("t"), help: .hidden)
    public var durationAlias: Double?

    @Option(help: "Playback speed from 0.1 to 10. Defaults to 1.")
    public var speed: Double = 1

    @Flag(help: "Export without audio.")
    public var mute = false

    @Flag(name: .customLong("an", withSingleDash: true), help: .hidden)
    public var muteAlias = false

    @Flag(name: .customLong("crop-to-fill"), help: "Enable crop-to-fill rendering.")
    public var cropToFill = false

    @Option(
        name: .customLong("crop"),
        help: "Crop rectangle as x,y,width,height."
    )
    public var crop: LuxelCropRectArgument?

    @Option(help: "Export quality. Values: compact, balanced, high, lossless.")
    public var quality: LuxelExportQualityArgument?

    @Flag(help: "Replace the output file if it already exists.")
    public var overwrite = false

    @Flag(name: .customShort("y"), help: .hidden)
    public var overwriteAlias = false

    @Flag(help: "Print a JSON result instead of the output path.")
    public var json = false

    @Flag(help: "Suppress terminal progress output.")
    public var quiet = false

    public init() {}

    public var shouldOverwrite: Bool {
        overwrite || overwriteAlias
    }

    public func exportRequest(for source: SourceMedia) throws -> ExportRequest {
        try exportDraft(for: source).exportRequest
    }

    public func exportDraft(for source: SourceMedia) throws -> EditorExportDraft {
        let resolvedFormat = try LuxelHeadlessExportFormat.resolve(
            explicit: format,
            outputURL: output.url
        )
        let resolvedQuality = try quality(for: resolvedFormat.domainValue)

        return try EditorExportDraft(
            source: source.replacingFileURL(input.url),
            format: resolvedFormat.domainValue,
            trimRange: timeRange(sourceDuration: source.duration),
            pixelSize: pixelSize(),
            frameRate: frameRate(),
            shouldMute: mute || muteAlias,
            shouldCrop: cropToFill || crop != nil,
            cropRect: crop?.domainValue,
            quality: resolvedQuality,
            speed: PlaybackSpeed(speed)
        )
    }

    public mutating func run() throws {
        let command = self
        try LuxelAsync.run {
            try await LuxelHeadlessExportRunner().convert(command)
        }
    }

    private func pixelSize() throws -> PixelSize? {
        if let sizeAlias {
            if let width, width != sizeAlias.width {
                throw aliasConflict(primaryName: "--width", aliasName: "-s")
            }
            if let height, height != sizeAlias.height {
                throw aliasConflict(primaryName: "--height", aliasName: "-s")
            }

            return try PixelSize(
                width: width ?? sizeAlias.width,
                height: height ?? sizeAlias.height
            )
        }

        switch (width, height) {
        case (.none, .none):
            return nil
        case (.some(let width), .some(let height)):
            return try PixelSize(width: width, height: height)
        default:
            throw LuxelCLIError.invalidHeadlessExportOptions(
                "Use both --width and --height, or neither."
            )
        }
    }

    private func frameRate() throws -> FrameRate? {
        guard
            let fps = try resolvedAliasedOption(
                primary: fps,
                alias: fpsAlias,
                primaryName: "--fps",
                aliasName: "-r"
            )
        else {
            return nil
        }

        return try FrameRate(fps)
    }

    private func timeRange(sourceDuration: TimeInterval) throws -> TimeRange? {
        let resolvedStartOption = try resolvedAliasedOption(
            primary: start,
            alias: startAlias,
            primaryName: "--start",
            aliasName: "--ss"
        )
        let resolvedEndOption = try resolvedAliasedOption(
            primary: end,
            alias: endAlias,
            primaryName: "--end",
            aliasName: "--to"
        )
        let resolvedDurationOption = try resolvedAliasedOption(
            primary: duration,
            alias: durationAlias,
            primaryName: "--duration",
            aliasName: "--t"
        )

        if resolvedEndOption != nil, resolvedDurationOption != nil {
            throw LuxelCLIError.invalidHeadlessExportOptions(
                "--end and --duration cannot be combined (aliases: --to and --t)."
            )
        }

        let resolvedStart = try validatedNonNegative(resolvedStartOption ?? 0, name: "--start")
        let resolvedEnd: TimeInterval
        if let duration = resolvedDurationOption {
            let resolvedDuration = try validatedPositive(duration, name: "--duration")
            resolvedEnd = resolvedStart + resolvedDuration
        } else if let end = resolvedEndOption {
            resolvedEnd = try validatedPositive(end, name: "--end")
        } else {
            resolvedEnd = sourceDuration
        }

        guard resolvedStart < sourceDuration, resolvedEnd <= sourceDuration + 0.000_001 else {
            throw LuxelCLIError.invalidHeadlessExportOptions(
                "Trim range must fit within the input duration."
            )
        }

        if resolvedStart == 0, abs(resolvedEnd - sourceDuration) < 0.000_001 {
            return nil
        }

        return try TimeRange(start: resolvedStart, end: resolvedEnd)
    }

    private func quality(for format: ExportFormat) throws -> ExportQuality {
        let resolvedQuality = quality?.domainValue ?? ExportQuality.defaultQuality(for: format)
        guard resolvedQuality.isAvailable(for: format) else {
            throw LuxelCLIError.invalidHeadlessExportOptions(
                "\(resolvedQuality.rawValue) quality is not available for \(format.rawValue)."
            )
        }

        return resolvedQuality
    }

    private func resolvedAliasedOption<Value: Equatable>(
        primary: Value?,
        alias: Value?,
        primaryName: String,
        aliasName: String
    ) throws -> Value? {
        switch (primary, alias) {
        case (.some(let primary), .some(let alias)):
            guard primary == alias else {
                throw aliasConflict(primaryName: primaryName, aliasName: aliasName)
            }

            return primary
        case (.some(let primary), .none):
            return primary
        case (.none, .some(let alias)):
            return alias
        case (.none, .none):
            return nil
        }
    }

    private func aliasConflict(primaryName: String, aliasName: String) -> LuxelCLIError {
        LuxelCLIError.invalidHeadlessExportOptions(
            "\(primaryName) and \(aliasName) cannot use different values."
        )
    }
}

public struct LuxelExportCommand: ParsableCommand, Sendable {
    public static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export media from a full Luxel ExportRequest JSON document.",
        discussion: """
      This command is the escape hatch for editor/export fields that do not have \
      dedicated CLI flags. The request JSON uses LuxelCore's ExportRequest shape.
      """
    )

    @Argument(help: "ExportRequest JSON file.", completion: .file())
    public var request: LuxelFilePath

    @Argument(help: "Output media file.", completion: .file())
    public var output: LuxelFilePath

    @Flag(help: "Replace the output file if it already exists.")
    public var overwrite = false

    @Flag(help: "Print a JSON result instead of the output path.")
    public var json = false

    @Flag(help: "Suppress terminal progress output.")
    public var quiet = false

    public init() {}

    public mutating func run() throws {
        let command = self
        try LuxelAsync.run {
            try await LuxelHeadlessExportRunner().export(command)
        }
    }
}

public struct LuxelTranscribeCommand: ParsableCommand, Sendable {
    public static let configuration = CommandConfiguration(
        commandName: "transcribe",
        abstract: "Transcribe a media file with Luxel's local transcript service.",
        discussion: """
      Text is printed to stdout by default, so shell redirection works:
      luxel transcribe recording.m4a > recording.txt
      """
    )

    @Argument(help: "Media or audio file to transcribe.", completion: .file())
    public var file: LuxelFilePath

    @Option(help: "Locale identifier. Defaults to the current locale.")
    public var locale: String?

    @Option(help: "Write transcript output to a file instead of stdout.", completion: .file())
    public var output: LuxelFilePath?

    @Flag(name: .customLong("semantic-turns"), help: "Use Apple Intelligence turn segmentation.")
    public var semanticTurns = false

    @Flag(help: "Identify speakers with Luxel's bundled local diarization model.")
    public var diarize = false

    @Flag(help: "Print the full transcript JSON instead of plain text.")
    public var json = false

    @Flag(help: "Replace --output if it already exists.")
    public var overwrite = false

    public init() {}

    public mutating func run() throws {
        try validateInputFile(file.url)
        if let output {
            try prepareOutputFile(output.url, overwrite: overwrite)
        }
        try runLuxelCommand(
            AutomationInvocation(
                command: .transcribe(
                    AutomationTranscriptionOptions(
                        inputURL: file.url,
                        localeIdentifier: locale,
                        outputURL: output?.url,
                        semanticTurns: semanticTurns,
                        diarize: diarize,
                        json: json,
                        overwrite: overwrite
                    )
                )
            ),
            execution: LuxelCommandExecutionArguments(
                wait: true,
                json: false,
                timeout: 3_600
            ),
            consumesResultFiles: output == nil,
            suppressesSuccessOutput: output != nil
        )
    }
}
