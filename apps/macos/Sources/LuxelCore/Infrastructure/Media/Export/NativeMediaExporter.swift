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

    public func export(_ request: ExportRequest, to outputFileURL: URL) async throws -> ExportedMedia {
        try await export(request, to: outputFileURL, progress: nil)
    }

    public func export(
        _ request: ExportRequest,
        to outputFileURL: URL,
        progress: MediaExportProgressHandler?
    ) async throws -> ExportedMedia {
        switch request.format {
        case .mp4, .hevc, .proRes422, .proRes4444, .m4a, .alac, .wav, .caf, .flac:
            try await avFoundationExporter.export(request, to: outputFileURL, progress: progress)
        case .gif, .apng:
            try await animatedExporter.export(request, to: outputFileURL, progress: progress)
        case .av1, .webm:
            throw NativeMediaExporterError.unsupportedNativeFormat(request.format)
        }
    }
}

public enum NativeMediaExporterError: Error, Equatable {
    case unsupportedNativeFormat(ExportFormat)
}
