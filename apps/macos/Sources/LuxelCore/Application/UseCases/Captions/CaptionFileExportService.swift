import Foundation

public struct CaptionFileExportRequest: Equatable, Sendable {
    public let track: CaptionTrack
    public let format: CaptionFileFormat
    public let outputFileURL: URL
    public let timeMapper: CaptionExportTimeMapper?

    public init(
        track: CaptionTrack,
        format: CaptionFileFormat,
        outputFileURL: URL,
        timeMapper: CaptionExportTimeMapper? = nil
    ) {
        self.track = track
        self.format = format
        self.outputFileURL = outputFileURL
        self.timeMapper = timeMapper
    }
}

public struct ExportedCaptionFile: Equatable, Sendable {
    public let fileURL: URL
    public let format: CaptionFileFormat

    public init(fileURL: URL, format: CaptionFileFormat) {
        self.fileURL = fileURL
        self.format = format
    }
}

public struct CaptionFileExportService: Sendable {
    private let fileSystem: any FileSystem

    public init(fileSystem: any FileSystem) {
        self.fileSystem = fileSystem
    }

    public func export(_ request: CaptionFileExportRequest) throws -> ExportedCaptionFile {
        let track = try request.timeMapper?.map(request.track) ?? request.track
        let text = request.format.serialize(track)
        try fileSystem.writeData(Data(text.utf8), to: request.outputFileURL)
        return ExportedCaptionFile(
            fileURL: request.outputFileURL,
            format: request.format
        )
    }
}
