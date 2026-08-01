import Foundation
import LuxelCore
import LuxelTestSupport
import Testing

@Suite("Frame grab service")
struct FrameGrabServiceTests {
    @MainActor
    @Test("grab fans out to clipboard and file")
    func grabFansOutToDestinations() async throws {
        let imageData = try makeImageData()
        let grabber = StubFrameGrabber(imageData: imageData)
        let fileWriter = SpyFrameGrabFileWriter()
        let destinationClient = SpyFrameGrabDestinationClient()
        let service = FrameGrabService(
            frameGrabber: grabber,
            fileWriter: fileWriter,
            destinationClient: destinationClient
        )
        let request = try makeRequest()
        let outputURL = URL(fileURLWithPath: "/tmp/frame.png")

        let result = try await service.grab(
            try FrameGrabJob(
                request: request,
                destinations: [.clipboard, .file],
                outputFileURL: outputURL
            ))

        #expect(grabber.requests == [request])
        #expect(destinationClient.copiedImages == [imageData])
        #expect(
            fileWriter.writes == [SpyFrameGrabFileWriter.Write(imageData: imageData, fileURL: outputURL)])
        #expect(result.completedDestinations == [.clipboard, .file])
        #expect(result.failedDestinations.isEmpty)
        #expect(result.fileURL == outputURL)
    }

    @MainActor
    @Test("grab reports destination failures without aborting remaining destinations")
    func grabReportsDestinationFailures() async throws {
        let imageData = try makeImageData()
        let destinationClient = SpyFrameGrabDestinationClient(copyError: StubError.copyFailed)
        let fileWriter = SpyFrameGrabFileWriter()
        let service = FrameGrabService(
            frameGrabber: StubFrameGrabber(imageData: imageData),
            fileWriter: fileWriter,
            destinationClient: destinationClient
        )
        let outputURL = URL(fileURLWithPath: "/tmp/frame.png")

        let result = try await service.grab(
            try FrameGrabJob(
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

        #expect(throws: FrameGrabError.emptyFrameGrabDestinations) {
            _ = try FrameGrabJob(request: request, destinations: [])
        }
        #expect(throws: FrameGrabError.fileDestinationRequiresOutputURL) {
            _ = try FrameGrabJob(request: request, destinations: [.file])
        }
    }

    private func makeRequest() throws -> FrameGrabRequest {
        try FrameGrabRequest(sourceFileURL: URL(fileURLWithPath: "/tmp/luxel.mp4"), time: 1)
    }

    private func makeImageData() throws -> FrameGrabImageData {
        try FrameGrabImageData(
            data: Data([0x89, 0x50, 0x4e, 0x47]),
            pixelSize: PixelSize(width: 2, height: 2)
        )
    }
}

private typealias StubFrameGrabber = TestFrameGrabberSpy

private typealias SpyFrameGrabFileWriter = TestFrameGrabFileWriterSpy

@MainActor
private final class SpyFrameGrabDestinationClient: FrameGrabDestinationClient {
    let copyError: (any Error)?
    private(set) var copiedImages: [FrameGrabImageData] = []

    init(copyError: (any Error)? = nil) {
        self.copyError = copyError
    }

    func copyImageToPasteboard(_ imageData: FrameGrabImageData) throws {
        if let copyError {
            throw copyError
        }

        copiedImages.append(imageData)
    }
}

private enum StubError: Error {
    case copyFailed
}
