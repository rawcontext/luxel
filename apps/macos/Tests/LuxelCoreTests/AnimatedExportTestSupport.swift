import Foundation
import LuxelCore
import LuxelTestSupport

func makeAnimatedExportRequest(
    format: ExportFormat,
    pixelSize: PixelSize? = nil,
    quality: ExportQuality = .balanced,
    speed: PlaybackSpeed = .normal,
    gifOptions: GIFRenderOptions? = nil,
    zoomBlocks: [ZoomBlock] = []
) throws -> ExportRequest {
    try ExportRequest(
        inputFileURL: testFixtureURL("input.mp4"),
        format: format,
        pixelSize: pixelSize ?? PixelSize(width: 160, height: 90),
        frameRate: FrameRate(10),
        timeRange: TimeRange(start: 1, end: 1.3),
        shouldMute: false,
        shouldCrop: true,
        quality: quality,
        speed: speed,
        gifOptions: gifOptions,
        zoomBlocks: zoomBlocks
    )
}

func testAnimatedZoomBlock(start: TimeInterval, end: TimeInterval) throws -> ZoomBlock {
    try ZoomBlock(
        timeRange: TimeRange(start: start, end: end),
        targetRect: NormalizedRect(x: 0.25, y: 0.25, width: 0.2, height: 0.2),
        zoom: 2,
        transitionOverride: 0.05
    )
}
