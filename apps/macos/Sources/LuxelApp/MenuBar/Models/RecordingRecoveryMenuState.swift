import Foundation
import LuxelCore

enum RecordingRecoveryMenuState: Equatable {
    case recovered(PastRecording)
    case knownCorrupt(fileURL: URL, reason: String)
    case unknownCorrupt(fileURL: URL, reason: String)
}

struct RecoveryPrompt: Equatable {
    let fileURL: URL
    let reason: String
    let isKnownRepairable: Bool

    var title: String {
        isKnownRepairable
            ? LuxelLocalization.string("Repairable Recording Found")
            : LuxelLocalization.string("Corrupt Recording Found")
    }

    var message: String {
        if isKnownRepairable {
            return LuxelLocalization.format(
                "recovery.repairable.message",
                defaultValue: "Luxel found an interrupted recording with a known corruption signature. The "
                    + "file was left in place so you can inspect it or try a repair workflow "
                    + "later.\n\n%@",
                reason)
        }

        return LuxelLocalization.format(
            "recovery.corrupt.message",
            defaultValue: "Luxel found an interrupted recording that appears corrupt. A diagnostic was "
                + "recorded so this failure can be investigated.\n\n%@",
            reason)
    }
}
