import Foundation
import LuxelCore

@MainActor
extension LuxelMenuModel {
    func refreshKnownSpeakers() {
        knownSpeakers = (try? knownSpeakerProfileStore.library())?.profiles ?? []
    }

    /// The model ships inside the app bundle, so preparation is a fast local
    /// copy into Application Support (with a network download as fallback for
    /// builds without bundled resources). Runs at launch and when the setting
    /// is switched on; skips silently when the model is already installed.
    func prepareSpeakerModelIfNeeded() {
        guard settings.transcriptSpeakerDiarizationEnabled else {
            return
        }

        Task { [speakerDiarizationModelStore] in
            _ = try? await speakerDiarizationModelStore.prepareModel()
        }
    }

    func setSpeakerDiarizationEnabled(_ isEnabled: Bool) {
        settings.transcriptSpeakerDiarizationEnabled = isEnabled
        saveSettings()
        prepareSpeakerModelIfNeeded()
    }

    func renameKnownSpeaker(id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
            var profile = knownSpeakers.first(where: { $0.id == id }),
            profile.displayName != trimmed
        else {
            return
        }

        profile.displayName = trimmed
        profile.updatedAt = Date()
        _ = try? knownSpeakerProfileStore.save(profile)
        refreshKnownSpeakers()
    }

    func deleteKnownSpeaker(id: UUID) {
        _ = try? knownSpeakerProfileStore.deleteProfile(id: id)
        if expandedKnownSpeakerID == id {
            expandedKnownSpeakerID = nil
        }
        refreshKnownSpeakers()
    }

    func removeKnownSpeakerClip(profileID: UUID, clipID: UUID) {
        guard var profile = knownSpeakers.first(where: { $0.id == profileID }),
            let clip = profile.exampleClips.first(where: { $0.id == clipID })
        else {
            return
        }

        profile.exampleClips.removeAll { $0.id == clipID }
        profile.updatedAt = Date()
        _ = try? knownSpeakerProfileStore.save(profile)
        try? knownSpeakerProfileStore.removeExampleClipFile(clip)
        refreshKnownSpeakers()
    }

}
