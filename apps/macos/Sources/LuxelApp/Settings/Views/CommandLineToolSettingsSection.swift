import LuxelCore
import SwiftUI

struct CommandLineToolSettingsSection: View {
    @Bindable var model: LuxelMenuModel

    var body: some View {
        Section("Command Line Tool") {
            if let install = model.settings.commandLineToolInstall {
                LabeledContent("Installed Link") {
                    Text(install.linkURL.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }

            LabeledContent("Install Location") {
                HStack {
                    Button {
                        model.installCommandLineTool()
                    } label: {
                        Label(
                            model.settings.commandLineToolInstall == nil
                                ? "Install luxel" : "Change Location",
                            systemImage: "terminal")
                    }
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
                            Label(
                                LuxelLocalization.string(
                                    "settings.commandLine.repair",
                                    defaultValue: "Repair"),
                                systemImage: "arrow.triangle.2.circlepath")
                        }
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

            LabeledContent("Shell") {
                Picker(selection: $model.settings.commandLineShell) {
                    ForEach(CommandLineShell.allCases) { shell in
                        Text(shell.displayName).tag(shell)
                    }
                } label: {
                    Text(
                        LuxelLocalization.string(
                            "settings.commandLine.shell",
                            defaultValue: "Shell")
                    )
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 140)
                .help(
                    LuxelLocalization.string(
                        "settings.commandLine.shellHelp",
                        defaultValue:
                            "Choose which shell profile the copied PATH command updates.")
                )
            }

            LabeledContent("Shell PATH") {
                Button {
                    model.copyCommandLinePathSetupCommand()
                } label: {
                    Label(
                        LuxelLocalization.string(
                            "settings.commandLine.copyPathCommand",
                            defaultValue: "Copy PATH Command"),
                        systemImage: "doc.on.doc")
                }
                .help(
                    LuxelLocalization.string(
                        "settings.commandLine.copyPathCommandHelp",
                        defaultValue:
                            "Copy a PATH setup command for the selected shell.")
                )
            }

            if let installStatus = model.commandLineToolInstallStatus {
                Label(installStatus.message, systemImage: installStatus.systemImage)
                    .font(.caption)
                    .foregroundStyle(installStatus.tint)
            }
        }
    }
}
