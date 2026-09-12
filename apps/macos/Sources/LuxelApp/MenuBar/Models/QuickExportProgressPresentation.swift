import LuxelCore

struct QuickExportProgressPresentation: Equatable {
    let presetName: String
    let snapshot: ExportProgressSnapshot

    var title: String {
        switch snapshot.phase {
        case .preparing:
            LuxelLocalization.format("Preparing %@", presetName)
        case .enhancingAudio:
            LuxelLocalization.string(
                "export.job.enhancingAudio",
                defaultValue: "Enhancing audio…"
            )
        case .exporting:
            LuxelLocalization.format("Exporting %@", presetName)
        case .completed:
            LuxelLocalization.format("Exported %@", presetName)
        case .canceled:
            LuxelLocalization.format("Canceled %@", presetName)
        }
    }

    var progressText: String {
        "\(Int((snapshot.progress * 100).rounded()))%"
    }

    var canCancel: Bool {
        switch snapshot.phase {
        case .preparing, .enhancingAudio, .exporting:
            true
        case .completed, .canceled:
            false
        }
    }
}
