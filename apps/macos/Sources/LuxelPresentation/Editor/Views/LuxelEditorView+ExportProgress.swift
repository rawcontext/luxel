import LuxelCore
import SwiftUI

extension LuxelEditorView {
    var exportProgressPanel: some View {
        LuxelGlassIsland(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 12) {
                if model.isExporting, !model.exportJobs.isEmpty {
                    if model.exportJobs.count > 1 {
                        Text("Exporting \(model.exportJobs.count) files")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        ProgressView(value: model.exportProgressValue)
                            .progressViewStyle(.linear)
                            .accessibilityLabel("Overall export progress")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.exportJobs) { job in
                            exportJobRow(
                                job,
                                isProminent: model.exportJobs.count == 1
                            )
                        }
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if showsExportPanelStatusIcon {
                            Image(systemName: model.exportPanelSystemImage)
                                .foregroundStyle(exportPanelTint)
                                .frame(width: 18)
                        }

                        Text(model.exportPanelTitle)
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        Spacer(minLength: 8)
                    }

                    Text(model.exportPanelMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    if !model.exportJobs.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(model.exportJobs) { job in
                                exportJobRow(job)
                            }
                        }
                    }
                }

                exportProgressActions
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    var exportProgressActions: some View {
        HStack(spacing: 8) {
            if model.canCancelExport {
                Button {
                    model.cancelExport()
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                }
                .help("Cancel the export in progress.")
            }

            if let exportedURL = model.exportedURL {
                Button {
                    model.openExportedFile()
                } label: {
                    Label("Open", systemImage: "arrow.up.forward.app")
                }
                .help("Open the exported file.")

                Menu {
                    exportedFileMenuItems(exportedURL: exportedURL)
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .help("More exported file actions.")
            }

            if model.canRetryExport {
                Button {
                    model.retryExport()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .help("Run the export again.")
            }
        }
        .labelStyle(.titleAndIcon)
    }

    @ViewBuilder
    func exportedFileMenuItems(exportedURL: URL) -> some View {
        Button {
            model.revealExportedFile()
        } label: {
            Label("Reveal in Finder", systemImage: "magnifyingglass")
        }

        Button {
            model.saveExportedFileAs()
        } label: {
            Label("Save a Copy...", systemImage: "tray.and.arrow.down")
        }

        Button {
            model.openExportedFileWithApplication()
        } label: {
            Label("Open With...", systemImage: "square.grid.3x3")
        }

        Divider()

        Button {
            model.copyExportedFile()
        } label: {
            Label("Copy File", systemImage: "doc.on.clipboard")
        }

        Button {
            model.copyExportedFilePath()
        } label: {
            Label("Copy Path", systemImage: "doc.text")
        }

        ShareLink(item: exportedURL) {
            Label("Share...", systemImage: "square.and.arrow.up")
        }
    }

    var exportPanelTint: Color {
        switch model.status {
        case .exported, .exportedBatch, .saved:
            .green
        case .failed:
            .red
        case .canceled:
            .secondary
        default:
            .accentColor
        }
    }

    func exportJobRow(_ job: ExportJobSnapshot, isProminent: Bool = false) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(job.format.prettyName)
                        .font(isProminent ? .subheadline : .caption)
                        .fontWeight(.semibold)

                    Spacer(minLength: 8)

                    Text(job.statusSummary)
                        .font(isProminent ? .caption : .caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                ProgressView(value: job.progressValue)
                    .progressViewStyle(.linear)
                    .accessibilityLabel(job.format.prettyName)
                    .accessibilityValue(job.statusSummary)
            }

            if job.fileURL != nil {
                Button {
                    model.revealExportJob(job)
                } label: {
                    Label("Reveal", systemImage: "magnifyingglass")
                }
                .labelStyle(.iconOnly)
                .help("Reveal in Finder")
            }
        }
    }

    var showsExportPanelStatusIcon: Bool {
        model.exportPanelSystemImage != "checkmark.circle"
    }
}
