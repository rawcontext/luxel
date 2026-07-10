import LuxelCore
import SwiftUI

extension LuxelEditorView {
    var exportProgressPanel: some View {
        LuxelGlassIsland(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 12) {
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

                if model.exportJobs.count > 1, model.isExporting || model.exportProgress != nil {
                    ProgressView(value: model.exportProgressValue)
                        .progressViewStyle(.linear)
                }

                if !model.exportJobs.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.exportJobs) { job in
                            exportJobRow(job)
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

    func exportJobRow(_ job: ExportJobSnapshot) -> some View {
        HStack(spacing: 8) {
            if showsExportJobStatusIcon(job) {
                Image(systemName: exportJobSystemImage(job))
                    .foregroundStyle(exportJobTint(job))
                    .frame(width: 18)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(job.format.prettyName)
                        .font(.caption)
                        .fontWeight(.semibold)

                    Spacer(minLength: 8)

                    Text(job.statusSummary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                ProgressView(value: job.progressValue)
                    .progressViewStyle(.linear)
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

    func exportJobSystemImage(_ job: ExportJobSnapshot) -> String {
        switch job.progress?.phase {
        case .preparing, .enhancingAudio, .exporting:
            "arrow.triangle.2.circlepath"
        case .completed:
            "checkmark.circle"
        case .canceled:
            "xmark.circle"
        case .none:
            "clock"
        }
    }

    var showsExportPanelStatusIcon: Bool {
        model.exportPanelSystemImage != "checkmark.circle"
    }

    func showsExportJobStatusIcon(_ job: ExportJobSnapshot) -> Bool {
        job.progress?.phase != .completed
    }

    func exportJobTint(_ job: ExportJobSnapshot) -> Color {
        switch job.progress?.phase {
        case .completed:
            .green
        case .canceled:
            .secondary
        default:
            .accentColor
        }
    }
}
