import AVFAudio
import Foundation
import LuxelTestSupport
import Testing

@testable import LuxelCore

@Suite("Studio Voice runtime parity")
struct StudioVoiceRuntimeParityTests {
    @Test("normalization alpha matches libdf training configuration")
    func normalizationAlphaMatchesLibDF() {
        #expect(abs(DeepFilterNetConfiguration().normalizationAlpha - 0.99) < 0.000_001)
    }

    @Test("analysis DFT uses libdf scaling")
    func analysisDFTUsesLibDFScaling() {
        let transform = DeepFilterNetSTFT(
            fftSize: 4,
            hopSize: 2,
            window: [1, 1, 1, 1]
        )
        var memory: [Float] = [0, 0]

        let spectrum = transform.forward(audio: [1, 0], memory: &memory)

        #expect(abs(spectrum.real[0] - 0.25) < 0.000_001)
        #expect(abs(spectrum.real[1] + 0.25) < 0.000_001)
        #expect(abs(spectrum.real[2] - 0.25) < 0.000_001)
    }

    @Test("deep filtering zero-pads taps outside the time axis")
    func deepFilteringZeroPadsTimeAxis() {
        let filtered = deepFilterNetApplyFiltering(
            real: [2],
            imaginary: [0],
            coefficients: [1, 0, 1, 0, 1, 0],
            shape: DeepFilterNetFilteringShape(
                filteredBins: 1,
                order: 3,
                lookahead: 1,
                frameCount: 1,
                frequencyBins: 1
            )
        )

        #expect(filtered.real == [2])
        #expect(filtered.imaginary == [0])
    }

    @Test("auxiliary reader restores Fortran-order inverse filterbank")
    func auxiliaryReaderRestoresFortranOrder() throws {
        let resources = try BundledStudioVoiceModelLocator(
            modelDirectoryURL: studioVoiceModelDirectory()
        ).locate()

        let auxiliary = try DeepFilterNetNPZReader.load(from: resources.auxiliaryDataURL)

        #expect(auxiliary.inverseERBFilterbank[33] == 0)
        #expect(auxiliary.inverseERBFilterbank[481 + 1] == 1)
    }

    private func studioVoiceModelDirectory() throws -> URL {
        packageRootURL()
            .appending(path: "Vendor/Models/studio-voice", directoryHint: .isDirectory)
    }

    private func packageRootURL() -> URL {
        var url = testSourceFileURL()
        while url.lastPathComponent != "Tests" {
            url.deleteLastPathComponent()
        }
        return url.deletingLastPathComponent()
    }
}

@Suite("Studio Voice")
struct StudioVoiceTests {
    @Test("bundled manifest validates every pinned artifact")
    func bundledManifestValidation() throws {
        let directory = try studioVoiceModelDirectory()
        let resources = try BundledStudioVoiceModelLocator(
            modelDirectoryURL: directory
        ).locate()
        let shippedFiles = try FileManager.default.subpathsOfDirectory(atPath: directory.path)
            .filter {
                !$0.hasSuffix("/")
                    && !["manifest.json", "LICENSE.txt", "NOTICE.md"].contains($0)
            }
            .filter { path in
                var isDirectory = ObjCBool(false)
                let fullPath = directory.appending(path: path).path
                return FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDirectory)
                    && !isDirectory.boolValue
            }

        #expect(resources.manifest.revision == "937bad9811f1ffc1a06ea0d676461b080b2bdc93")
        #expect(resources.manifest.sampleRate == 48_000)
        #expect(Set(resources.manifest.files.map(\.path)) == Set(shippedFiles))
    }

    @Test("bundled enhancer loads offline and preserves bounded window length")
    func bundledEnhancerInference() async throws {
        let enhancer = DeepFilterNetStudioVoiceEnhancer(
            locator: BundledStudioVoiceModelLocator(
                modelDirectoryURL: try studioVoiceModelDirectory()
            )
        )
        let frameCount = 48_123
        let samples = (0..<frameCount).map { frame in
            Float(sin(Double(frame) * 2 * .pi * 220 / 48_000) * 0.1)
        }
        let streamID = UUID()

        let output = try await enhancer.enhance(
            StudioVoiceWindow(
                streamID: streamID,
                samples: samples,
                sampleRate: 48_000,
                beginsStream: true,
                endsStream: true
            ),
            progress: nil
        )

        #expect(output.samples.count == samples.count)
        #expect(output.samples.allSatisfy { $0.isFinite })
        #expect(output.samples.suffix(123).contains { abs($0) > 0.000_001 })
    }

    @Test("preparation skips default and audio-disabled requests")
    func preparationSkipsInapplicableRequests() async throws {
        let enhancer = SpyStudioVoiceEnhancer()
        let service = ExportAudioPreparationService(enhancer: enhancer)
        let requests = [
            try makeRequest(format: .mp4),
            try makeRequest(format: .gif, studioVoiceEnabled: true),
            try makeRequest(format: .mp4, shouldMute: true, studioVoiceEnabled: true)
        ]

        let prepared = try await service.prepareAudio(for: requests, progress: nil)

        for index in requests.indices {
            #expect(prepared.asset(forRequestAt: index) == nil)
        }
        #expect(await enhancer.windows().isEmpty)
    }

    @Test("preparation enhances bounded windows once and shares a batch artifact")
    func boundedBatchPreparation() async throws {
        let enhancer = SpyStudioVoiceEnhancer()
        let temporaryRoot = try temporaryDirectory()
        let service = ExportAudioPreparationService(
            enhancer: enhancer,
            temporaryRootURL: temporaryRoot,
            windowDuration: 0.1,
            overlapDuration: 0.02
        )
        let requests = [
            try makeRequest(format: .mp4, studioVoiceEnabled: true),
            try makeRequest(format: .webm, studioVoiceEnabled: true)
        ]

        let prepared = try await service.prepareAudio(for: requests, progress: nil)
        let first = try #require(prepared.asset(forRequestAt: 0))
        let second = try #require(prepared.asset(forRequestAt: 1))
        let audioFile = try AVAudioFile(forReading: first.fileURL)
        let windows = await enhancer.windows()

        #expect(first.fileURL == second.fileURL)
        #expect(first.duration == requests[0].timeRange.duration)
        #expect(first.sampleRate == 48_000)
        #expect(first.channelCount == 2)
        #expect(audioFile.fileFormat.sampleRate == 48_000)
        #expect(audioFile.fileFormat.channelCount == 2)
        #expect(audioFile.length == AVAudioFramePosition(requests[0].timeRange.duration * 48_000))
        #expect(windows.count > 2)
        #expect(windows.allSatisfy { $0.samples.count <= 4_800 })
        #expect(windows.filter(\.beginsStream).count == 2)
        #expect(windows.filter(\.endsStream).count == 2)

        prepared.removeTemporaryFiles()
        #expect(!FileManager.default.fileExists(atPath: first.fileURL.path))
    }

    @Test("preparation applies level and post-enhancement normalization")
    func gainAndNormalization() async throws {
        let temporaryRoot = try temporaryDirectory()
        let service = ExportAudioPreparationService(
            enhancer: SpyStudioVoiceEnhancer(),
            temporaryRootURL: temporaryRoot
        )
        let unity = try makeRequest(
            format: .mp4,
            audioMix: AudioMixPlan(tracks: [AudioTrackMix(kind: .system)])
        )
        let half = try makeRequest(
            format: .webm,
            audioMix: AudioMixPlan(
                tracks: [AudioTrackMix(kind: .system, volume: 0.5)]
            )
        )
        let normalized = try makeRequest(
            format: .av1,
            audioMix: AudioMixPlan(
                tracks: [AudioTrackMix(kind: .system)],
                normalizePeak: true
            )
        )

        let prepared = try await service.prepareAudio(
            for: [unity, half, normalized],
            progress: nil
        )
        let unityAsset = try #require(prepared.asset(forRequestAt: 0))
        let halfAsset = try #require(prepared.asset(forRequestAt: 1))
        let normalizedAsset = try #require(prepared.asset(forRequestAt: 2))
        let unityPeak = try peak(of: unityAsset.fileURL)
        let halfPeak = try peak(of: halfAsset.fileURL)
        let normalizedPeak = try peak(of: normalizedAsset.fileURL)

        #expect(unityPeak > 0)
        #expect(abs(halfPeak / unityPeak - 0.5) < 0.02)
        #expect(abs(normalizedPeak - AudioMixPlan.normalizationTargetPeak) < 0.01)
        prepared.removeTemporaryFiles()
    }

    @Test("cancellation stops enhancement and removes temporary artifacts")
    func cancellationCleanup() async throws {
        let enhancer = SpyStudioVoiceEnhancer(delay: .seconds(30))
        let temporaryRoot = try temporaryDirectory()
        let service = ExportAudioPreparationService(
            enhancer: enhancer,
            temporaryRootURL: temporaryRoot,
            windowDuration: 0.1,
            overlapDuration: 0.02
        )
        let request = try makeRequest(format: .mp4, studioVoiceEnabled: true)
        let task = Task {
            try await service.prepareAudio(for: [request], progress: nil)
        }

        await enhancer.waitUntilStarted()
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        let contents = try FileManager.default.contentsOfDirectory(
            at: temporaryRoot,
            includingPropertiesForKeys: nil
        )
        #expect(contents.isEmpty)
    }

    private func makeRequest(
        format: ExportFormat,
        shouldMute: Bool = false,
        audioMix: AudioMixPlan? = nil,
        studioVoiceEnabled: Bool = false
    ) throws -> ExportRequest {
        try ExportRequest(
            inputFileURL: fixtureURL("input@2x.mp4"),
            format: format,
            pixelSize: PixelSize(width: 320, height: 180),
            frameRate: FrameRate(30),
            timeRange: TimeRange(start: 0.1, end: 0.5),
            shouldMute: shouldMute,
            audioMix: audioMix,
            studioVoiceEnabled: studioVoiceEnabled,
            shouldCrop: false,
            speed: PlaybackSpeed(2)
        )
    }

    private func peak(of url: URL) throws -> Double {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(file.length)
            )
        else {
            return 0
        }
        try file.read(into: buffer)
        guard let channelData = buffer.floatChannelData else {
            return 0
        }

        var peak = 0.0
        for channel in 0..<Int(format.channelCount) {
            for frame in 0..<Int(buffer.frameLength) {
                peak = max(peak, Double(abs(channelData[channel][frame])))
            }
        }
        return peak
    }

    private func studioVoiceModelDirectory() throws -> URL {
        packageRootURL()
            .appending(path: "Vendor/Models/studio-voice", directoryHint: .isDirectory)
    }

    private func fixtureURL(_ fileName: String) -> URL {
        packageRootURL().appending(path: "Tests/Fixtures/\(fileName)")
    }

    private func packageRootURL() -> URL {
        var url = testSourceFileURL()
        while url.lastPathComponent != "Tests" {
            url.deleteLastPathComponent()
        }
        return url.deletingLastPathComponent()
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "StudioVoiceTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private actor SpyStudioVoiceEnhancer: StudioVoiceEnhancing {
    private let delay: Duration?
    private var captured: [StudioVoiceWindow] = []
    private var started = false
    private var startContinuations: [CheckedContinuation<Void, Never>] = []

    init(delay: Duration? = nil) {
        self.delay = delay
    }

    func enhance(
        _ input: StudioVoiceWindow,
        progress: StudioVoiceProgressHandler?
    ) async throws -> StudioVoiceWindow {
        captured.append(input)
        started = true
        let continuations = startContinuations
        startContinuations.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
        if let delay {
            try await Task.sleep(for: delay)
        }
        return input
    }

    func windows() -> [StudioVoiceWindow] {
        captured
    }

    func waitUntilStarted() async {
        if started {
            return
        }
        await withCheckedContinuation { continuation in
            startContinuations.append(continuation)
        }
    }
}
