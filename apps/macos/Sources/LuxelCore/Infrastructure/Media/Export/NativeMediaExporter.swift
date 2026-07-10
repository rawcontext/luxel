import Foundation

public struct NativeMediaExporter: MediaExporter, Sendable {
    private let avFoundationExporter: AVFoundationMediaExporter
    private let animatedExporter: ImageIOAnimatedMediaExporter

    public init(
        avFoundationExporter: AVFoundationMediaExporter = AVFoundationMediaExporter(),
        animatedExporter: ImageIOAnimatedMediaExporter = ImageIOAnimatedMediaExporter()
    ) {
        self.avFoundationExporter = avFoundationExporter
        self.animatedExporter = animatedExporter
    }

    public func export(
        _ input: MediaExportInput,
        to outputFileURL: URL,
        progress: MediaExportProgressHandler?
    ) async throws -> ExportedMedia {
        let request = input.request
        switch request.format {
        case .mp4, .hevc, .proRes422, .proRes4444, .m4a, .alac, .wav, .caf, .flac:
            return try await avFoundationExporter.export(
                input,
                to: outputFileURL,
                progress: progress
            )
        case .gif, .apng:
            return try await animatedExporter.export(
                input,
                to: outputFileURL,
                progress: progress
            )
        case .av1, .webm:
            throw NativeMediaExporterError.unsupportedNativeFormat(request.format)
        }
    }
}

public enum NativeMediaExporterError: Error, Equatable {
    case unsupportedNativeFormat(ExportFormat)
}
