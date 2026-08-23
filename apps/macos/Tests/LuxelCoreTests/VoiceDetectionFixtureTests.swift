@preconcurrency import AVFoundation
import CryptoKit
import Foundation
@testable import LuxelCore
import Testing

@Suite("Voice detection fixture benchmark", .serialized)
struct VoiceDetectionFixtureTests {
    @Test("fixture manifest records provenance formats and matching checksums")
    func fixtureManifest() throws {
        let corpus = try VoiceDetectionFixtureCorpus.load()

        #expect(corpus.manifest.schemaVersion == 1)
        #expect(corpus.manifest.speechSource.license == "CC BY 4.0")
        #expect(corpus.manifest.fixtures.count == 9)
        #expect(Set(corpus.manifest.fixtures.map(\.sampleRate)) == [16_000, 44_100, 48_000])
        #expect(Set(corpus.manifest.fixtures.map(\.channels)) == [1, 2])

        for fixture in corpus.manifest.fixtures {
            let data = try Data(contentsOf: corpus.url(for: fixture))
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            #expect(digest == fixture.sha256, "Checksum mismatch for \(fixture.file)")
            #expect(!fixture.provenance.isEmpty)
            #expect(!fixture.consentLicense.isEmpty)
            #expect(fixture.durationSeconds > 0)
            #expect(fixture.bitsPerSample == 16)
        }
    }

    @Test("bundled model and production pipeline meet prompt precision gates")
    func productionPipelinePromptBehavior() async throws {
        let corpus = try VoiceDetectionFixtureCorpus.load()
        let modelURL = packageRoot
            .appending(path: "Vendor/Models/voice-activity-detection")
            .appending(path: BundledVoiceActivityModelLocator.modelDirectoryName)

        for fixture in corpus.manifest.fixtures {
            let result = try await benchmark(
                fixture: fixture,
                fileURL: corpus.url(for: fixture),
                modelURL: modelURL
            )
            if ProcessInfo.processInfo.environment["VOICE_DETECTION_BENCHMARK_REPORT"] == "1" {
                print(result.reportLine(fixtureName: fixture.file))
            }

            switch fixture.expected {
            case .prompt:
                #expect(result.promptCount == 1, "Expected one prompt for \(fixture.file)")
                #expect(
                    result.firstPromptSecondsFromStart.map { $0 <= 2 } == true,
                    "Prompt was late for \(fixture.file)"
                )
            case .noPrompt:
                #expect(result.promptCount == 0, "Unexpected prompt for \(fixture.file)")
            }
            #expect(result.modelFrameCount > 0)
        }
    }

    private func benchmark(
        fixture: VoiceDetectionFixture,
        fileURL: URL,
        modelURL: URL
    ) async throws -> VoiceDetectionFixtureResult {
        var pipeline = try await VoiceActivityInferencePipeline(modelURL: modelURL)
        let service = VoiceDetectionService()
        _ = await service.reconcile(eligibility: .fixtureEligible)
        let file = try AVAudioFile(forReading: fileURL)
        let chunkSizes = [AVAudioFrameCount(1_777), 4_096, 8_111]
        var chunkIndex = 0
        var sourceFramePosition: AVAudioFramePosition = 0
        var modelFrameIndex = 0
        var promptCount = 0
        var firstPromptSeconds: TimeInterval?
        let startDate = Date(timeIntervalSince1970: 1_800_000_000)

        while file.framePosition < file.length {
            let remaining = AVAudioFrameCount(file.length - file.framePosition)
            let capacity = min(remaining, chunkSizes[chunkIndex % chunkSizes.count])
            let buffer = try #require(AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: capacity
            ))
            try file.read(into: buffer, frameCount: capacity)
            let sampleRate = Int32(file.processingFormat.sampleRate)
            let observations = try await pipeline.process(CapturedVoiceActivityBuffer(
                buffer: buffer,
                presentationTime: CMTime(value: sourceFramePosition, timescale: sampleRate),
                duration: CMTime(value: Int64(buffer.frameLength), timescale: sampleRate)
            ))

            for observation in observations {
                let observedAt = startDate.addingTimeInterval(
                    Double(modelFrameIndex) * observation.frameDuration
                )
                let effects = await service.handle(.observation(VoiceActivityObservation(
                    probability: observation.probability,
                    frameDuration: observation.frameDuration,
                    observedAt: observedAt,
                    kind: observation.kind
                )))
                if effects.contains(.postPrompt) {
                    promptCount += 1
                    firstPromptSeconds = firstPromptSeconds
                        ?? observedAt.timeIntervalSince(startDate)
                }
                modelFrameIndex += 1
            }

            sourceFramePosition += AVAudioFramePosition(buffer.frameLength)
            chunkIndex += 1
        }

        return VoiceDetectionFixtureResult(
            promptCount: promptCount,
            firstPromptSecondsFromStart: firstPromptSeconds,
            modelFrameCount: modelFrameIndex
        )
    }
}

private struct VoiceDetectionFixtureResult {
    let promptCount: Int
    let firstPromptSecondsFromStart: TimeInterval?
    let modelFrameCount: Int

    func reportLine(fixtureName: String) -> String {
        let promptTime = firstPromptSecondsFromStart
            .map { String(format: "%.3f", $0) }
            ?? "none"
        return "\(fixtureName): frames=\(modelFrameCount), prompts=\(promptCount), firstPromptSeconds=\(promptTime)"
    }
}

private struct VoiceDetectionFixtureCorpus {
    let directoryURL: URL
    let manifest: VoiceDetectionFixtureManifest

    static func load() throws -> VoiceDetectionFixtureCorpus {
        let manifestURL = try #require(Bundle.module.url(
            forResource: "manifest",
            withExtension: "json"
        ))
        let directory = manifestURL.deletingLastPathComponent()
        let data = try Data(contentsOf: manifestURL)
        return VoiceDetectionFixtureCorpus(
            directoryURL: directory,
            manifest: try JSONDecoder().decode(VoiceDetectionFixtureManifest.self, from: data)
        )
    }

    func url(for fixture: VoiceDetectionFixture) -> URL {
        directoryURL.appending(path: fixture.file)
    }
}

private struct VoiceDetectionFixtureManifest: Decodable {
    let schemaVersion: Int
    let speechSource: VoiceDetectionSpeechSource
    let fixtures: [VoiceDetectionFixture]
}

private struct VoiceDetectionSpeechSource: Decodable {
    let license: String
}

private struct VoiceDetectionFixture: Decodable {
    enum Expected: String, Decodable {
        case prompt
        case noPrompt
    }

    let file: String
    let expected: Expected
    let provenance: String
    let consentLicense: String
    let durationSeconds: TimeInterval
    let sampleRate: Int
    let channels: Int
    let bitsPerSample: Int
    let sha256: String
}

private extension VoiceDetectionEligibility {
    static let fixtureEligible = VoiceDetectionEligibility(
        isEnabled: true,
        isDisclosureAccepted: true,
        notificationPermission: .authorized,
        microphonePermission: .authorized,
        microphone: VoiceDetectionMicrophone(deviceID: nil, name: "Fixture"),
        isModelAvailable: true,
        isDetectorReady: true,
        isRecordingLifecycleIdle: true,
        isSessionLocked: false,
        isDisplayAsleep: false
    )
}

private let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
