import Foundation
import LuxelCore
import SwiftUI

struct LuxelRecentRecordings: View {
    let model: LuxelMenuModel
    let openRecording: (URL) -> Void

    var body: some View {
        if !model.recentRecordings.isEmpty {
            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Recent")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                ForEach(model.recentRecordings.prefix(5), id: \.fileURL) { recording in
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
            return "\(export.format.prettyName) - \(ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file))"
        }

        return export.format.prettyName
    }
}
