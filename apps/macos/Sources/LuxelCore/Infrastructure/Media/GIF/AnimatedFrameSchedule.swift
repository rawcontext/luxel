import AVFoundation
import CoreMedia
import Foundation

struct AnimatedFrameSchedule: Equatable, Sendable {
    let frameTimes: [CMTime]
    let frameDelay: TimeInterval

    init(request: ExportRequest, sourceFrameRate: Double) {
        let requestedFrameRate = Double(request.frameRate.framesPerSecond)
        let speed = request.speed.value
        let sourceFrameRate = max(1, sourceFrameRate)
        let effectiveFrameRate = requestedFrameRate * speed
        let decimation = max(1, Int((effectiveFrameRate / sourceFrameRate).rounded(.up)))
        let unscaledDuration = (try? request.timelineMapper.unscaledOutputDuration) ?? 0
        let candidateFrameCount = max(
            1, Int((unscaledDuration * requestedFrameRate).rounded()))
        let indices = stride(from: 0, to: candidateFrameCount, by: decimation)
        let mapper = EditedTimelineMapper(
            trimRange: request.timeRange,
            editPlan: request.editPlan
        )

        frameTimes = indices.compactMap { index in
            guard let sourceTime = mapper.sourceTime(
                forOutputTime: Double(index) / requestedFrameRate
            ) else {
                return nil
            }
            return CMTime(
                seconds: sourceTime,
                preferredTimescale: 600
            )
        }
        frameDelay = Double(decimation) / effectiveFrameRate
    }
}

func animatedFrameSchedule(for request: ExportRequest, asset: AVURLAsset) async
-> AnimatedFrameSchedule {
    let sourceFrameRate = await sourceFrameRate(
        for: asset, fallback: request.frameRate.framesPerSecond)
    return AnimatedFrameSchedule(request: request, sourceFrameRate: sourceFrameRate)
}

private func sourceFrameRate(for asset: AVURLAsset, fallback: Int) async -> Double {
    guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first,
          let nominalFrameRate = try? await videoTrack.load(.nominalFrameRate),
          nominalFrameRate.isFinite,
          nominalFrameRate > 0
    else {
        return Double(fallback)
    }

    return Double(nominalFrameRate)
}
