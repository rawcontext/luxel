import AppKit
import Foundation
import UniformTypeIdentifiers

public final class AppKitScreenshotFilePromise: NSObject, NSFilePromiseProviderDelegate {
    private let imageData: ImageData
    private let fileName: String
    private let sourceFileURL: URL?
    private let queue = OperationQueue()

    public init(
        imageData: ImageData,
        fileName: String,
        sourceFileURL: URL? = nil
    ) {
        self.imageData = imageData
        self.fileName = fileName
        self.sourceFileURL = sourceFileURL
        queue.maxConcurrentOperationCount = 1
        super.init()
    }

    public func makeProvider() -> NSFilePromiseProvider {
        NSFilePromiseProvider(
            fileType: imageData.format.uniformTypeIdentifier,
            delegate: self
        )
    }

    public func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        fileNameForType fileType: String
    ) -> String {
        fileName
    }

    public func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        writePromiseTo url: URL,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        let destinationURL = url.appending(path: fileName)

        do {
            if let sourceFileURL {
                try FileManager.default.copyItem(at: sourceFileURL, to: destinationURL)
            } else {
                try imageData.data.write(to: destinationURL, options: .atomic)
            }

            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }

    public func operationQueue(
        for filePromiseProvider: NSFilePromiseProvider
    ) -> OperationQueue {
        queue
    }
}

private extension ScreenshotFormat {
    var uniformTypeIdentifier: String {
        switch self {
        case .png:
            UTType.png.identifier
        case .jpeg:
            UTType.jpeg.identifier
        case .heic:
            UTType.heic.identifier
        }
    }
}
