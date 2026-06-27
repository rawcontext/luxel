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
        #expect(plan.quality == .balanced)
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
        #expect(plan.quality == .balanced)
    }

    @Test("ProRes exports map to QuickTime movie plans")
    func proResExportsMapToQuickTimeMoviePlans() throws {
        let expectations: [(format: ExportFormat, presetName: String)] = [
            (.proRes422, AVAssetExportPresetAppleProRes422LPCM),
            (.proRes4444, AVAssetExportPresetAppleProRes4444LPCM)
        ]

        for expectation in expectations {
            let request = try makeRequest(format: expectation.format)

            let plan = try AVFoundationExportPlanFactory().makePlan(
                for: request,
                outputFileURL: URL(fileURLWithPath: "/tmp/output.mov")
            )

            #expect(plan.presetName == expectation.presetName)
            #expect(plan.outputFileType == .mov)
            #expect(plan.quality == .high)
        }
    }

    @Test("audio exports map to native audio plans")
    func audioExportsMapToNativeAudioPlans() throws {
        let expectations: [AudioPlanExpectation] = [
            AudioPlanExpectation(
                format: .m4a,
                presetName: AVAssetExportPresetAppleM4A,
                outputFileType: .m4a,
                quality: .balanced
            ),
            AudioPlanExpectation(
                format: .alac,
                presetName: AVAssetExportPresetPassthrough,
                outputFileType: .m4a,
                quality: .lossless
            ),
            AudioPlanExpectation(
                format: .wav,
                presetName: AVAssetExportPresetPassthrough,
                outputFileType: .wav,
                quality: .lossless
            ),
            AudioPlanExpectation(
                format: .caf,
                presetName: AVAssetExportPresetPassthrough,
                outputFileType: .caf,
                quality: .lossless
            ),
            AudioPlanExpectation(
                format: .flac,
                presetName: AVAssetExportPresetPassthrough,
                outputFileType: nil,
                quality: .lossless
            )
        ]

        for expectation in expectations {
            let request = try makeRequest(format: expectation.format, width: 1, height: 1)

            let plan = try AVFoundationExportPlanFactory().makePlan(
                for: request,
                outputFileURL: URL(fileURLWithPath: "/tmp/output.\(expectation.format.fileExtension)")
            )

            #expect(plan.presetName == expectation.presetName)
            #expect(plan.outputFileType == expectation.outputFileType)
            #expect(plan.quality == expectation.quality)
        }
    }

    @Test("compact mp4 export maps to medium quality preset")
    func compactMP4ExportMapsToMediumQualityPreset() throws {
        let request = try makeRequest(format: .mp4, quality: .compact)

        let plan = try AVFoundationExportPlanFactory().makePlan(
            for: request,
            outputFileURL: URL(fileURLWithPath: "/tmp/output.mp4")
        )

        #expect(plan.presetName == AVAssetExportPresetMediumQuality)
        #expect(plan.quality == .compact)
    }

    @Test("unavailable lossless video export falls back to balanced")
    func unavailableLosslessVideoExportFallsBackToBalanced() throws {
        let request = try makeRequest(format: .mp4, quality: .lossless)

        let plan = try AVFoundationExportPlanFactory().makePlan(
            for: request,
            outputFileURL: URL(fileURLWithPath: "/tmp/output.mp4")
        )

        #expect(plan.presetName == AVAssetExportPresetHighestQuality)
        #expect(plan.quality == .balanced)
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
        height: Int = 720,
        quality: ExportQuality = .balanced
    ) throws -> ExportRequest {
        try ExportRequest(
            inputFileURL: URL(fileURLWithPath: "/tmp/input.mp4"),
            format: format,
            pixelSize: PixelSize(width: width, height: height),
            frameRate: FrameRate(30),
            timeRange: TimeRange(start: 2, end: 6),
            shouldMute: false,
            shouldCrop: false,
            quality: quality
        )
    }
}

private struct AudioPlanExpectation {
    let format: ExportFormat
    let presetName: String
    let outputFileType: AVFileType?
    let quality: ExportQuality
}
