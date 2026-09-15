import Foundation

public enum RecordingTitleOrigin: String, Codable, Sendable {
    case context
    case intelligence
    case user
}

public struct RecordingOrganization: Codable, Equatable, Sendable {
    public let id: UUID
    public let capturedAt: Date
    public let timeZoneIdentifier: String
    public let captureKind: String
    public var sourceApplication: String?
    public var title: String
    public var titleOrigin: RecordingTitleOrigin
    public var pathsLocked: Bool
    public var isFavorite: Bool
    public var transcriptFileName: String?
    public var recordingOptions: RecordingOptions?
    public var editState: RecordingEditState?
    public var duration: TimeInterval?
    public var exports: [RecordingExportReference]

    public init(
        id: UUID = UUID(), capturedAt: Date, timeZone: TimeZone = .current,
        captureKind: String, sourceApplication: String? = nil, title: String,
        titleOrigin: RecordingTitleOrigin = .context
    ) {
        self.id = id
        self.capturedAt = capturedAt
        timeZoneIdentifier = timeZone.identifier
        self.captureKind = captureKind
        self.sourceApplication = sourceApplication
        self.title = title
        self.titleOrigin = titleOrigin
        pathsLocked = titleOrigin == .user
        isFavorite = false
        exports = []
    }
}

public struct RecordingExportReference: Codable, Equatable, Sendable {
    public let relativePath: String
    public let format: ExportFormat
    public let date: Date
    public let presetName: String?

    public init(relativePath: String, format: ExportFormat, date: Date, presetName: String?) {
        self.relativePath = relativePath
        self.format = format
        self.date = date
        self.presetName = presetName
    }
}

public enum RecordingFileLayout {
    public static func sanitizedTitle(_ value: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:?*\"<>|").union(.controlCharacters)
        let cleaned = value.precomposedStringWithCanonicalMapping.unicodeScalars.map {
            forbidden.contains($0) ? " " : String($0)
        }.joined().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String(cleaned.prefix(72)).trimmingCharacters(in: CharacterSet(charactersIn: " .-"))
    }

    public static func stem(title: String, date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "\(formatter.string(from: date)) - \(sanitizedTitle(title))"
    }

    public static func mediaURL(
        in root: URL, date: Date, title: String, fileExtension: String,
        timeZone: TimeZone = .current,
        exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL {
        let base = stem(title: title, date: date, timeZone: timeZone)
        let month = String(base.prefix(7))
        var name = base
        var index = 2
        while exists(root.appending(path: month).appending(path: name)) {
            name = "\(base) (\(index))"
            index += 1
        }
        return root.appending(path: month).appending(path: name)
            .appending(path: name).appendingPathExtension(fileExtension)
    }
}

public struct RecordingEditState: Codable, Equatable, Sendable {
    public let trimStart: TimeInterval
    public let trimEnd: TimeInterval
    public let transcriptEditPlan: TimelineEditPlan

    public init(trimStart: TimeInterval, trimEnd: TimeInterval, transcriptEditPlan: TimelineEditPlan) {
        self.trimStart = trimStart
        self.trimEnd = trimEnd
        self.transcriptEditPlan = transcriptEditPlan
    }
}
