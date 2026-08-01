import Foundation

extension AppSettings {
    @discardableResult
    public mutating func addExportPreset(id: UUID = UUID()) throws -> ExportPreset {
        let preset = try ExportPreset(
            id: id,
            name: exportPresets.uniquePresetName(base: "New Preset"),
            format: .mp4,
            sizeRule: .original,
            frameRate: nil,
            destination: .recordingsDirectory,
            postAction: .revealInFinder
        )
        exportPresets.append(preset)
        if quickExportPresetID == nil {
            quickExportPresetID = preset.id
        }
        return preset
    }

    @discardableResult
    public mutating func duplicateExportPreset(id: UUID, newID: UUID = UUID()) throws -> ExportPreset {
        guard let preset = exportPresets.first(where: { $0.id == id }) else {
            throw ExportPresetSettingsError.presetNotFound(id)
        }

        let copy = try ExportPreset(
            id: newID,
            name: exportPresets.uniquePresetName(base: "\(preset.name) Copy"),
            format: preset.format,
            sizeRule: preset.sizeRule,
            frameRate: preset.frameRate,
            destination: preset.destination,
            postAction: preset.postAction
        )
        exportPresets.append(copy)
        return copy
    }

    public mutating func deleteExportPreset(id: UUID) {
        exportPresets.removeAll { $0.id == id }

        if quickExportPresetID == id {
            quickExportPresetID = exportPresets.first?.id
        }
    }
}

public enum ExportPresetSettingsError: Error, Equatable {
    case presetNotFound(UUID)
}
