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
        switch request.format {
        case .mp4, .hevc:
            try await avFoundationExporter.export(request, to: outputFileURL)
        case .gif, .apng:
            try await animatedExporter.export(request, to: outputFileURL)
        case .av1, .webm:
            throw NativeMediaExporterError.unsupportedNativeFormat(request.format)
        }
    }
}

public enum NativeMediaExporterError: Error, Equatable {
    case unsupportedNativeFormat(ExportFormat)
}
