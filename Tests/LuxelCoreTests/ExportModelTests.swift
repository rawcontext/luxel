import Foundation
import LuxelCore
import Testing

@Suite("Export model")
struct ExportModelTests {
    @Test("video formats map to expected extensions and display names")
    func formatMetadata() {
        #expect(ExportFormat.mp4.fileExtension == "mp4")
        #expect(ExportFormat.hevc.fileExtension == "mp4")
        #expect(ExportFormat.av1.fileExtension == "mp4")
        #expect(ExportFormat.webm.fileExtension == "webm")
        #expect(ExportFormat.gif.fileExtension == "gif")
        #expect(ExportFormat.apng.fileExtension == "apng")

        #expect(ExportFormat.mp4.prettyName == "MP4 (H264)")
        #expect(ExportFormat.hevc.prettyName == "MP4 (H265)")
        #expect(ExportFormat.av1.prettyName == "MP4 (AV1)")
        #expect(ExportFormat.webm.prettyName == "WebM")
        #expect(ExportFormat.gif.prettyName == "GIF")
        #expect(ExportFormat.apng.prettyName == "APNG")
    }

    @Test("v1 apple-native formats exclude deferred native codec formats")
    func v1AppleNativeFormatsExcludeDeferredNativeCodecFormats() {
        #expect(ExportFormat.appleNativeV1Formats == [.mp4, .hevc, .gif, .apng])

        for format in ExportFormat.appleNativeV1Formats {
            #expect(format.isAppleNativeV1Format)
            #expect(!format.requiresExternalNativeCodec)
        }

        for format in [ExportFormat.webm, .av1] {
            #expect(!format.isAppleNativeV1Format)
            #expect(format.requiresExternalNativeCodec)
        }
    }

    @Test("video exports round odd dimensions to even values")
    func videoExportsRoundDimensionsToEvenValues() throws {
        for format in [ExportFormat.mp4, .hevc, .av1, .webm] {
            let request = try makeRequest(format: format, width: 469, height: 839)

            #expect(try request.outputPixelSize == PixelSize(width: 470, height: 840))
        }
    }

    @Test("animated image exports preserve requested odd dimensions")
    func animatedExportsPreserveOddDimensions() throws {
        for format in [ExportFormat.gif, .apng] {
            let request = try makeRequest(format: format, width: 469, height: 839)

            #expect(try request.outputPixelSize == PixelSize(width: 469, height: 839))
        }
    }

    @Test("animated exports always mute output")
    func animatedExportsAlwaysMuteOutput() throws {
        let gifRequest = try makeRequest(format: .gif, shouldMute: false)
        let apngRequest = try makeRequest(format: .apng, shouldMute: false)
        let mp4Request = try makeRequest(format: .mp4, shouldMute: false)

        #expect(gifRequest.outputShouldMute)
        #expect(apngRequest.outputShouldMute)
        #expect(!mp4Request.outputShouldMute)
    }

    @Test("time range exposes trim duration")
    func timeRangeDuration() throws {
        let range = try TimeRange(start: 11.5, end: 27)

        #expect(range.duration == 15.5)
    }

    @Test("progress snapshots expose action text and clamp progress")
    func progressSnapshotsExposeActionTextAndClampProgress() {
        let preparing = ExportProgressSnapshot.preparing(format: .mp4)
        let exporting = ExportProgressSnapshot.exporting(format: .gif, progress: 1.5)
        let canceled = ExportProgressSnapshot.canceled(format: .hevc)

        #expect(preparing.phase == .preparing)
        #expect(preparing.actionTitle == "Preparing MP4 (H264)")
        #expect(preparing.progress == 0)
        #expect(exporting.phase == .exporting)
        #expect(exporting.actionTitle == "Exporting GIF")
        #expect(exporting.progress == 1)
        #expect(canceled.phase == .canceled)
        #expect(canceled.actionTitle == "Canceled MP4 (H265)")
    }

    @Test("invalid value objects throw")
    func invalidValuesThrow() {
        #expect(throws: ExportModelError.invalidPixelSize) {
            _ = try PixelSize(width: 0, height: 100)
        }
        #expect(throws: ExportModelError.invalidFrameRate) {
            _ = try FrameRate(0)
        }
        #expect(throws: ExportModelError.invalidTimeRange) {
            _ = try TimeRange(start: 5, end: 5)
        }
    }

    private func makeRequest(
        format: ExportFormat,
        width: Int = 100,
        height: Int = 200,
        shouldMute: Bool = false
    ) throws -> ExportRequest {
        try ExportRequest(
            inputFileURL: URL(fileURLWithPath: "/tmp/input.mp4"),
            format: format,
            pixelSize: PixelSize(width: width, height: height),
            frameRate: FrameRate(30),
            timeRange: TimeRange(start: 0, end: 10),
            shouldMute: shouldMute,
            shouldCrop: true
        )
    }
}
