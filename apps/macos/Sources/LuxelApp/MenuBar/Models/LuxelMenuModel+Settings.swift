import Foundation
import LuxelCore
import LuxelPresentation

@MainActor
extension LuxelMenuModel {
    func saveSettings() {
        try? settingsStore.save(settings)
    }

    func dismissNotificationReminder() {
        guard settings.notificationReminder else {
            return
        }

        settings.notificationReminder = false
        saveSettings()
    }

    func configureEditor(_ editorModel: LuxelEditorModel) {
        configuredEditorModel = editorModel
        editorModel.configureExportMemory(settings.perFormatExportMemory) {
            [weak self] format, memory in
            self?.rememberExportMemory(memory, for: format)
        }
        editorModel.configureLastSelectedExportFormat(settings.lastSelectedExportFormat) {
            [weak self] format in
            self?.rememberLastSelectedExportFormat(format)
        }
        editorModel.configureDiscard(
            confirmDiscard: settings.confirmDiscard,
            onDiscard: { [weak self] _ in
                self?.refreshRecentRecordings()
            },
            onConfirmDiscardChange: { [weak self] confirmDiscard in
                self?.settings.confirmDiscard = confirmDiscard
                self?.saveSettings()
            }
        )
        editorModel.configureSourceFileRename { [weak self] oldURL, newURL in
            try self?.recordingHistoryService.renameRecordingSource(from: oldURL, to: newURL)
            self?.refreshRecentRecordings()
        }
    }

    func chooseRecordingsDirectory() {
        do {
            guard
                let directory = try bookmarkedDirectoryPicker.chooseDirectory(
                    currentDirectory: settings.recordingsDirectory
                )
            else {
                return
            }

            recordingActionErrorMessage = nil
            settings.recordingsDirectory = directory.url
            settings.recordingsDirectoryBookmark = directory
            saveSettings()
        } catch {
            recordingActionErrorMessage = errorMessage(error)
        }
    }

    func addCommandLineFolderGrant() {
        do {
            guard
                let directory = try bookmarkedDirectoryPicker.chooseDirectory(
                    currentDirectory: settings.recordingsDirectory
                )
            else {
                return
            }
            guard
                !settings.commandLineFolderGrants.contains(where: {
                    $0.directory.url.standardizedFileURL == directory.url.standardizedFileURL
                })
            else {
                return
            }
            settings.commandLineFolderGrants.append(
                CommandLineFolderGrant(directory: directory)
            )
            saveSettings()
        } catch {
            recordingActionErrorMessage = errorMessage(error)
        }
    }

    func removeCommandLineFolderGrant(_ id: UUID) {
        settings.commandLineFolderGrants.removeAll { $0.id == id }
        saveSettings()
    }

    func revokeCommandLineClient(_ id: UUID) {
        settings.commandLinePairedClients.removeAll { $0.id == id }
        CommandLineCredentialStore().removeSecret(clientID: id)
        saveSettings()
    }

    func setCommandLineControlEnabled(_ enabled: Bool) {
        settings.commandLineControlEnabled = enabled
        if !enabled {
            for job in commandLineJobs.values {
                job.cancel()
            }
        }
        saveSettings()
    }

    private func rememberExportMemory(_ memory: ExportMemory, for format: ExportFormat) {
        settings.perFormatExportMemory[format] = memory
        saveSettings()
    }

    private func rememberLastSelectedExportFormat(_ format: ExportFormat) {
        settings.lastSelectedExportFormat = format
        saveSettings()
    }

    func reconcileLaunchAtLoginWithSettings() {
        applyLaunchAtLogin(settings.launchAtLogin)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        applyLaunchAtLogin(enabled)
    }

    func applyTranscriptLanguage(_ identifier: String?) {
        settings.transcriptLanguageIdentifier = identifier
        saveSettings()
        configuredEditorModel?.refreshTranscriptionConfiguration()
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if launchAtLoginService.isEnabled() != enabled {
                try launchAtLoginService.setEnabled(enabled)
            }
        } catch {
        }

        let resolved = launchAtLoginService.isEnabled()
        launchAtLogin = resolved
        if settings.launchAtLogin != resolved {
            settings.launchAtLogin = resolved
            saveSettings()
        }
    }
}
