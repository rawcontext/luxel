import AVFoundation
import CoreMedia
import Foundation

extension TimeRange {
    var cmTimeRange: CMTimeRange {
        CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 60_000),
            duration: CMTime(seconds: duration, preferredTimescale: 60_000)
        )
    }
}

extension AVMutableCompositionTrack {
    func insert(_ sourceSegments: [SourceMediaSegment], from sourceTrack: AVAssetTrack) throws {
        for segment in sourceSegments {
            try insertTimeRange(
                segment.sourceRange.cmTimeRange,
                of: sourceTrack,
                at: CMTime(seconds: segment.outputStart, preferredTimescale: 60_000)
            )
        }
    }
}

extension AVURLAsset {
    func firstTrack(
        withMediaType mediaType: AVMediaType,
        or error: @autoclosure () -> any Swift.Error
    ) async throws -> AVAssetTrack {
        guard let track = try await loadTracks(withMediaType: mediaType).first else {
            throw error()
        }
        return track
    }
}

extension CMSampleBuffer {
    func copiedPCMData(
        missingDataError: @autoclosure () -> any Swift.Error,
        copyError: (OSStatus) -> any Swift.Error
    ) throws -> Data {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(self) else {
            throw missingDataError()
        }
        let dataLength = CMBlockBufferGetDataLength(blockBuffer)
        guard dataLength > 0 else {
            throw missingDataError()
        }

        var data = Data(count: dataLength)
        let status = data.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return OSStatus(paramErr)
            }
            return CMBlockBufferCopyDataBytes(
                blockBuffer,
                atOffset: 0,
                dataLength: dataLength,
                destination: baseAddress
            )
        }
        guard status == noErr else {
            throw copyError(status)
        }
        return data
    }
}
