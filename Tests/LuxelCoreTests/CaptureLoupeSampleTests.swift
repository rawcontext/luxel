import LuxelCore
import Testing

@Suite("Capture loupe sample")
struct CaptureLoupeSampleTests {
    @Test("sample centers source rect and places overlay below trailing by default")
    func sampleCentersSourceRectAndPlacesOverlayBelowTrailingByDefault() throws {
        let display = try DisplayBounds(id: DisplayID(1), x: 0, y: 0, width: 100, height: 80)
        let selection = try CaptureRect(x: 10, y: 12, width: 40, height: 30)

        let sample = try CaptureLoupeSampleResolver.sample(
            cursor: CapturePoint(x: 50, y: 40),
            display: display,
            selection: selection,
            sampleSize: 24,
            overlaySize: PixelSize(width: 30, height: 20),
            cursorOffset: 10
        )

        #expect(sample.cursor == CapturePoint(x: 50, y: 40))
        #expect(sample.sourceRect == (try CaptureRect(x: 38, y: 28, width: 24, height: 24)))
        #expect(sample.overlayOrigin == CapturePoint(x: 60, y: 50))
        #expect(sample.quadrant == .bottomRight)
        #expect(sample.readout == CaptureLoupeReadout(cursor: CapturePoint(x: 50, y: 40), selection: selection))
    }

    @Test("sample clamps source rect near display edges")
    func sampleClampsSourceRectNearDisplayEdges() throws {
        let display = try DisplayBounds(id: DisplayID(1), x: 0, y: 0, width: 100, height: 80)

        let sample = try CaptureLoupeSampleResolver.sample(
            cursor: CapturePoint(x: 2, y: 3),
            display: display,
            selection: nil,
            sampleSize: 24,
            overlaySize: PixelSize(width: 30, height: 20),
            cursorOffset: 10
        )

        #expect(sample.sourceRect == (try CaptureRect(x: 0, y: 0, width: 24, height: 24)))
    }

    @Test("sample flips overlay above and leading near bottom trailing edge")
    func sampleFlipsOverlayAboveAndLeadingNearBottomTrailingEdge() throws {
        let display = try DisplayBounds(id: DisplayID(1), x: 0, y: 0, width: 100, height: 80)

        let sample = try CaptureLoupeSampleResolver.sample(
            cursor: CapturePoint(x: 95, y: 75),
            display: display,
            selection: nil,
            sampleSize: 24,
            overlaySize: PixelSize(width: 30, height: 20),
            cursorOffset: 8
        )

        #expect(sample.overlayOrigin == CapturePoint(x: 57, y: 47))
        #expect(sample.quadrant == .topLeft)
    }

    @Test("sample flips overlay leading while keeping it below when there is vertical room")
    func sampleFlipsOverlayLeadingWhileKeepingItBelowWhenThereIsVerticalRoom() throws {
        let display = try DisplayBounds(id: DisplayID(1), x: 0, y: 0, width: 100, height: 80)

        let sample = try CaptureLoupeSampleResolver.sample(
            cursor: CapturePoint(x: 95, y: 10),
            display: display,
            selection: nil,
            sampleSize: 24,
            overlaySize: PixelSize(width: 30, height: 20),
            cursorOffset: 8
        )

        #expect(sample.overlayOrigin == CapturePoint(x: 57, y: 18))
        #expect(sample.quadrant == .bottomLeft)
    }

    @Test("sample clamps oversized sample and overlay to small displays")
    func sampleClampsOversizedSampleAndOverlayToSmallDisplays() throws {
        let display = try DisplayBounds(id: DisplayID(1), x: 0, y: 0, width: 10, height: 8)

        let sample = try CaptureLoupeSampleResolver.sample(
            cursor: CapturePoint(x: 20, y: -10),
            display: display,
            selection: nil,
            sampleSize: 24,
            overlaySize: PixelSize(width: 30, height: 20),
            cursorOffset: 8
        )

        #expect(sample.cursor == CapturePoint(x: 10, y: 0))
        #expect(sample.sourceRect == (try CaptureRect(x: 0, y: 0, width: 10, height: 8)))
        #expect(sample.overlayOrigin == CapturePoint(x: 0, y: 0))
    }

    @Test("sample rejects invalid sampling geometry")
    func sampleRejectsInvalidSamplingGeometry() throws {
        let display = try DisplayBounds(id: DisplayID(1), x: 0, y: 0, width: 100, height: 80)

        #expect(throws: CaptureModelError.invalidDimensions) {
            _ = try CaptureLoupeSampleResolver.sample(
                cursor: CapturePoint(x: 50, y: 40),
                display: display,
                selection: nil,
                sampleSize: 0,
                overlaySize: PixelSize(width: 30, height: 20)
            )
        }
        #expect(throws: CaptureModelError.invalidDimensions) {
            _ = try CaptureLoupeSampleResolver.sample(
                cursor: CapturePoint(x: 50, y: 40),
                display: display,
                selection: nil,
                overlaySize: PixelSize(width: 30, height: 20),
                cursorOffset: -1
            )
        }
    }
}
