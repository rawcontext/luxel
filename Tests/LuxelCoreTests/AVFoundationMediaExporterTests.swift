import AVFoundation
import CoreMedia
import Foundation
import LuxelCore
import Testing

@Suite("AVFoundation media exporter")
struct AVFoundationMediaExporterTests {
    @Test("mp4 export trims resizes changes frame rate and keeps audio")
    func mp4ExportTrimsResizesChangesFrameRateAndKeepsAudio() async throws {
        let outputURL = temporaryOutputURL(fileExtension: "mp4")
        let request = try ExportRequest(
            inputFileURL: fixtureURL("input@2x.mp4"),
            format: .mp4,
            pixelSize: PixelSize(width: 321, height: 181),
            frameRate: FrameRate(30),
            timeRange: TimeRange(start: 1, end: 1.75),
            shouldMute: false,
            shouldCrop: true
        )

        let exported = try await AVFoundationMediaExporter().export(request, to: outputURL)
        let source = try await AVFoundationMediaMetadataReader().readSourceMedia(at: outputURL)
        let expectedPixelSize = try PixelSize(width: 322, height: 182)
        let expectedFrameRate = try FrameRate(30)

        #expect(exported.fileURL == outputURL)
        #expect(exported.format == .mp4)
        #expect(exported.pixelSize == expectedPixelSize)
        #expect(!exported.shouldMute)
        #expect(source.duration > 0.70)
        #expect(source.duration < 0.80)
        #expect(source.pixelSize == exported.pixelSize)
        #expect(source.nominalFrameRate == expectedFrameRate)
        #expect(source.hasAudio)
        let codecType = try await videoCodecType(at: outputURL)
        #expect(codecType == kCMVideoCodecType_H264)

        try? FileManager.default.removeItem(at: outputURL)
    }

    @Test("hevc export writes HEVC video")
    func hevcExportWritesHEVCVideo() async throws {
        let outputURL = temporaryOutputURL(fileExtension: "mp4")
        let request = try ExportRequest(
            inputFileURL: fixtureURL("input.mp4"),
            format: .hevc,
            pixelSize: PixelSize(width: 320, height: 180),
            frameRate: FrameRate(30),
            timeRange: TimeRange(start: 1, end: 1.5),
            shouldMute: true,
            shouldCrop: false
        )

        let exported = try await AVFoundationMediaExporter().export(request, to: outputURL)
        let source = try await AVFoundationMediaMetadataReader().readSourceMedia(at: outputURL)
        let expectedPixelSize = try PixelSize(width: 320, height: 180)
        let codecType = try await videoCodecType(at: outputURL)

        #expect(exported.format == .hevc)
        #expect(source.pixelSize == expectedPixelSize)
        #expect(codecType == kCMVideoCodecType_HEVC)

        try? FileManager.default.removeItem(at: outputURL)
    }

    @Test("muted mp4 export omits audio tracks")
    func mutedMP4ExportOmitsAudioTracks() async throws {
        let outputURL = temporaryOutputURL(fileExtension: "mp4")
        let request = try ExportRequest(
            inputFileURL: fixtureURL("input@2x.mp4"),
            format: .mp4,
            pixelSize: PixelSize(width: 320, height: 180),
            frameRate: FrameRate(24),
            timeRange: TimeRange(start: 2, end: 2.5),
            shouldMute: true,
            shouldCrop: false
        )

        let exported = try await AVFoundationMediaExporter().export(request, to: outputURL)
        let source = try await AVFoundationMediaMetadataReader().readSourceMedia(at: outputURL)
        let expectedPixelSize = try PixelSize(width: 320, height: 180)
        let expectedFrameRate = try FrameRate(24)

        #expect(exported.shouldMute)
        #expect(source.pixelSize == expectedPixelSize)
        #expect(source.nominalFrameRate == expectedFrameRate)
        #expect(!source.hasAudio)

        try? FileManager.default.removeItem(at: outputURL)
    }

    @Test("h264 export uses compatibility profile metadata")
    func h264ExportUsesCompatibilityProfileMetadata() async throws {
        let outputURL = temporaryOutputURL(fileExtension: "mp4")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }
        let request = try ExportRequest(
            inputFileURL: fixtureURL("input@2x.mp4"),
            format: .mp4,
            pixelSize: PixelSize(width: 321, height: 181),
            frameRate: FrameRate(30),
            timeRange: TimeRange(start: 1, end: 1.75),
            shouldMute: false,
            shouldCrop: false,
            quality: .high
        )

        _ = try await AVFoundationMediaExporter().export(request, to: outputURL)
        let source = try await AVFoundationMediaMetadataReader().readSourceMedia(at: outputURL)
        let formatDescription = try await firstVideoFormatDescription(at: outputURL)
        let extensions = try #require(CMFormatDescriptionGetExtensions(formatDescription) as? [String: Any])
        let boxTypes = try topLevelBoxTypes(at: outputURL)
        let expectedPixelSize = try PixelSize(width: 322, height: 182)

        #expect(source.pixelSize == expectedPixelSize)
        #expect(CMFormatDescriptionGetMediaSubType(formatDescription) == kCMVideoCodecType_H264)
        #expect(try h264ProfileIDC(formatDescription: formatDescription) == 100)
        #expect(extensions[kCMFormatDescriptionExtension_PixelAspectRatio as String] == nil)
        #expect(extensions[kCMFormatDescriptionExtension_ColorPrimaries as String] as? String == kCMFormatDescriptionColorPrimaries_ITU_R_709_2 as String)
        #expect(extensions[kCMFormatDescriptionExtension_TransferFunction as String] as? String == kCMFormatDescriptionTransferFunction_ITU_R_709_2 as String)
        #expect(extensions[kCMFormatDescriptionExtension_YCbCrMatrix as String] as? String == kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2 as String)
        #expect(try boxIndex("moov", in: boxTypes) < boxIndex("mdat", in: boxTypes))
    }

    @Test("unsupported formats are rejected without writing output")
    func unsupportedFormatsAreRejectedWithoutWritingOutput() async throws {
        let outputURL = temporaryOutputURL(fileExtension: "gif")
        let request = try ExportRequest(
            inputFileURL: fixtureURL("input.mp4"),
            format: .gif,
            pixelSize: PixelSize(width: 320, height: 180),
            frameRate: FrameRate(12),
            timeRange: TimeRange(start: 1, end: 1.2),
            shouldMute: false,
            shouldCrop: false
        )

        await #expect(throws: AVFoundationExportPlanError.unsupportedFormat(.gif)) {
            _ = try await AVFoundationMediaExporter().export(request, to: outputURL)
        }
        #expect(!FileManager.default.fileExists(atPath: outputURL.path))
    }

    private func fixtureURL(_ fileName: String) throws -> URL {
        try packageRootURL()
            .appending(path: "docs/Luxel/test/fixtures")
            .appending(path: fileName)
    }

    private func temporaryOutputURL(fileExtension: String) -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "luxel-export-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)
    }

    private func videoCodecType(at fileURL: URL) async throws -> CMVideoCodecType {
        CMFormatDescriptionGetMediaSubType(try await firstVideoFormatDescription(at: fileURL))
    }

    private func firstVideoFormatDescription(at fileURL: URL) async throws -> CMFormatDescription {
        let asset = AVURLAsset(url: fileURL)
        let videoTrack = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let formatDescription = try #require(try await videoTrack.load(.formatDescriptions).first)

        return formatDescription
    }

    private func h264ProfileIDC(formatDescription: CMFormatDescription) throws -> UInt8 {
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
              parameterSetSize > 1 else {
            throw AVFoundationMediaExporterTestError.missingH264ParameterSet
        }

        return parameterSetPointer[1]
    }

    private func topLevelBoxTypes(at fileURL: URL) throws -> [String] {
        let data = try Data(contentsOf: fileURL)
        var offset = 0
        var boxTypes: [String] = []

        while offset + 8 <= data.count {
            let boxSize32 = data[offset..<offset + 4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            let boxTypeData = data[offset + 4..<offset + 8]
            let boxType = String(decoding: boxTypeData, as: UTF8.self)
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

    private func boxIndex(_ boxType: String, in boxTypes: [String]) throws -> Int {
        guard let index = boxTypes.firstIndex(of: boxType) else {
            throw AVFoundationMediaExporterTestError.missingMP4Box(boxType)
        }

        return index
    }

    private func packageRootURL() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "Tests" {
            let next = url.deletingLastPathComponent()
            try #require(next.path != url.path)
            url = next
        }

        return url.deletingLastPathComponent()
    }
}

private enum AVFoundationMediaExporterTestError: Error, Equatable {
    case invalidMP4BoxSize
    case missingH264ParameterSet
    case missingMP4Box(String)
}
