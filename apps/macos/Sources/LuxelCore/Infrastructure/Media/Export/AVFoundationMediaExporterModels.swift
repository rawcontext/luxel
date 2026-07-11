import AVFAudio
import AVFoundation
import AudioToolbox
import CoreMedia
import Foundation

struct AVFoundationVideoExportComposition {
    let composition: AVMutableComposition
    let videoTrack: AVMutableCompositionTrack
    let audioTracks: [AVMutableCompositionTrack]
    let timeRange: CMTimeRange
}

struct AVFoundationAudioExportComposition {
    let composition: AVMutableComposition
    let audioTracks: [AVMutableCompositionTrack]
    let timeRange: CMTimeRange
}

struct AVFoundationAudioExportContext {
    let composition: AVMutableComposition
    let audioTracks: [AVMutableCompositionTrack]
    let timeRange: CMTimeRange
    let outputFileURL: URL
    let format: ExportFormat
    let audioMix: AVAudioMix?
}

struct AVFoundationAudioExportRuntime {
    let reader: AVAssetReader
    let output: AVAssetReaderAudioMixOutput
    let outputFile: AVAudioFile
    let processingFormat: AVAudioFormat
    let totalDuration: TimeInterval
}

final class AVAssetExportSessionProgressSource: @unchecked Sendable {
    private let exportSession: AVAssetExportSession

    init(_ exportSession: AVAssetExportSession) {
        self.exportSession = exportSession
    }

    var progress: Double {
        Double(exportSession.progress)
    }
}

public enum AVFoundationMediaExporterError: Error, Equatable {
    case missingVideoTrack
    case missingAudioTrack
    case cannotCreateVideoTrack
    case cannotCreateAudioTrack
    case unsupportedPreset(String)
    case unsupportedOutputFileType(String)
    case cannotCreateAudioReaderOutput
    case cannotCreateAudioBuffer
    case cannotCopyPCMData(OSStatus)
    case audioReaderFailed(String)
}
