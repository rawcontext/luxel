import Foundation

extension AppSettings {
    @discardableResult
    public mutating func addCaptureSizePreset(id: UUID = UUID()) throws -> CaptureSizePreset {
        let preset = try CaptureSizePreset(
            id: id,
            name: userSizePresets.uniquePresetName(base: "New Size"),
            pixelSize: PixelSize(width: 1280, height: 720)
        )
        userSizePresets.append(preset)
        return preset
    }

    @discardableResult
    public mutating func duplicateCaptureSizePreset(id: UUID, newID: UUID = UUID()) throws
    -> CaptureSizePreset {
        guard let preset = userSizePresets.first(where: { $0.id == id }) else {
            throw CaptureSizePresetSettingsError.presetNotFound(id)
        }

        let copy = try CaptureSizePreset(
            id: newID,
            name: userSizePresets.uniquePresetName(base: "\(preset.name) Copy"),
            pixelSize: preset.pixelSize
        )
        userSizePresets.append(copy)
        return copy
    }

    public mutating func deleteCaptureSizePreset(id: UUID) {
        userSizePresets.removeAll { $0.id == id }
    }
}

public enum CaptureSizePresetSettingsError: Error, Equatable {
    case presetNotFound(UUID)
}

extension [CaptureSizePreset] {
    fileprivate func uniquePresetName(base: String) -> String {
        let names = Set(map(\.name))
        guard names.contains(base) else {
            return base
        }

        var index = 2
        while names.contains("\(base) \(index)") {
            index += 1
        }
        return "\(base) \(index)"
    }
}
