import Foundation
import LuxelCore

struct PreviewAudioMixTaskID: Equatable, Sendable {
    let sourceFileURL: URL
    let format: ExportFormat
    let trimStart: TimeInterval
    let trimEnd: TimeInterval
    let shouldMute: Bool
    let audioVolume: Double
    let normalizeAudio: Bool
}
