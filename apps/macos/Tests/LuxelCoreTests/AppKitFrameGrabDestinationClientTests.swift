import Foundation
import LuxelCore
import Testing

@Suite("AppKit frame grab destination client")
struct AppKitFrameGrabDestinationClientTests {
    @MainActor
    @Test("copy rejects malformed image data")
    func copyRejectsMalformedImageData() throws {
        let imageData = try FrameGrabImageData(
            data: Data([0x01]),
            pixelSize: PixelSize(width: 1, height: 1)
        )

        #expect(throws: AppKitFrameGrabDestinationClientError.invalidImageData) {
            try AppKitFrameGrabDestinationClient().copyImageToPasteboard(imageData)
        }
    }
}
