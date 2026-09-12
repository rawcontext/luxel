import Foundation
import LuxelCore

enum PresetSizeSelection: String, CaseIterable, Identifiable {
    case original
    case percent75
    case percent50
    case percent33
    case percent25
    case percent20
    case percent10
    case maxWidth

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .original:
            LuxelLocalization.string("Original")
        case .percent75:
            "75%"
        case .percent50:
            "50%"
        case .percent33:
            "33%"
        case .percent25:
            "25%"
        case .percent20:
            "20%"
        case .percent10:
            "10%"
        case .maxWidth:
            LuxelLocalization.string("Max Width")
        }
    }

    init(editorPreset: EditorSizePreset) {
        switch editorPreset {
        case .original:
            self = .original
        case .percent75:
            self = .percent75
        case .percent50:
            self = .percent50
        case .percent33:
            self = .percent33
        case .percent25:
            self = .percent25
        case .percent20:
            self = .percent20
        case .percent10:
            self = .percent10
        }
    }

    func sizeRule(currentMaxWidth: Int) -> ExportPresetSizeRule {
        switch self {
        case .original:
            .original
        case .percent75:
            .preset(.percent75)
        case .percent50:
            .preset(.percent50)
        case .percent33:
            .preset(.percent33)
        case .percent25:
            .preset(.percent25)
        case .percent20:
            .preset(.percent20)
        case .percent10:
            .preset(.percent10)
        case .maxWidth:
            .maxWidth(currentMaxWidth)
        }
    }
}

enum PresetDestinationSelection: String, CaseIterable, Identifiable {
    case recordingsDirectory
    case clipboard

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .recordingsDirectory:
            LuxelLocalization.string("Recordings Folder")
        case .clipboard:
            LuxelLocalization.string("Clipboard")
        }
    }
}

extension ExportPresetPostAction {
    var label: String {
        switch self {
        case .none:
            LuxelLocalization.string("None")
        case .revealInFinder:
            LuxelLocalization.string("Reveal in Finder")
        case .copyToClipboard:
            LuxelLocalization.string("Copy to Clipboard")
        case .notifyWithThumbnail:
            LuxelLocalization.string("Notify with Thumbnail")
        }
    }
}
