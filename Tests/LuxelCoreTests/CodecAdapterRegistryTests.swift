import Foundation
import LuxelCore
import Testing

@Suite("Codec adapter registry")
struct CodecAdapterRegistryTests {
    @Test("empty registry exposes only Apple-native availability")
    func emptyRegistryExposesOnlyAppleNativeAvailability() {
        let registry = CodecAdapterRegistry.empty

        #expect(registry.availability == .none)
        #expect(registry.availability.availableExportFormats == [.mp4, .hevc, .gif, .apng])
    }

    @Test("registry exposes registered external formats in availability order")
    func registryExposesRegisteredExternalFormatsInAvailabilityOrder() throws {
        let registry = try CodecAdapterRegistry(registrations: [
            makeRegistration(format: .av1),
            makeRegistration(format: .webm)
        ])

        #expect(registry.availability.registeredExternalFormats == [.webm, .av1])
        #expect(registry.availability.availableExportFormats == [.mp4, .hevc, .gif, .apng, .webm, .av1])
    }

    @Test("registration rejects Apple-native formats and duplicates")
    func registrationRejectsAppleNativeFormatsAndDuplicates() throws {
        #expect(throws: CodecAdapterRegistryError.unsupportedRegistrationFormat(.mp4)) {
            _ = try makeRegistration(format: .mp4)
        }

        let registration = try makeRegistration(format: .webm)
        #expect(throws: CodecAdapterRegistryError.duplicateExternalFormat(.webm)) {
            _ = try CodecAdapterRegistry(registrations: [registration, registration])
        }
    }

    @Test("registered media exporter routes native and external formats")
    func registeredMediaExporterRoutesNativeAndExternalFormats() async throws {
        let nativeExporter = SpyMediaExporter()
        let externalExporter = SpyMediaExporter()
        let registry = try CodecAdapterRegistry(registrations: [
            try CodecAdapterRegistration(
                format: .webm,
                exporter: externalExporter,
                sizeEstimator: StubExportSizeEstimator()
            )
        ])
        let exporter = registry.mediaExporter(nativeExporter: nativeExporter)

        _ = try await exporter.export(makeRequest(format: .mp4), to: URL(fileURLWithPath: "/tmp/native.mp4"))
        _ = try await exporter.export(makeRequest(format: .webm), to: URL(fileURLWithPath: "/tmp/external.webm"))

        #expect(await nativeExporter.requestedFormats() == [.mp4])
        #expect(await externalExporter.requestedFormats() == [.webm])
    }

    @Test("registered size estimator routes native and external formats")
    func registeredSizeEstimatorRoutesNativeAndExternalFormats() async throws {
        let nativeEstimator = SpyExportSizeEstimator(bytes: 100)
        let externalEstimator = SpyExportSizeEstimator(bytes: 200)
        let registry = try CodecAdapterRegistry(registrations: [
            try CodecAdapterRegistration(
                format: .av1,
                exporter: StubMediaExporter(),
                sizeEstimator: externalEstimator
            )
        ])
        let estimator = registry.exportSizeEstimator(nativeEstimator: nativeEstimator)

        let nativeEstimate = try await estimator.estimate(makeRequest(format: .hevc))
        let externalEstimate = try await estimator.estimate(makeRequest(format: .av1))

        #expect(nativeEstimate.bytes == 100)
        #expect(externalEstimate.bytes == 200)
        #expect(await nativeEstimator.requestedFormats() == [.hevc])
        #expect(await externalEstimator.requestedFormats() == [.av1])
    }

    @Test("unregistered external formats are rejected before native fallback")
    func unregisteredExternalFormatsAreRejectedBeforeNativeFallback() async throws {
        let registry = CodecAdapterRegistry.empty
        let exporter = registry.mediaExporter(nativeExporter: StubMediaExporter())
        let estimator = registry.exportSizeEstimator(nativeEstimator: StubExportSizeEstimator())

        await #expect(throws: CodecAdapterRegistryError.unregisteredExternalFormat(.webm)) {
            _ = try await exporter.export(makeRequest(format: .webm), to: URL(fileURLWithPath: "/tmp/out.webm"))
        }

        await #expect(throws: CodecAdapterRegistryError.unregisteredExternalFormat(.av1)) {
            _ = try await estimator.estimate(makeRequest(format: .av1))
        }
    }

    private func makeRegistration(format: ExportFormat) throws -> CodecAdapterRegistration {
        try CodecAdapterRegistration(
            format: format,
            exporter: StubMediaExporter(),
            sizeEstimator: StubExportSizeEstimator()
        )
    }

    private func makeRequest(format: ExportFormat) throws -> ExportRequest {
        try ExportRequest(
            inputFileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            format: format,
            pixelSize: PixelSize(width: 1280, height: 720),
            frameRate: FrameRate(30),
            timeRange: TimeRange(start: 0, end: 2),
            shouldMute: false,
            shouldCrop: true
        )
    }
}

private struct StubMediaExporter: MediaExporter {
    func export(_ request: ExportRequest, to outputFileURL: URL) async throws -> ExportedMedia {
        try ExportedMedia(
            fileURL: outputFileURL,
            format: request.format,
            pixelSize: request.outputPixelSize,
            shouldMute: request.outputShouldMute
        )
    }
}

private actor SpyMediaExporter: MediaExporter {
    private var requests: [ExportRequest] = []

    func export(_ request: ExportRequest, to outputFileURL: URL) async throws -> ExportedMedia {
        requests.append(request)
        return try await StubMediaExporter().export(request, to: outputFileURL)
    }

    func requestedFormats() -> [ExportFormat] {
        requests.map(\.format)
    }
}

private struct StubExportSizeEstimator: ExportSizeEstimator {
    func estimate(_ request: ExportRequest) async throws -> ExportEstimate {
        try ExportEstimate(bytes: 1, confidence: .modeled)
    }
}

private actor SpyExportSizeEstimator: ExportSizeEstimator {
    private let bytes: Int64
    private var requests: [ExportRequest] = []

    init(bytes: Int64) {
        self.bytes = bytes
    }

    func estimate(_ request: ExportRequest) async throws -> ExportEstimate {
        requests.append(request)
        return try ExportEstimate(bytes: bytes, confidence: .modeled)
    }

    func requestedFormats() -> [ExportFormat] {
        requests.map(\.format)
    }
}
