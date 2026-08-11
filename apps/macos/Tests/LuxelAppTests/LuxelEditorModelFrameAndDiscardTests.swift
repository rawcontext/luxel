import Foundation
import LuxelCore
import Testing

@testable import LuxelPresentation

extension LuxelEditorModelTests {
    @Test("save current frame asks for destination and writes selected file")
    func saveCurrentFrameAsksForDestinationAndWritesSelectedFile() async throws {
        let imageData = try frameImageData()
        let frameGrabber = SpyFrameGrabber(imageData: imageData)
        let fileWriter = SpyFrameGrabFileWriter()
        let destinationURL = URL(fileURLWithPath: "/tmp/source frame.png")
        let fileActionClient = StubExportedFileActionClient(saveDestination: destinationURL)
        let model = makeModel(
            fileActionClient: fileActionClient,
            frameGrabber: frameGrabber,
            frameGrabFileWriter: fileWriter
        )
        let sourceURL = URL(fileURLWithPath: "/tmp/source.mp4")

        await model.open(fileURL: sourceURL, outputDirectory: URL(fileURLWithPath: "/tmp"))
        model.saveCurrentFrameAs()

        while model.isGrabbingFrame {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(fileActionClient.requestedSaveNames == ["source (frame 0.00.0).png"])
        #expect(
            fileWriter.writes == [
                SpyFrameGrabFileWriter.Write(imageData: imageData, fileURL: destinationURL)
            ])
        #expect(
            frameGrabber.requests == [
                try FrameGrabRequest(sourceFileURL: sourceURL, time: 0)
            ])
        #expect(model.status == .savedFrame(destinationURL))
        #expect(model.statusMessage == "Saved source frame.png")
    }

    @Test("discard recording trashes source and clears editor")
    func discardRecordingTrashesSourceAndClearsEditor() async throws {
        let fixture = await discardFixture()
        let didDiscard = fixture.model.discardRecording()

        #expect(didDiscard)
        #expect(fixture.fileSystem.trashedFiles == [fixture.sourceURL])
        #expect(fixture.discardedURLs.values == [fixture.sourceURL])
        #expect(!fixture.model.hasSource)
        #expect(!fixture.model.canDiscard)
        #expect(fixture.model.status == .discarded("source.mp4"))
        #expect(fixture.model.statusMessage == "Discarded source.mp4")
    }

    @Test("discard recording keeps source when trash fails")
    func discardRecordingKeepsSourceWhenTrashFails() async throws {
        let fixture = await discardFixture(trashError: StubError.trashFailed)
        let didDiscard = fixture.model.discardRecording()

        #expect(!didDiscard)
        #expect(fixture.fileSystem.trashedFiles == [fixture.sourceURL])
        #expect(fixture.discardedURLs.values.isEmpty)
        #expect(fixture.model.hasSource)

        if case .failed = fixture.model.status {
        } else {
            Issue.record("Expected discard failure status")
        }
    }

    private func discardFixture(
        trashError: Error? = nil
    ) async -> DiscardFixture {
        let fileSystem = SpyFileSystem(trashError: trashError)
        let sourceURL = URL(fileURLWithPath: "/tmp/source.mp4")
        let discardedURLs = DiscardedURLRecorder()
        let model = makeModel(fileSystem: fileSystem)
        model.configureDiscard(confirmDiscard: false) { fileURL in
            discardedURLs.values.append(fileURL)
        }
        await model.open(fileURL: sourceURL, outputDirectory: URL(fileURLWithPath: "/tmp"))
        return DiscardFixture(
            model: model,
            fileSystem: fileSystem,
            sourceURL: sourceURL,
            discardedURLs: discardedURLs
        )
    }
}

@MainActor
private final class DiscardedURLRecorder {
    var values: [URL] = []
}

private struct DiscardFixture {
    let model: LuxelEditorModel
    let fileSystem: SpyFileSystem
    let sourceURL: URL
    let discardedURLs: DiscardedURLRecorder
}
