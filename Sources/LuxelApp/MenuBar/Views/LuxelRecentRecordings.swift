import Foundation
import LuxelCore
import SwiftUI

struct LuxelRecentRecordings: View {
    @Bindable var model: LuxelMenuModel
    let openRecording: (URL) -> Void

    var body: some View {
        if !model.recentRecordings.isEmpty {
            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Recent")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Spacer()

                    if model.canFilterRecentRecordings {
                        Picker("Show", selection: $model.recentRecordingFilter) {
                            ForEach(RecordingHistoryFilter.allCases, id: \.self) { filter in
                                Text(filter.recentMenuLabel).tag(filter)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(width: 116)
                    }
                }

                if model.filteredRecentRecordings.isEmpty {
                    Text(model.recentRecordingFilter.emptyRecentMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    ForEach(model.filteredRecentRecordings, id: \.fileURL) { recording in
                        Button {
                            if opensInEditor(recording) {
                                openRecording(recording.fileURL)
                            } else {
                                model.revealRecording(recording)
                            }
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(recording.name)
                                        .lineLimit(1)

                                    if let subtitle = recentRecordingSubtitle(for: recording) {
                                        Text(subtitle)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            } icon: {
                                Image(systemName: recentRecordingSystemImage(for: recording))
                            }
                        }
                        .help(recording.fileURL.path)
                    }
                }
            }
        }
    }

    private func opensInEditor(_ recording: PastRecording) -> Bool {
        recording.kind == .recording && !recording.options.isAudioOnly
    }

    private func recentRecordingSystemImage(for recording: PastRecording) -> String {
        switch recording.kind {
        case .recording:
            recording.options.isAudioOnly ? "waveform" : "clock"
        case .screenshot:
            "camera"
        }
    }

    private func recentRecordingSubtitle(for recording: PastRecording) -> String? {
        if recording.kind == .screenshot {
            let fileExtension = recording.fileURL.pathExtension
            return fileExtension.isEmpty ? "Screenshot" : "\(fileExtension.uppercased()) screenshot"
        }

        guard let export = recording.latestExport else {
            return nil
        }

        if let fileSizeBytes = export.fileSizeBytes {
            let fileSize = ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
            return "\(export.format.prettyName) - \(fileSize)"
        }

        return export.format.prettyName
    }
}

private extension RecordingHistoryFilter {
    var recentMenuLabel: String {
        switch self {
        case .all:
            "All"
        case .recordings:
            "Recordings"
        case .screenshots:
            "Screenshots"
        }
    }

    var emptyRecentMessage: String {
        switch self {
        case .all:
            "No recent items"
        case .recordings:
            "No recent recordings"
        case .screenshots:
            "No recent screenshots"
        }
    }
}
