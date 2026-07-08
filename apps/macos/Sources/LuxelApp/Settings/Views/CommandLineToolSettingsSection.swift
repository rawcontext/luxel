import LuxelCore
import LuxelPresentation
import SwiftUI

struct CommandLineToolSettingsSection: View {
    @Bindable var model: LuxelMenuModel

    var body: some View {
        SettingsIslandGroup("Command Line Tool") {
            if let install = model.settings.commandLineToolInstall {
                SettingsRow("Installed Link") {
                    Text(install.linkURL.path)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                LuxelGlassRowDivider()
            }

            SettingsRow("Install Location") {
                HStack(spacing: 8) {
                    Button {
                        model.installCommandLineTool()
                    } label: {
                        SettingsCapsuleButtonLabel(
                            model.settings.commandLineToolInstall == nil
                                ? "Install luxel" : "Change Location",
                            systemImage: "terminal"
                        )
                    }
                    .buttonStyle(.plain)
                    .help(
                        LuxelLocalization.format(
                            "settings.commandLine.installDestinationHelp",
                            defaultValue: "Install to %@",
                            model.commandLineToolInstallService.defaultDestination.path)
                    )

                    if model.settings.commandLineToolInstall != nil {
                        Button {
                            model.repairCommandLineToolInstall()
                        } label: {
                            SettingsCapsuleButtonLabel(
                                LuxelLocalization.string(
                                    "settings.commandLine.repair",
                                    defaultValue: "Repair"),
                                systemImage: "arrow.triangle.2.circlepath"
                            )
                        }
                        .buttonStyle(.plain)
                        .help(
                            LuxelLocalization.string(
                                "settings.commandLine.repairHelp",
                                defaultValue:
                                    "Update the installed command to point at this Luxel app.")
                        )
                    }
                }
            }
            .help("Install the command line helper for terminal automation.")

            LuxelGlassRowDivider()

            SettingsRow("Shell") {
                SettingsMenuPicker(
                    selection: $model.settings.commandLineShell,
                    options: Array(CommandLineShell.allCases)
                ) { shell in
                    shell.displayName
                }
                .help(
                    LuxelLocalization.string(
                        "settings.commandLine.shellHelp",
                        defaultValue:
                            "Choose which shell profile the copied PATH command updates.")
                )
            }

            LuxelGlassRowDivider()

            SettingsRow("Shell PATH") {
                Button {
                    model.copyCommandLinePathSetupCommand()
                } label: {
                    SettingsCapsuleButtonLabel(
                        LuxelLocalization.string(
                            "settings.commandLine.copyPathCommand",
                            defaultValue: "Copy PATH Command"),
                        systemImage: "doc.on.doc"
                    )
                }
                .buttonStyle(.plain)
                .help(
                    LuxelLocalization.string(
                        "settings.commandLine.copyPathCommandHelp",
                        defaultValue:
                            "Copy a PATH setup command for the selected shell.")
                )
            }

            if let installStatus = model.commandLineToolInstallStatus {
                LuxelGlassRowDivider()

                Label(installStatus.message, systemImage: installStatus.systemImage)
                    .font(.caption)
                    .foregroundStyle(installStatus.tint)
                    .frame(minHeight: LuxelGlassTheme.settingsRowHeight)
            }
        }
    }
}
