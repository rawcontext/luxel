import LuxelCore
import Testing

func expectDefaultOptionalExportFeatures(_ request: ExportRequest) {
    #expect(request.audioMix == nil)
    #expect(!request.studioVoiceEnabled)
    #expect(request.gifOptions == nil)
    #expect(request.cursorOptions == nil)
    #expect(request.keystrokeOptions == nil)
    #expect(request.captionOptions == nil)
    #expect(request.cameraOverlay == nil)
    #expect(request.zoomBlocks.isEmpty)
}
