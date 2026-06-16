import Foundation
import LuxelCore
import Testing

@Suite("Frame grab service")
struct FrameGrabServiceTests {
    @MainActor
    @Test("grab fans out to clipboard file and preview")
    func grabFansOutToDestinations() async throws {
        let imageData = try makeImageData()
        let grabber = StubFrameGrabber(imageData: imageData)
        let fileWriter = SpyScreenshotFileWriter()
        let destinationClient = SpyFrameGrabDestinationClient()
        let service = FrameGrabService(
            frameGrabber: grabber,
            fileWriter: fileWriter,
            destinationClient: destinationClient
        )
        let request = try makeRequest()
        let outputURL = URL(fileURLWithPath: "/tmp/frame.png")

        let result = try await service.grab(try FrameGrabJob(
            request: request,
            destinations: [.clipboard, .file, .preview],
            outputFileURL: outputURL
        ))

        #expect(grabber.requests == [request])
        #expect(destinationClient.copiedImages == [imageData])
        #expect(fileWriter.writes == [SpyScreenshotFileWriter.Write(imageData: imageData, fileURL: outputURL)])
        #expect(destinationClient.openedURLs == [outputURL])
        #expect(result.completedDestinations == [.clipboard, .file, .preview])
        #expect(result.failedDestinations.isEmpty)
        #expect(result.fileURL == outputURL)
    }

    @MainActor
    @Test("grab reports destination failures without aborting remaining destinations")
    func grabReportsDestinationFailures() async throws {
        let imageData = try makeImageData()
        let destinationClient = SpyFrameGrabDestinationClient(copyError: StubError.copyFailed)
        let fileWriter = SpyScreenshotFileWriter()
        let service = FrameGrabService(
            frameGrabber: StubFrameGrabber(imageData: imageData),
            fileWriter: fileWriter,
            destinationClient: destinationClient
        )
        let outputURL = URL(fileURLWithPath: "/tmp/frame.png")

        let result = try await service.grab(try FrameGrabJob(
            request: makeRequest(),
            destinations: [.clipboard, .file],
            outputFileURL: outputURL
        ))

        #expect(result.completedDestinations == [.file])
        #expect(result.failedDestinations == [.clipboard])
        #expect(fileWriter.writes.map(\.fileURL) == [outputURL])
    }

    @Test("job validates destinations")
    func jobValidatesDestinations() throws {
        let request = try makeRequest()

        #expect(throws: ScreenshotModelError.emptyScreenshotDestinations) {
            _ = try FrameGrabJob(request: request, destinations: [])
        }
        #expect(throws: ScreenshotModelError.fileDestinationRequiresOutputURL) {
            _ = try FrameGrabJob(request: request, destinations: [.file])
        }
    }

    private func makeRequest() throws -> FrameGrabRequest {
        try FrameGrabRequest(sourceFileURL: URL(fileURLWithPath: "/tmp/luxel.mp4"), time: 1)
    }

    private func makeImageData() throws -> ImageData {
        try ImageData(
            data: Data([0x89, 0x50, 0x4e, 0x47]),
            format: .png,
            pixelSize: PixelSize(width: 2, height: 2)
        )
    }
}

private final class StubFrameGrabber: FrameGrabber, @unchecked Sendable {
    let imageData: ImageData
    private(set) var requests: [FrameGrabRequest] = []

    init(imageData: ImageData) {
        self.imageData = imageData
    }

    func grab(_ request: FrameGrabRequest) async throws -> ImageData {
        requests.append(request)
        return imageData
    }
}

private final class SpyScreenshotFileWriter: ScreenshotFileWriter, @unchecked Sendable {
    struct Write: Equatable {
        let imageData: ImageData
        let fileURL: URL
    }

    private(set) var writes: [Write] = []

    func write(_ imageData: ImageData, to fileURL: URL) throws {
        writes.append(Write(imageData: imageData, fileURL: fileURL))
    }
}

@MainActor
private final class SpyFrameGrabDestinationClient: ScreenshotDestinationClient {
    let copyError: (any Error)?
    private(set) var copiedImages: [ImageData] = []
    private(set) var openedURLs: [URL] = []

    init(copyError: (any Error)? = nil) {
        self.copyError = copyError
    }

    func copyImageToPasteboard(_ imageData: ImageData) throws {
        if let copyError {
            throw copyError
        }

        copiedImages.append(imageData)
    }

    func openWithDefaultApp(_ fileURL: URL) throws {
        openedURLs.append(fileURL)
    }
}

private enum StubError: Error {
    case copyFailed
}
