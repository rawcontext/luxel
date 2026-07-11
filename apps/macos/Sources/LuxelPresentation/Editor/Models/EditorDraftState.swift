import Foundation
import LuxelCore

struct EditorDraftState: Equatable, Sendable {
    static let defaults = EditorDraftState(
        format: .mp4,
        selectedFormats: [.mp4],
        trimStart: 0,
        trimEnd: 1,
        sizePreset: .original,
        outputWidth: 1280,
        outputHeight: 720,
        frameRate: 60,
        playbackSpeed: .normal,
        shouldMute: false,
        audioVolume: 1,
        normalizeAudio: false,
        studioVoiceEnabled: false,
        shouldCrop: true,
        quality: .balanced,
        gifLoopModeKind: .forever,
        gifLoopCount: 3,
        gifDithering: .auto,
        transcriptEditPlan: .empty
    )

    let format: ExportFormat
    let selectedFormats: [ExportFormat]
    let trimStart: TimeInterval
    let trimEnd: TimeInterval
    let sizePreset: EditorSizePreset?
    let outputWidth: Int
    let outputHeight: Int
    let frameRate: Int
    let playbackSpeed: PlaybackSpeed
    let shouldMute: Bool
    let audioVolume: Double
    let normalizeAudio: Bool
    let studioVoiceEnabled: Bool
    let shouldCrop: Bool
    let quality: ExportQuality
    let gifLoopModeKind: EditorGIFLoopModeKind
    let gifLoopCount: Int
    let gifDithering: GIFDitheringMode
    let transcriptEditPlan: TimelineEditPlan
}
