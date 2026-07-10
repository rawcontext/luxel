import AVFoundation
import CoreMedia

extension AVFoundationVideoCompositionFactory {
    func addCameraRamp(
        to layerConfiguration: inout AVVideoCompositionLayerInstruction.Configuration,
        cameraPath: CameraPath,
        context: VideoCompositionInstructionContext,
        timeRange: CMTimeRange
    ) throws {
        let startTransform = try cameraPath.transform(
            at: outputSeconds(timeRange.start, in: context.timeRange)
        )
        let endTransform = try cameraPath.transform(
            at: outputSeconds(timeRange.end, in: context.timeRange)
        )
        layerConfiguration.addCropRectangleRamp(
            AVVideoCompositionLayerInstruction.CropRectangleRamp(
                timeRange: timeRange,
                start: sourceCropRect(
                    for: startTransform,
                    geometry: context.geometry,
                    spatialCropRect: context.spatialCropRect
                ),
                end: sourceCropRect(
                    for: endTransform,
                    geometry: context.geometry,
                    spatialCropRect: context.spatialCropRect
                )
            ))
        layerConfiguration.addTransformRamp(
            AVVideoCompositionLayerInstruction.TransformRamp(
                timeRange: timeRange,
                start: renderTransform(
                    geometry: context.geometry,
                    outputSize: context.outputSize,
                    shouldCrop: context.shouldCrop,
                    spatialCropRect: context.spatialCropRect,
                    cameraTransform: startTransform
                ),
                end: renderTransform(
                    geometry: context.geometry,
                    outputSize: context.outputSize,
                    shouldCrop: context.shouldCrop,
                    spatialCropRect: context.spatialCropRect,
                    cameraTransform: endTransform
                )
            ))
    }
}
