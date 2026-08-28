@preconcurrency import AVFoundation
import CoreMedia

enum AVAssetWriterCrashRecovery {
    static let initialFragmentInterval = CMTime(seconds: 1, preferredTimescale: 600)
    static let fragmentInterval = CMTime(seconds: 10, preferredTimescale: 600)

    static func configure(_ writer: AVAssetWriter) {
        writer.initialMovieFragmentInterval = initialFragmentInterval
        writer.movieFragmentInterval = fragmentInterval
    }
}
