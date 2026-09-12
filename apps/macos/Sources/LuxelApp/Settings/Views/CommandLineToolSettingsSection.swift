import LuxelCore
import LuxelPresentation
import SwiftUI

struct CommandLineToolSettingsSection: View {
    @Bindable var model: LuxelMenuModel

    var body: some View {
        SettingsIslandGroup(
            LuxelLocalization.string(
                "settings.commandLine.title",
                defaultValue: "Command Line"
            ),
            footer: LuxelLocalization.string(
                "settings.commandLine.footer",
                defaultValue: "The external luxel command asks this app to perform every action."
            )
        ) {
            SettingsRow(
                LuxelLocalization.string(
                    "settings.commandLine.control",
                    defaultValue: "Command Line Control"
                )
            ) {
                Toggle(
                    LuxelLocalization.string(
                        "settings.commandLine.control",
                        defaultValue: "Command Line Control"
                    ),
                    isOn: Binding(
                        get: { model.settings.commandLineControlEnabled },
                        set: { model.setCommandLineControlEnabled($0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
            }

            LuxelGlassRowDivider()

            SettingsRow(
                LuxelLocalization.string(
                    "settings.commandLine.repository",
                    defaultValue: "Install and Documentation"
                )
            ) {
                Link(
                    LuxelLocalization.string(
                        "settings.commandLine.openGitHub",
                        defaultValue: "Open GitHub"
                    ),
                    destination: URL(string: "https://github.com/rawcontext/luxel/tree/master/apps/cli")!
                )
            }
        }

        pairedClients
        folderAccess
    }

    private var pairedClients: some View {
        SettingsIslandGroup(
            LuxelLocalization.string(
                "settings.commandLine.pairedClients",
                defaultValue: "Paired Clients"
            )
        ) {
            if model.settings.commandLinePairedClients.isEmpty {
                SettingsRow {
                    Text(
                        LuxelLocalization.string(
                            "settings.commandLine.noPairedClients",
                            defaultValue: "No command line clients are paired."
                        )
                    )
                    .foregroundStyle(.secondary)
                }
            } else {
                ForEach(model.settings.commandLinePairedClients) { client in
                    SettingsRow(client.name) {
                        Button(
                            LuxelLocalization.string(
                                "settings.commandLine.revoke",
                                defaultValue: "Revoke"
                            )
                        ) {
                            model.revokeCommandLineClient(client.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var folderAccess: some View {
        SettingsIslandGroup(
            LuxelLocalization.string(
                "settings.commandLine.fileAccess",
                defaultValue: "File Access"
            ),
            footer: LuxelLocalization.string(
                "settings.commandLine.fileAccessFooter",
                defaultValue:
                    "Movies, the recording folder, and folders you add are available to command line requests."
            )
        ) {
            SettingsRow(
                LuxelLocalization.string(
                    "settings.commandLine.moviesFolder",
                    defaultValue: "Movies Folder"
                )
            ) {
                Text(
                    FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)
                        .first?.userVisiblePath ?? "~/Movies"
                )
                .lineLimit(1)
                .truncationMode(.middle)
            }

            LuxelGlassRowDivider()

            SettingsRow(
                LuxelLocalization.string(
                    "settings.commandLine.recordingFolder",
                    defaultValue: "Recording Folder"
                )
            ) {
                Text(model.settings.recordingsDirectory.userVisiblePath)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            ForEach(model.settings.commandLineFolderGrants) { grant in
                LuxelGlassRowDivider()
                SettingsRow(grant.directory.url.lastPathComponent) {
                    Button(
                        LuxelLocalization.string(
                            "settings.commandLine.removeFolder",
                            defaultValue: "Remove"
                        )
                    ) {
                        model.removeCommandLineFolderGrant(grant.id)
                    }
                    .buttonStyle(.plain)
                }
            }

            LuxelGlassRowDivider()

            SettingsRow {
                Button {
                    model.addCommandLineFolderGrant()
                } label: {
                    SettingsCapsuleButtonLabel(
                        LuxelLocalization.string(
                            "settings.commandLine.addFolder",
                            defaultValue: "Add Folder"
                        ),
                        systemImage: "folder.badge.plus"
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
