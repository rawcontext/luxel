@preconcurrency import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import LuxelTestSupport
import ScreenCaptureKit
import Testing

@testable import LuxelCore

@Suite("ScreenCaptureKit recording fragments")
struct ScreenCaptureKitRecordingFragmentTests {
    @Test("H.264 recording survives a static-screen gap across recovery fragments")
    func recordingSurvivesFrameDeliveryGap() async throws {
        let outputURL = temporaryTestFileURL(pathExtension: "mp4")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let request = try RecordingRequest(
            target: .area(
                displayID: DisplayID(1), rect: CaptureRect(x: 188, y: 111, width: 64, height: 64)),
            outputFileURL: outputURL,
            pixelSize: PixelSize(width: 64, height: 64),
            frameRate: .fps60
        )
        let segment = try RecordingWriterSegment(
            request: request, outputFileURL: outputURL, audioLevelHandler: nil)
        let startTime = CMTime(seconds: 1_000_000, preferredTimescale: 1_000_000_000)

        for index in 0..<320 where !(index > 100 && index < 140) {
            let time = CMTimeAdd(startTime, CMTime(value: Int64(index), timescale: 20))
            segment.append(try screenSample(at: time), outputType: .screen)
            try await Task.sleep(for: .milliseconds(2))
        }

        let savedURL = try await withCheckedThrowingContinuation { continuation in
            segment.finish(fileManager: .default, continuation: continuation)
        }
        #expect(savedURL == outputURL)
        let asset = AVURLAsset(url: outputURL)
        #expect(try await asset.load(.isPlayable))
        #expect(try await asset.load(.duration).seconds >= 15)
        let track = try #require(await asset.loadTracks(withMediaType: .video).first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        #expect(reader.startReading())
        var frameCount = 0
        while output.copyNextSampleBuffer() != nil {
            frameCount += 1
        }
        #expect(reader.status == .completed)
        #expect(frameCount > 200)
    }

    private func screenSample(at time: CMTime) throws -> CMSampleBuffer {
        var pixelBuffer: CVPixelBuffer?
        #expect(
            CVPixelBufferCreate(
                kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA, nil, &pixelBuffer) == noErr)
        let imageBuffer = try #require(pixelBuffer)
        CVPixelBufferLockBaseAddress(imageBuffer, [])
        if let baseAddress = CVPixelBufferGetBaseAddress(imageBuffer) {
            memset(baseAddress, 0, CVPixelBufferGetDataSize(imageBuffer))
        }
        CVPixelBufferUnlockBaseAddress(imageBuffer, [])
        var formatDescription: CMVideoFormatDescription?
        #expect(
            CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault, imageBuffer: imageBuffer,
                formatDescriptionOut: &formatDescription) == noErr)
        var timing = CMSampleTimingInfo(
            duration: .invalid, presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        #expect(
            CMSampleBufferCreateReadyWithImageBuffer(
                allocator: kCFAllocatorDefault, imageBuffer: imageBuffer,
                formatDescription: try #require(formatDescription), sampleTiming: &timing,
                sampleBufferOut: &sampleBuffer) == noErr)
        let sample = try #require(sampleBuffer)
        let attachments = try #require(
            CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) as? [NSMutableDictionary])
        let frameInfo = try #require(attachments.first)
        frameInfo[SCStreamFrameInfo.status.rawValue] = SCFrameStatus.complete.rawValue
        return sample
    }
}
