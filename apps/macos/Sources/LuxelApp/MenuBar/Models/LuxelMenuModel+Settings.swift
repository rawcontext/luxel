import Foundation
import LuxelCore
import LuxelPresentation

enum CommandLineToolInstallStatus: Equatable {
    case installed(URL)
    case failed(String)
}

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
        editorModel.configureExportMemory(settings.perFormatExportMemory) {
            [weak self] format, memory in
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

    func installCommandLineTool() {
        do {
            let destination = try commandLineToolInstallService.installToDefaultLocation()
            commandLineToolInstallStatus = .installed(destination)
        } catch {
            commandLineToolInstallStatus = .failed(errorMessage(error))
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
