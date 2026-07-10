import Foundation
import LuxelCore
import Testing

@Suite("Precision transcription release integration", .serialized)
struct PrecisionTranscriptionIntegrationTests {
    @Test(
        "pinned local model validates and transcribes English and non-English offline",
        .enabled(if: precisionIntegrationEnvironment != nil)
    )
    func pinnedModelTranscribesOffline() async throws {
        let environment = try #require(precisionIntegrationEnvironment)
        let root = FileManager.default.temporaryDirectory.appending(
            path: "LuxelPrecisionIntegration-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let validator = ParakeetPrecisionModelValidator()
        let catalog = try BundledLocalModelCatalog.production(
            registeredValidatorKeys: [validator.key],
            attributionIdentifiers: ["fluidinference-parakeet-tdt-0.6b-v3-coreml"],
            currentAppVersion: "1.0.25"
        )
        let downloader = LocalPrecisionFixtureDownloader(
            modelDirectory: environment.modelDirectory
        )
        let manager = try LocalModelManager(
            catalogProvider: catalog,
            validators: [validator],
            downloader: downloader,
            verifier: SHA256ArtifactVerifier(),
            repository: ApplicationSupportLocalModelRepository(
                root: root,
                appVersion: "1.0.25",
                appBuild: "integration"
            )
        )
        let installation = try await manager.install(PrecisionTranscriptionEngine.modelID)
        let engine = PrecisionTranscriptionEngine(modelManager: manager)

        let english = try await engine.recognize(
            audioURL: environment.englishAudio,
            audioTrackIndex: nil,
            locale: Locale(identifier: "en-US")
        )
        #expect(normalized(english.text).contains(normalized(environment.englishExpected)))
        #expect(english.provenance.modelRevision == installation.commit)
        #expect(english.words.allSatisfy { $0.end > $0.start })

        let nonEnglish = try await engine.recognize(
            audioURL: environment.nonEnglishAudio,
            audioTrackIndex: nil,
            locale: Locale(identifier: environment.nonEnglishLocale)
        )
        #expect(
            normalized(nonEnglish.text).contains(
                normalized(environment.nonEnglishExpected)
            )
        )
        #expect(nonEnglish.words.allSatisfy { $0.end > $0.start })

        if let twoTrackMovie = environment.twoTrackMovie {
            async let first = engine.recognize(
                audioURL: twoTrackMovie,
                audioTrackIndex: 0,
                locale: Locale(identifier: "en-US")
            )
            async let second = engine.recognize(
                audioURL: twoTrackMovie,
                audioTrackIndex: 1,
                locale: Locale(identifier: "en-US")
            )
            let results = try await [first, second]
            #expect(results.allSatisfy { !$0.words.isEmpty })
        }

        #expect(await downloader.callCount == 21)
    }

    @Test(
        "runtime corruption is quarantined without an implicit download",
        .enabled(if: precisionIntegrationEnvironment != nil)
    )
    func corruptRuntimeIsQuarantinedOffline() async throws {
        let environment = try #require(precisionIntegrationEnvironment)
        let root = FileManager.default.temporaryDirectory.appending(
            path: "LuxelPrecisionCorruption-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let validator = ParakeetPrecisionModelValidator()
        let catalog = try BundledLocalModelCatalog.production(
            registeredValidatorKeys: [validator.key],
            attributionIdentifiers: ["fluidinference-parakeet-tdt-0.6b-v3-coreml"],
            currentAppVersion: "1.0.25"
        )
        let downloader = LocalPrecisionFixtureDownloader(
            modelDirectory: environment.modelDirectory
        )
        let manager = try LocalModelManager(
            catalogProvider: catalog,
            validators: [validator],
            downloader: downloader,
            verifier: SHA256ArtifactVerifier(),
            repository: ApplicationSupportLocalModelRepository(
                root: root,
                appVersion: "1.0.25",
                appBuild: "integration"
            )
        )
        let installation = try await manager.install(PrecisionTranscriptionEngine.modelID)
        let vocabulary = installation.payloadRoot
            .appending(path: "parakeet-tdt-0.6b-v3-coreml")
            .appending(path: "parakeet_vocab.json")
        let originalSize = try Data(contentsOf: vocabulary).count
        try Data(repeating: 0x20, count: originalSize).write(to: vocabulary, options: .atomic)

        let engine = PrecisionTranscriptionEngine(modelManager: manager)
        await #expect(throws: PrecisionTranscriptionError.self) {
            try await engine.recognize(
                audioURL: environment.englishAudio,
                audioTrackIndex: nil,
                locale: Locale(identifier: "en-US")
            )
        }
        guard case .repairRequired = await manager.state(for: PrecisionTranscriptionEngine.modelID)
        else {
            Issue.record("Runtime load failure must quarantine the installed release")
            return
        }
        #expect(await downloader.callCount == 21)
    }
}

private struct PrecisionIntegrationEnvironment: Sendable {
    let modelDirectory: URL
    let englishAudio: URL
    let englishExpected: String
    let nonEnglishAudio: URL
    let nonEnglishExpected: String
    let nonEnglishLocale: String
    let twoTrackMovie: URL?

    init?(environment: [String: String]) {
        guard let modelPath = environment["LUXEL_PRECISION_MODEL_PATH"],
              let englishPath = environment["LUXEL_PRECISION_ENGLISH_AUDIO_PATH"],
              let englishExpected = environment["LUXEL_PRECISION_ENGLISH_EXPECTED"],
              let nonEnglishPath = environment["LUXEL_PRECISION_NON_ENGLISH_AUDIO_PATH"],
              let nonEnglishExpected = environment["LUXEL_PRECISION_NON_ENGLISH_EXPECTED"],
              let nonEnglishLocale = environment["LUXEL_PRECISION_NON_ENGLISH_LOCALE"]
        else {
            return nil
        }
        modelDirectory = URL(fileURLWithPath: modelPath, isDirectory: true)
        englishAudio = URL(fileURLWithPath: englishPath)
        self.englishExpected = englishExpected
        nonEnglishAudio = URL(fileURLWithPath: nonEnglishPath)
        self.nonEnglishExpected = nonEnglishExpected
        self.nonEnglishLocale = nonEnglishLocale
        twoTrackMovie = environment["LUXEL_PRECISION_TWO_TRACK_MOVIE_PATH"].map {
            URL(fileURLWithPath: $0)
        }
    }
}

private let precisionIntegrationEnvironment = PrecisionIntegrationEnvironment(
    environment: ProcessInfo.processInfo.environment
)

private actor LocalPrecisionFixtureDownloader: LocalModelDownloading {
    let modelDirectory: URL
    private(set) var callCount = 0

    init(modelDirectory: URL) {
        self.modelDirectory = modelDirectory
    }

    func download(
        _ request: LocalModelArtifactDownloadRequest,
        progress: @escaping LocalModelDownloadProgressHandler
    ) async throws {
        callCount += 1
        let source = modelDirectory.appending(path: request.artifact.path)
        try FileManager.default.copyItem(at: source, to: request.destinationURL)
        await progress(request.artifact.byteCount)
    }
}

private func normalized(_ text: String) -> String {
    text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
        .joined(separator: " ")
}
