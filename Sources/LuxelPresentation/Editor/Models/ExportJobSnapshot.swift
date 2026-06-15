import Foundation
import LuxelCore

struct ExportJobSnapshot: Identifiable, Equatable {
    let id: Int
    let format: ExportFormat
    var progress: ExportProgressSnapshot?
    var fileURL: URL?
    var fileSizeBytes: Int64?

    var progressValue: Double {
        progress?.progress ?? 0
    }

    var statusSummary: String {
        if let fileSizeBytes {
            return ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
        }

        guard let progress else {
            return "Queued"
        }

        switch progress.phase {
        case .preparing:
            return "Preparing"
        case .exporting:
            return "\(Int((progress.progress * 100).rounded()))%"
        case .completed:
            return "Complete"
        case .canceled:
            return "Canceled"
        }
    }
}
