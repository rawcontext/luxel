import AVFAudio
import AppKit
import AVFoundation
import CoreMedia
import Foundation
import LuxelCore
import Testing

extension AVFoundationMediaExporterTests {
    func fixtureURL(_ fileName: String) throws -> URL {
        try packageRootURL()
            .appending(path: "Tests/Fixtures")
            .appending(path: fileName)
    }

    func temporaryOutputURL(fileExtension: String) -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "luxel-export-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)
    }

    func videoCodecType(at fileURL: URL) async throws -> CMVideoCodecType {
        CMFormatDescriptionGetMediaSubType(try await firstVideoFormatDescription(at: fileURL))
    }

    func audioCodecType(at fileURL: URL) async throws -> FourCharCode {
        let asset = AVURLAsset(url: fileURL)
        let audioTrack = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        let formatDescription = try #require(try await audioTrack.load(.formatDescriptions).first)

        return CMFormatDescriptionGetMediaSubType(formatDescription)
    }

    func firstVideoFormatDescription(at fileURL: URL) async throws -> CMFormatDescription {
        let asset = AVURLAsset(url: fileURL)
        let videoTrack = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let formatDescription = try #require(try await videoTrack.load(.formatDescriptions).first)

        return formatDescription
    }

    func h264ProfileIDC(formatDescription: CMFormatDescription) throws -> UInt8 {
        var parameterSetPointer: UnsafePointer<UInt8>?
        var parameterSetSize = 0
        var parameterSetCount = 0
        var nalUnitHeaderLength: Int32 = 0
        let status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            formatDescription,
            parameterSetIndex: 0,
            parameterSetPointerOut: &parameterSetPointer,
            parameterSetSizeOut: &parameterSetSize,
            parameterSetCountOut: &parameterSetCount,
            nalUnitHeaderLengthOut: &nalUnitHeaderLength
        )

        guard status == noErr,
              let parameterSetPointer,
              parameterSetSize > 1
        else {
            throw AVFoundationMediaExporterTestError.missingH264ParameterSet
        }

        return parameterSetPointer[1]
    }

    func topLevelBoxTypes(at fileURL: URL) throws -> [String] {
        let data = try Data(contentsOf: fileURL)
        var offset = 0
        var boxTypes: [String] = []

        while offset + 8 <= data.count {
            let boxSize32 = data[offset..<offset + 4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            let boxTypeData = data[offset + 4..<offset + 8]
            let boxType = String(bytes: boxTypeData, encoding: .utf8) ?? ""
            boxTypes.append(boxType)

            if boxSize32 == 0 {
                break
            }

            let headerSize: Int
            let boxSize: Int
            if boxSize32 == 1 {
                guard offset + 16 <= data.count else {
                    throw AVFoundationMediaExporterTestError.invalidMP4BoxSize
                }

                headerSize = 16
                let largeSize = data[offset + 8..<offset + 16].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
                boxSize = Int(largeSize)
            } else {
                headerSize = 8
                boxSize = Int(boxSize32)
            }

            guard boxSize >= headerSize, offset + boxSize <= data.count else {
                throw AVFoundationMediaExporterTestError.invalidMP4BoxSize
            }

            offset += boxSize
        }

        return boxTypes
    }

    func boxIndex(_ boxType: String, in boxTypes: [String]) throws -> Int {
        guard let index = boxTypes.firstIndex(of: boxType) else {
            throw AVFoundationMediaExporterTestError.missingMP4Box(boxType)
        }

        return index
    }

    func writeSplitColorMovie(to outputURL: URL) async throws {
        let width = 64
        let height = 64
        let frameRate: Int32 = 10
        let frameCount = 20
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height
            ]
        )
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )

        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else {
            throw AVFoundationMediaExporterTestError.cannotAddWriterInput
        }

        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        for frameIndex in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000)
            }

            let pixelBuffer = try splitColorPixelBuffer(width: width, height: height)
            let time = CMTime(value: CMTimeValue(frameIndex), timescale: frameRate)
            guard adaptor.append(pixelBuffer, withPresentationTime: time) else {
                throw AVFoundationMediaExporterTestError.writerAppendFailed(
                    writer.error?.localizedDescription)
            }
        }

        input.markAsFinished()
        try await finishWriting(writer)
    }

    func splitColorPixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            [
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ] as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess,
              let pixelBuffer
        else {
            throw AVFoundationMediaExporterTestError.pixelBufferCreateFailed(status)
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        }

        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let baseAddress = try #require(CVPixelBufferGetBaseAddress(pixelBuffer))
        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)

        for row in 0..<height {
            for column in 0..<width {
                let offset = row * rowBytes + column * 4
                if column < width / 2 {
                    bytes[offset] = 0
                    bytes[offset + 1] = 0
                    bytes[offset + 2] = 255
                } else {
                    bytes[offset] = 255
                    bytes[offset + 1] = 0
                    bytes[offset + 2] = 0
                }
                bytes[offset + 3] = 255
            }
        }

        return pixelBuffer
    }

    func finishWriting(_ writer: AVAssetWriter) async throws {
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw AVFoundationMediaExporterTestError.writerFinishFailed(
                writer.error?.localizedDescription)
        }
    }

    func rgbPixel(
        at fileURL: URL,
        time: TimeInterval,
        x column: Int,
        y row: Int
    ) async throws -> RGBPixel {
        let asset = AVURLAsset(url: fileURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let image = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
        let bitmap = NSBitmapImageRep(cgImage: image)
        let color = try #require(bitmap.colorAt(x: column, y: row)?.usingColorSpace(.deviceRGB))

        return RGBPixel(
            red: Int((color.redComponent * 255).rounded()),
            green: Int((color.greenComponent * 255).rounded()),
            blue: Int((color.blueComponent * 255).rounded())
        )
    }

    func audioPeak(at fileURL: URL, duration: TimeInterval) async throws -> Double {
        let peaks = try await AVAssetReaderAudioPeakAnalyzer().measurePeaks(
            AudioPeakAnalysisRequest(
                inputFileURL: fileURL,
                timeRange: TimeRange(start: 0, end: duration),
                audioTracks: [.system]
            ))

        return try #require(peaks[.system])
    }

    func writeSilentAudioFixture(to fileURL: URL, duration: TimeInterval) throws {
        let sampleRate = 44_100.0
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let pcmFormat = try #require(
            AVAudioFormat(
                standardFormatWithSampleRate: sampleRate,
                channels: 1
            ))
        let buffer = try #require(
            AVAudioPCMBuffer(
                pcmFormat: pcmFormat,
                frameCapacity: frameCount
            ))
        buffer.frameLength = frameCount

        let file = try AVAudioFile(
            forWriting: fileURL,
            settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000
            ]
        )
        try file.write(from: buffer)
    }

    func writeSilentPCMFixture(to fileURL: URL, duration: TimeInterval) throws {
        let sampleRate = 48_000.0
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let format = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: 2,
                interleaved: false
            )
        )
        let buffer = try #require(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        )
        buffer.frameLength = frameCount
        let file = try AVAudioFile(
            forWriting: fileURL,
            settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true
            ],
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        try file.write(from: buffer)
    }

    func packageRootURL() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "Tests" {
            let next = url.deletingLastPathComponent()
            try #require(next.path != url.path)
            url = next
        }

        return url.deletingLastPathComponent()
    }
}

struct RGBPixel: Equatable {
    let red: Int
    let green: Int
    let blue: Int
}

private enum AVFoundationMediaExporterTestError: Error, Equatable {
    case cannotAddWriterInput
    case invalidMP4BoxSize
    case missingH264ParameterSet
    case missingMP4Box(String)
    case pixelBufferCreateFailed(CVReturn)
    case writerAppendFailed(String?)
    case writerFinishFailed(String?)
}
