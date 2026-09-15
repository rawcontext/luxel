import Foundation

public enum RecordingDateFilter: String, CaseIterable, Sendable {
    case all = "All dates"
    case today = "Today"
    case week = "Last 7 days"
    case month = "Last 30 days"

    public func includes(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        switch self {
        case .all: return true
        case .today: return calendar.isDate(date, inSameDayAs: now)
        case .week, .month:
            let days = self == .week ? 6 : 29
            let start = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now)) ?? now
            return date >= start && date <= now
        }
    }
}

public enum RecordingSearch {
    public static func matches(_ recording: PastRecording, query: String, transcript: String) -> Bool {
        let metadata = recording.bundleManifest?.organization
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let text = [
            recording.name, metadata?.title ?? "", metadata?.sourceApplication ?? "",
            formatter.string(from: recording.date),
            recording.date.formatted(date: .long, time: .omitted), transcript
        ].joined(separator: " ")
        return query.split(whereSeparator: \.isWhitespace).allSatisfy { text.localizedStandardContains($0) }
    }
}
