import AVFoundation
import CoreMedia
import Foundation
import LuxelCore
import Testing

@Suite("AVFoundation export plan")
struct AVFoundationExportPlanFactoryTests {
    @Test("mp4 export maps to highest quality MPEG-4 plan")
    func mp4ExportMapsToHighestQualityPlan() throws {
        let request = try makeRequest(format: .mp4, width: 641, height: 839)

        let plan = try AVFoundationExportPlanFactory().makePlan(
            for: request,
            outputFileURL: URL(fileURLWithPath: "/tmp/output.mp4")
        )
        let expectedPixelSize = try PixelSize(width: 642, height: 840)

        #expect(plan.inputFileURL.path == "/tmp/input.mp4")
        #expect(plan.outputFileURL.path == "/tmp/output.mp4")
        #expect(plan.presetName == AVAssetExportPresetHighestQuality)
        #expect(plan.outputFileType == .mp4)
        #expect(plan.timeRange.start == CMTime(seconds: 2, preferredTimescale: 600))
        #expect(plan.timeRange.duration == CMTime(seconds: 4, preferredTimescale: 600))
        #expect(plan.outputPixelSize == expectedPixelSize)
        #expect(!plan.shouldMute)
    }

    @Test("hevc export maps to HEVC highest quality plan")
    func hevcExportMapsToHEVCHighestQualityPlan() throws {
        let request = try makeRequest(format: .hevc)

        let plan = try AVFoundationExportPlanFactory().makePlan(
            for: request,
            outputFileURL: URL(fileURLWithPath: "/tmp/output.mp4")
        )

        #expect(plan.presetName == AVAssetExportPresetHEVCHighestQuality)
        #expect(plan.outputFileType == .mp4)
    }

    @Test("non AVFoundation formats are rejected")
    func nonAVFoundationFormatsAreRejected() throws {
        for format in [ExportFormat.av1, .webm, .gif, .apng] {
            let request = try makeRequest(format: format)

            #expect(throws: AVFoundationExportPlanError.unsupportedFormat(format)) {
                _ = try AVFoundationExportPlanFactory().makePlan(
                    for: request,
                    outputFileURL: URL(fileURLWithPath: "/tmp/output.\(format.fileExtension)")
                )
            }
        }
    }

    private func makeRequest(
        format: ExportFormat,
        width: Int = 1280,
        height: Int = 720
    ) throws -> ExportRequest {
        try ExportRequest(
            inputFileURL: URL(fileURLWithPath: "/tmp/input.mp4"),
            format: format,
            pixelSize: PixelSize(width: width, height: height),
            frameRate: FrameRate(30),
            timeRange: TimeRange(start: 2, end: 6),
            shouldMute: false,
            shouldCrop: false
        )
    }
}
