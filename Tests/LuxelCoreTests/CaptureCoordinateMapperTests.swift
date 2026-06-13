import LuxelCore
import Testing

@Suite("Capture coordinate mapper")
struct CaptureCoordinateMapperTests {
    @Test("recording rect flips top-left cropper y inside display")
    func recordingRectFlipsTopLeftCropperYInsideDisplay() throws {
        let display = try DisplayBounds(id: DisplayID(1), x: 0, y: 0, width: 2560, height: 1440)
        let selection = try CaptureRect(x: 40, y: 120, width: 640, height: 360)

        let rect = try CaptureCoordinateMapper.recordingRect(
            fromTopLeftSelection: selection,
            in: display
        )
        let expected = try CaptureRect(x: 40, y: 960, width: 640, height: 360)

        #expect(rect == expected)
    }

    @Test("local rect subtracts display origin")
    func localRectSubtractsDisplayOrigin() throws {
        let display = try DisplayBounds(id: DisplayID(2), x: -1728, y: 120, width: 1728, height: 1117)
        let windowRect = try CaptureRect(x: -1600, y: 220, width: 500, height: 400)

        let localRect = try CaptureCoordinateMapper.localRect(fromGlobalRect: windowRect, in: display)
        let expected = try CaptureRect(x: 128, y: 100, width: 500, height: 400)

        #expect(localRect == expected)
    }

    @Test("selection outside display throws")
    func selectionOutsideDisplayThrows() throws {
        let display = try DisplayBounds(id: DisplayID(1), x: 0, y: 0, width: 100, height: 100)
        let selection = try CaptureRect(x: 20, y: 20, width: 90, height: 20)

        #expect(throws: CaptureModelError.selectionOutsideDisplay) {
            _ = try CaptureCoordinateMapper.recordingRect(fromTopLeftSelection: selection, in: display)
        }
    }
}
