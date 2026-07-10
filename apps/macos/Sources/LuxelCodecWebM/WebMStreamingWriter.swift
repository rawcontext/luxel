import Foundation
import LuxelCore

final class WebMStreamingWriter {
    static let timestampScale: UInt64 = 1_000_000
    static let seekHeadReservationSize = 512
    static let clusterDurationLimit: Int64 = 2_000
    static let clusterPayloadLimit = 1_000_000

    let outputFileURL: URL
    let pixelSize: PixelSize
    let hasAudio: Bool
    let fileSystem: FileManager

    var fileHandle: FileHandle?
    var fileOffset: UInt64 = 0
    var segmentSizeOffset: UInt64 = 0
    var segmentDataStartOffset: UInt64 = 0
    var infoPosition: UInt64 = 0
    var tracksPosition: UInt64 = 0
    var firstClusterPosition: UInt64?
    var cuesPosition: UInt64?
    var durationPayloadOffset: UInt64 = 0
    var maxEndTimecode: Int64 = 0
    var currentCluster: WebMCluster?
    var cuePoints: [WebMCuePoint] = []

    init(
        outputFileURL: URL,
        pixelSize: PixelSize,
        hasAudio: Bool,
        fileSystem: FileManager
    ) {
        self.outputFileURL = outputFileURL
        self.pixelSize = pixelSize
        self.hasAudio = hasAudio
        self.fileSystem = fileSystem
    }
}
