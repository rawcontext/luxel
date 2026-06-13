import SwiftUI

struct LuxelRecordingStatusMessages: View {
    let model: LuxelMenuModel

    var body: some View {
        if let recordingStatusMessage = model.recordingStatusMessage {
            Text(recordingStatusMessage)
                .font(.caption)
                .foregroundStyle(model.recordingStatusTint)
                .lineLimit(2)
        }

        if model.shouldShowRecordingAudioLevelMeter {
            AudioLevelMeterView(sample: model.audioLevelSample)
        }

        if let recordingNoticeMessage = model.recordingNoticeMessage {
            Text(recordingNoticeMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }

        if let recordingActionErrorMessage = model.recordingActionErrorMessage {
            Text(recordingActionErrorMessage)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
        }

        if let quickExportStatusMessage = model.quickExportStatusMessage {
            Text(quickExportStatusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }

        if let recoveryStatusMessage = model.recoveryStatusMessage {
            Text(recoveryStatusMessage)
                .font(.caption)
                .foregroundStyle(model.recoveryStatusTint)
                .lineLimit(2)
        }
    }
}
