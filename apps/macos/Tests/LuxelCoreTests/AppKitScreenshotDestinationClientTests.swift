import Foundation
import LuxelCore
import Testing

@Suite("AppKit screenshot destination client")
struct AppKitScreenshotDestinationClientTests {
    @MainActor
    @Test("copy rejects malformed image data")
    func copyRejectsMalformedImageData() throws {
        let imageData = try ImageData(
            data: Data([0x01]),
            format: .png,
            pixelSize: PixelSize(width: 1, height: 1)
        )

        #expect(throws: AppKitScreenshotDestinationClientError.invalidImageData) {
            try AppKitScreenshotDestinationClient().copyImageToPasteboard(imageData)
        }
    }
}
