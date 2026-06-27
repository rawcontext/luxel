import Foundation
import LuxelCore

struct ExportEstimateTaskID: Equatable, Hashable {
    let sourceFileURL: URL
    let formats: [ExportFormat]
    let trimStart: TimeInterval
    let trimEnd: TimeInterval
    let outputWidth: Int
    let outputHeight: Int
    let frameRate: Int
    let playbackSpeed: Double
    let quality: ExportQuality
    let gifLoopModeKind: EditorGIFLoopModeKind?
    let gifLoopCount: Int?
    let gifDithering: GIFDitheringMode?
    let shouldMute: Bool
    let shouldCrop: Bool
}
