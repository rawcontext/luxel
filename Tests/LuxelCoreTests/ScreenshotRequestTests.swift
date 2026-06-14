import Foundation
import LuxelCore
import Testing

@Suite("Screenshot request")
struct ScreenshotRequestTests {
    @Test("opaque screenshot requests accept all target kinds")
    func opaqueScreenshotRequestsAcceptAllTargets() throws {
        let rect = try CaptureRect(x: 10, y: 20, width: 640, height: 360)
        let targets: [CaptureTarget] = [
            .display(DisplayID(1)),
            .window(id: 42),
            .area(displayID: DisplayID(1), rect: rect)
        ]

        for target in targets {
            let request = try ScreenshotRequest(
                target: target,
                includeCursor: true,
                scale: .native,
                format: .jpeg,
                backdrop: .opaque
            )

            #expect(request.target == target)
            #expect(request.includeCursor)
            #expect(request.scale == .native)
            #expect(request.format == .jpeg)
            #expect(request.backdrop == .opaque)
        }
    }

    @Test("transparent screenshots require window target")
    func transparentScreenshotsRequireWindowTarget() throws {
        let rect = try CaptureRect(x: 0, y: 0, width: 640, height: 360)

        #expect(throws: ScreenshotModelError.transparentBackdropRequiresWindowTarget) {
            try ScreenshotRequest(
                target: .display(DisplayID(1)),
                includeCursor: false,
                format: .png,
                backdrop: .transparent
            )
        }

        #expect(throws: ScreenshotModelError.transparentBackdropRequiresWindowTarget) {
            try ScreenshotRequest(
                target: .area(displayID: DisplayID(1), rect: rect),
                includeCursor: false,
                format: .heic,
                backdrop: .transparent
            )
        }
    }

    @Test("transparent screenshots require alpha capable format")
    func transparentScreenshotsRequireAlphaCapableFormat() {
        #expect(throws: ScreenshotModelError.transparentBackdropRequiresAlphaCapableFormat) {
            try ScreenshotRequest(
                target: .window(id: 42),
                includeCursor: false,
                format: .jpeg,
                backdrop: .transparent
            )
        }
    }

    @Test("transparent window screenshots allow png and heic")
    func transparentWindowScreenshotsAllowAlphaFormats() throws {
        let png = try ScreenshotRequest(
            target: .window(id: 42),
            includeCursor: false,
            format: .png,
            backdrop: .transparent
        )
        let heic = try ScreenshotRequest(
            target: .window(id: 42),
            includeCursor: false,
            format: .heic,
            backdrop: .transparent
        )

        #expect(png.format == .png)
        #expect(heic.format == .heic)
    }

    @Test("request round trips through codable")
    func requestRoundTripsThroughCodable() throws {
        let request = try ScreenshotRequest(
            target: .window(id: 42),
            includeCursor: true,
            scale: .points,
            format: .heic,
            backdrop: .transparent
        )

        let encoded = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(ScreenshotRequest.self, from: encoded)

        #expect(decoded == request)
    }

    @Test("image data rejects empty payloads")
    func imageDataRejectsEmptyPayloads() throws {
        let pixelSize = try PixelSize(width: 100, height: 80)

        #expect(throws: ScreenshotModelError.emptyImageData) {
            try ImageData(data: Data(), format: .png, pixelSize: pixelSize)
        }

        let imageData = try ImageData(data: Data([0x89, 0x50, 0x4E, 0x47]), format: .png, pixelSize: pixelSize)
        #expect(imageData.pixelSize == pixelSize)
    }
}
