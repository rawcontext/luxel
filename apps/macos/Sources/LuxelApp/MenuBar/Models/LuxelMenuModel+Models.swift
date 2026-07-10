import Foundation
import LuxelCore

@MainActor
extension LuxelMenuModel {
    var selectedTranscriptLocale: Locale {
        settings.transcriptLanguageIdentifier.map(Locale.init(identifier:)) ?? .current
    }

    var precisionLanguageIsSupported: Bool {
        (try? PrecisionTranscriptionLanguageCatalog.languageCode(for: selectedTranscriptLocale)) != nil
    }

    func observeLocalModelState() {
        localModelStateTask?.cancel()
        localModelStateTask = Task { [weak self, localModelManager] in
            let changes = await localModelManager.stateChanges()
            let state = await localModelManager.state(for: PrecisionTranscriptionEngine.modelID)
            guard !Task.isCancelled else { return }
            self?.applyPrecisionModelState(state)

            for await change in changes where change.modelID == PrecisionTranscriptionEngine.modelID {
                guard !Task.isCancelled else { return }
                self?.applyPrecisionModelState(change.state)
            }
        }
    }

    func installAndEnablePrecisionTranscription() {
        guard precisionLanguageIsSupported else {
            precisionModelErrorMessage =
                PrecisionTranscriptionError.unsupportedLanguage(
                    selectedTranscriptLocale.identifier
                ).localizedDescription
            return
        }
        precisionModelTask?.cancel()
        precisionModelErrorMessage = nil
        precisionModelTask = Task { [weak self, localModelManager] in
            do {
                _ = try await localModelManager.install(PrecisionTranscriptionEngine.modelID)
                let lease = try await localModelManager.acquire(
                    PrecisionTranscriptionEngine.modelID
                )
                await localModelManager.release(lease)
                guard !Task.isCancelled else { return }
                guard var updatedSettings = self?.settings else { return }
                updatedSettings.transcriptEnginePreference = .precision
                try self?.settingsStore.save(updatedSettings)
                self?.settings = updatedSettings
                self?.configuredEditorModel?.refreshTranscriptionConfiguration()
            } catch {
                guard !Task.isCancelled else { return }
                self?.precisionModelErrorMessage = error.localizedDescription
            }
            self?.precisionModelTask = nil
        }
    }

    func cancelPrecisionModelInstallation() {
        Task { [localModelManager] in
            await localModelManager.cancelInstallation(PrecisionTranscriptionEngine.modelID)
        }
    }

    func setPrecisionTranscriptionEnabled(_ enabled: Bool) {
        if !enabled {
            persistTranscriptEnginePreference(.appleSpeech)
            return
        }
        guard precisionLanguageIsSupported else {
            precisionModelErrorMessage =
                PrecisionTranscriptionError.unsupportedLanguage(
                    selectedTranscriptLocale.identifier
                ).localizedDescription
            return
        }
        switch precisionModelState {
        case .ready, .updateAvailable:
            persistTranscriptEnginePreference(.precision)
        default:
            break
        }
    }

    func removePrecisionModel() {
        var updatedSettings = settings
        updatedSettings.transcriptEnginePreference = .appleSpeech
        do {
            try settingsStore.save(updatedSettings)
        } catch {
            precisionModelErrorMessage = error.localizedDescription
            return
        }
        settings = updatedSettings
        configuredEditorModel?.refreshTranscriptionConfiguration()
        precisionModelTask?.cancel()
        precisionModelTask = Task { [weak self, localModelManager, precisionTranscriptionEngine] in
            await precisionTranscriptionEngine.unload()
            do {
                try await localModelManager.remove(PrecisionTranscriptionEngine.modelID)
            } catch {
                self?.precisionModelErrorMessage = error.localizedDescription
            }
            self?.precisionModelTask = nil
        }
    }

    func applyTranscriptLanguage(_ identifier: String?, switchingToApple: Bool = false) {
        if switchingToApple {
            settings.transcriptEnginePreference = .appleSpeech
        }
        settings.transcriptLanguageIdentifier = identifier
        saveSettings()
        configuredEditorModel?.refreshTranscriptionConfiguration()
    }

    private func applyPrecisionModelState(_ state: LocalModelInstallationState) {
        precisionModelState = state
        if settings.transcriptEnginePreference == .precision {
            switch state {
            case .ready, .updateAvailable, .failed(_, priorReadyInstallation: .some):
                break
            default:
                persistTranscriptEnginePreference(.appleSpeech)
            }
        }
    }

    private func persistTranscriptEnginePreference(_ preference: TranscriptEnginePreference) {
        var updatedSettings = settings
        updatedSettings.transcriptEnginePreference = preference
        do {
            try settingsStore.save(updatedSettings)
            settings = updatedSettings
            precisionModelErrorMessage = nil
            configuredEditorModel?.refreshTranscriptionConfiguration()
        } catch {
            precisionModelErrorMessage = error.localizedDescription
        }
    }
}
