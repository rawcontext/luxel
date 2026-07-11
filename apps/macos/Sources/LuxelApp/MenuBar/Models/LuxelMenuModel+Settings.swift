import Foundation
import LuxelCore
import LuxelPresentation

enum CommandLineToolInstallStatus: Equatable {
    case installed(URL)
    case repaired(URL)
    case pathCommandCopied(URL)
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
        configuredEditorModel = editorModel
        editorModel.configureExportMemory(settings.perFormatExportMemory) { [weak self] format, memory in
            self?.rememberExportMemory(memory, for: format)
        }
        editorModel.configureLastSelectedExportFormat(settings.lastSelectedExportFormat) { [weak self] format in
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

    func installCommandLineTool() {
        do {
            guard let install = try commandLineToolInstallService.chooseAndInstall() else {
                return
            }

            settings.commandLineToolInstall = install
            saveSettings()
            commandLineToolInstallStatus = .installed(install.linkURL)
        } catch {
            commandLineToolInstallStatus = .failed(errorMessage(error))
        }
    }

    func repairCommandLineToolInstall() {
        guard let install = settings.commandLineToolInstall else {
            installCommandLineTool()
            return
        }

        do {
            let repairedInstall = try commandLineToolInstallService.repairInstall(install)
            settings.commandLineToolInstall = repairedInstall
            saveSettings()
            commandLineToolInstallStatus = .repaired(repairedInstall.linkURL)
        } catch {
            commandLineToolInstallStatus = .failed(errorMessage(error))
        }
    }

    func copyCommandLinePathSetupCommand() {
        let install =
            settings.commandLineToolInstall
            ?? CommandLineToolInstall(
                linkURL: commandLineToolInstallService.defaultDestination,
                directoryBookmark: BookmarkedDirectory(
                    url: commandLineToolInstallService.defaultDestination.deletingLastPathComponent(),
                    bookmarkData: Data()
                )
            )
        let command = commandLineToolInstallService.pathSetupCommand(
            for: install,
            shell: settings.commandLineShell,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
        fileWorkflowService.copyText(command)
        commandLineToolInstallStatus = .pathCommandCopied(install.linkURL)
    }

    func reconcileCommandLineToolInstallWithBundle() {
        guard let install = settings.commandLineToolInstall else {
            return
        }

        do {
            let repairedInstall = try commandLineToolInstallService.repairInstall(install)
            if repairedInstall != install {
                settings.commandLineToolInstall = repairedInstall
                saveSettings()
            }
        } catch {
        }
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
