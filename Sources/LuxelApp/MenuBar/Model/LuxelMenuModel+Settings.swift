import LuxelCore
import LuxelPresentation

@MainActor
extension LuxelMenuModel {
    func saveSettings() {
        try? settingsStore.save(settings)
    }

    func configureEditor(_ editorModel: LuxelEditorModel) {
        editorModel.configureExportMemory(settings.perFormatExportMemory) { [weak self] format, memory in
            self?.rememberExportMemory(memory, for: format)
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
    }

    func chooseRecordingsDirectory() {
        do {
            guard let directory = try bookmarkedDirectoryPicker.chooseDirectory(
                currentDirectory: settings.recordingsDirectory
            ) else {
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
    private func rememberExportMemory(_ memory: ExportMemory, for format: ExportFormat) {
        settings.perFormatExportMemory[format] = memory
        saveSettings()
    }
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLoginService.setEnabled(enabled)
            launchAtLogin = launchAtLoginService.isEnabled()
        } catch {
            launchAtLogin = launchAtLoginService.isEnabled()
        }
    }
}
