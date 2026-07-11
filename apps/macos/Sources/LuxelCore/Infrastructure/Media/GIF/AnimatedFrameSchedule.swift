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
        let availableOutputFrameRate = sourceFrameRate * speed
        let decimation = max(
            1,
            Int((requestedFrameRate / availableOutputFrameRate).rounded(.up))
        )
        let candidateFrameCount = max(
            1, Int((request.outputDuration * requestedFrameRate).rounded()))
        let indices = stride(from: 0, to: candidateFrameCount, by: decimation)
        let mapper = request.timelineMapper

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
        frameDelay = Double(decimation) / requestedFrameRate
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
