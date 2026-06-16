import AppKit
import LuxelCore
import Testing

@MainActor
@Suite("AppKit screenshot file promise")
struct AppKitScreenshotFilePromiseTests {
    @Test("provider exposes screenshot filename and writes image data")
    func providerExposesScreenshotFilenameAndWritesImageData() async throws {
        let imageData = try makeImageData(bytes: [0x89, 0x50, 0x4e, 0x47])
        let promise = AppKitScreenshotFilePromise(
            imageData: imageData,
            fileName: "Luxel Screenshot.png"
        )
        let provider = promise.makeProvider()
        let directoryURL = try temporaryDirectory()

        #expect(promise.filePromiseProvider(provider, fileNameForType: "public.png") == "Luxel Screenshot.png")

        try await fulfill(promise, provider: provider, to: directoryURL)

        let outputURL = directoryURL.appending(path: "Luxel Screenshot.png")
        #expect(try Data(contentsOf: outputURL) == imageData.data)
    }

    @Test("provider copies existing screenshot file when available")
    func providerCopiesExistingScreenshotFileWhenAvailable() async throws {
        let directoryURL = try temporaryDirectory()
        let sourceURL = directoryURL.appending(path: "source.png")
        let promisedDirectoryURL = try temporaryDirectory()
        let fileData = Data([0x01, 0x02, 0x03])
        try fileData.write(to: sourceURL)
        let promise = AppKitScreenshotFilePromise(
            imageData: try makeImageData(bytes: [0x89, 0x50, 0x4e, 0x47]),
            fileName: "Dragged.png",
            sourceFileURL: sourceURL
        )
        let provider = promise.makeProvider()

        try await fulfill(promise, provider: provider, to: promisedDirectoryURL)

        let outputURL = promisedDirectoryURL.appending(path: "Dragged.png")
        #expect(try Data(contentsOf: outputURL) == fileData)
    }

    private func makeImageData(bytes: [UInt8]) throws -> ImageData {
        try ImageData(
            data: Data(bytes),
            format: .png,
            pixelSize: PixelSize(width: 1, height: 1)
        )
    }

    private func temporaryDirectory() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    private func fulfill(
        _ promise: AppKitScreenshotFilePromise,
        provider: NSFilePromiseProvider,
        to directoryURL: URL
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            promise.filePromiseProvider(provider, writePromiseTo: directoryURL) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
