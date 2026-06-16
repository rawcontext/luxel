import Foundation

public struct FrameGrabJob: Equatable, Sendable {
    public let request: FrameGrabRequest
    public let destinations: [ScreenshotDestination]
    public let outputFileURL: URL?

    public init(
        request: FrameGrabRequest,
        destinations: [ScreenshotDestination],
        outputFileURL: URL? = nil
    ) throws {
        guard !destinations.isEmpty else {
            throw ScreenshotModelError.emptyScreenshotDestinations
        }

        if destinations.contains(where: \.requiresFileURL), outputFileURL == nil {
            throw ScreenshotModelError.fileDestinationRequiresOutputURL
        }

        self.request = request
        self.destinations = destinations
        self.outputFileURL = outputFileURL
    }
}

public struct FrameGrabResult: Equatable, Sendable {
    public let imageData: ImageData
    public let completedDestinations: [ScreenshotDestination]
    public let failedDestinations: [ScreenshotDestination]
    public let fileURL: URL?
}

@MainActor
public final class FrameGrabService {
    private let frameGrabber: any FrameGrabber
    private let fileWriter: any ScreenshotFileWriter
    private let destinationClient: any ScreenshotDestinationClient

    public init(
        frameGrabber: any FrameGrabber,
        fileWriter: any ScreenshotFileWriter,
        destinationClient: any ScreenshotDestinationClient
    ) {
        self.frameGrabber = frameGrabber
        self.fileWriter = fileWriter
        self.destinationClient = destinationClient
    }

    public func grab(_ job: FrameGrabJob) async throws -> FrameGrabResult {
        let imageData = try await frameGrabber.grab(job.request)
        var completedDestinations: [ScreenshotDestination] = []
        var failedDestinations: [ScreenshotDestination] = []
        var didWriteFile = false

        for destination in job.destinations {
            do {
                switch destination {
                case .clipboard:
                    try destinationClient.copyImageToPasteboard(imageData)
                case .file:
                    try writeFileIfNeeded(imageData, to: job.outputFileURL, didWriteFile: &didWriteFile)
                case .preview:
                    try writeFileIfNeeded(imageData, to: job.outputFileURL, didWriteFile: &didWriteFile)
                    try destinationClient.openWithDefaultApp(requiredFileURL(from: job.outputFileURL))
                }

                completedDestinations.append(destination)
            } catch {
                failedDestinations.append(destination)
            }
        }

        return FrameGrabResult(
            imageData: imageData,
            completedDestinations: completedDestinations,
            failedDestinations: failedDestinations,
            fileURL: didWriteFile ? job.outputFileURL : nil
        )
    }

    private func writeFileIfNeeded(
        _ imageData: ImageData,
        to fileURL: URL?,
        didWriteFile: inout Bool
    ) throws {
        guard !didWriteFile else {
            return
        }

        try fileWriter.write(imageData, to: try requiredFileURL(from: fileURL))
        didWriteFile = true
    }

    private func requiredFileURL(from fileURL: URL?) throws -> URL {
        guard let fileURL else {
            throw ScreenshotModelError.fileDestinationRequiresOutputURL
        }

        return fileURL
    }
}
