import Foundation

public struct RecordingName: Equatable, Sendable {
    public let value: String

    public init(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw RecordingNameError.empty
        }

        self.value = trimmed
    }

    private init(uncheckedValue value: String) {
        self.value = value
    }

    public static func timestamped(
        title: String = "Luxel",
        extension fileExtension: String = "",
        now: Date,
        calendar: Calendar = .current
    ) -> RecordingName {
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: now)
        let value = String(
            format: "%@ %04d-%02d-%02d at %02d.%02d.%02d%@",
            title,
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0,
            fileExtension
        )

        return RecordingName(uncheckedValue: value)
    }
}

public enum RecordingNameError: Error, Equatable {
    case empty
}
