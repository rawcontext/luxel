import Foundation

public struct ScreenshotCaptureJob: Equatable, Sendable {
    public let request: ScreenshotRequest
    public let destinations: [ScreenshotDestination]
    public let outputFileURL: URL?
    public let historyName: String?

    public init(
        request: ScreenshotRequest,
        destinations: [ScreenshotDestination],
        outputFileURL: URL? = nil,
        historyName: String? = nil
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
        self.historyName = historyName
    }
}

public struct ScreenshotCaptureResult: Equatable, Sendable {
    public let imageData: ImageData
    public let completedDestinations: [ScreenshotDestination]
    public let failedDestinations: [ScreenshotDestination]
    public let fileURL: URL?
    public let historyEntry: PastRecording?
}

@MainActor
public final class ScreenshotCaptureService {
    private let capturer: any StillCapturer
    private let fileWriter: any ScreenshotFileWriter
    private let destinationClient: any ScreenshotDestinationClient
    private let history: RecordingHistoryService

    public init(
        capturer: any StillCapturer,
        fileWriter: any ScreenshotFileWriter,
        destinationClient: any ScreenshotDestinationClient,
        history: RecordingHistoryService
    ) {
        self.capturer = capturer
        self.fileWriter = fileWriter
        self.destinationClient = destinationClient
        self.history = history
    }

    public func capture(_ job: ScreenshotCaptureJob) async throws -> ScreenshotCaptureResult {
        let imageData = try await capturer.capture(job.request)
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

        let writtenFileURL = didWriteFile ? job.outputFileURL : nil
        let historyEntry: PastRecording? = if let writtenFileURL {
            history.addScreenshot(fileURL: writtenFileURL, name: job.historyName)
        } else {
            nil
        }

        return ScreenshotCaptureResult(
            imageData: imageData,
            completedDestinations: completedDestinations,
            failedDestinations: failedDestinations,
            fileURL: writtenFileURL,
            historyEntry: historyEntry
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
