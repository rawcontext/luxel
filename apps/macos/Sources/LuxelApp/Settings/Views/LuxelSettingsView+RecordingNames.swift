import AppKit
import LuxelCore
import LuxelPresentation
import SwiftUI

extension LuxelSettingsView {
    var recordingNamesSettingsGroup: some View {
        SettingsIslandGroup(
            "Recording names",
            footer: "Uses the first 200 transcript words on this Mac. Otherwise, names use the capture type and time."
        ) {
            Toggle(
                "Name recordings with Apple Intelligence",
                isOn: Binding {
                    model.automaticRecordingTitlesEnabled
                } set: {
                    model.setAutomaticRecordingTitles($0)
                }
            )
            .toggleStyle(LuxelGlassSwitchToggleStyle())
            .disabled(model.recordingTitleModelAvailability == .unsupported)
            .frame(minHeight: LuxelGlassTheme.settingsRowHeight)

            LuxelGlassRowDivider()

            VStack(alignment: .leading, spacing: 8) {
                Text(recordingTitleModelStatus)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if model.recordingTitleModelAvailability != .available,
                    model.recordingTitleModelAvailability != .unsupported {
                    Button("Set Up Apple Intelligence") { model.openAppleIntelligenceSetup() }
                }
                Text("Recordings are saved in monthly folders, with a folder for each recording.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        }
        .task {
            while !Task.isCancelled {
                model.refreshRecordingTitleModel()
                do { try await Task.sleep(for: .seconds(3)) } catch { break }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshRecordingTitleModel()
        }
    }

    private var recordingTitleModelStatus: String {
        switch model.recordingTitleModelAvailability {
        case .available: LuxelLocalization.string("Apple Intelligence is ready.")
        case .notEnabled:
            LuxelLocalization.string("Enable Apple Intelligence in System Settings. macOS downloads the model.")
        case .downloading: LuxelLocalization.string("macOS is preparing the Apple Intelligence model.")
        case .unsupported: LuxelLocalization.string("This Mac does not support Apple Intelligence.")
        case .unavailable: LuxelLocalization.string("Apple Intelligence is currently unavailable.")
        }
    }
}
