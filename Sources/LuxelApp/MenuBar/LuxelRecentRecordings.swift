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
                        if recording.options.isAudioOnly {
                            model.revealRecording(recording)
                        } else {
                            openRecording(recording.fileURL)
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
                            Image(systemName: recording.options.isAudioOnly ? "waveform" : "clock")
                        }
                    }
                    .help(recording.fileURL.path)
                }
            }
        }
    }

    private func recentRecordingSubtitle(for recording: PastRecording) -> String? {
        guard let export = recording.latestExport else {
            return nil
        }

        if let fileSizeBytes = export.fileSizeBytes {
            return "\(export.format.prettyName) - \(ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file))"
        }

        return export.format.prettyName
    }
}
