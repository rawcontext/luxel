import Foundation

public struct FrameGrabJob: Equatable, Sendable {
    public let request: FrameGrabRequest
    public let destinations: [FrameGrabDestination]
    public let outputFileURL: URL?

    public init(
        request: FrameGrabRequest,
        destinations: [FrameGrabDestination],
        outputFileURL: URL? = nil
    ) throws {
        guard !destinations.isEmpty else {
            throw FrameGrabError.emptyFrameGrabDestinations
        }

        if destinations.contains(where: \.requiresFileURL), outputFileURL == nil {
            throw FrameGrabError.fileDestinationRequiresOutputURL
        }

        self.request = request
        self.destinations = destinations
        self.outputFileURL = outputFileURL
    }
}

public struct FrameGrabResult: Equatable, Sendable {
    public let imageData: FrameGrabImageData
    public let completedDestinations: [FrameGrabDestination]
    public let failedDestinations: [FrameGrabDestination]
    public let fileURL: URL?
}

@MainActor
public final class FrameGrabService {
    private let frameGrabber: any FrameGrabber
    private let fileWriter: any FrameGrabFileWriter
    private let destinationClient: any FrameGrabDestinationClient

    public init(
        frameGrabber: any FrameGrabber,
        fileWriter: any FrameGrabFileWriter,
        destinationClient: any FrameGrabDestinationClient
    ) {
        self.frameGrabber = frameGrabber
        self.fileWriter = fileWriter
        self.destinationClient = destinationClient
    }

    public func grab(_ job: FrameGrabJob) async throws -> FrameGrabResult {
        let imageData = try await frameGrabber.grab(job.request)
        var completedDestinations: [FrameGrabDestination] = []
        var failedDestinations: [FrameGrabDestination] = []
        var didWriteFile = false

        for destination in job.destinations {
            do {
                switch destination {
                case .clipboard:
                    try destinationClient.copyImageToPasteboard(imageData)
                case .file:
                    try writeFileIfNeeded(imageData, to: job.outputFileURL, didWriteFile: &didWriteFile)
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
        _ imageData: FrameGrabImageData,
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
            throw FrameGrabError.fileDestinationRequiresOutputURL
        }

        return fileURL
    }
}
