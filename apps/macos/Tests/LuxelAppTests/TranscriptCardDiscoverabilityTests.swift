import Foundation
import LuxelCore
import Testing

@testable import LuxelPresentation

@MainActor
@Suite("Transcript card discoverability")
struct TranscriptCardDiscoverabilityTests {
    @Test("transcript words remain keyboard focusable with selection instructions")
    func keyboardSelectionConfiguration() throws {
        let source = try String(
            contentsOf: packageRoot.appending(
                path: "Sources/LuxelPresentation/Editor/Views/TranscriptDisplaySupport.swift"
            ),
            encoding: .utf8
        )

        #expect(!source.contains(".focusable(false)"))
        #expect(source.contains("Hold Shift while activating to extend the selection."))
        #expect(source.contains(".accessibilityValue(isSelected ? \"Selected\" : \"Not selected\")"))
    }

    @Test("transcript editing actions use adjacent icon controls with tooltips")
    func transcriptEditingActionConfiguration() throws {
        let cardSource = try String(
            contentsOf: packageRoot.appending(
                path: "Sources/LuxelPresentation/Editor/Views/TranscriptCardContent.swift"
            ),
            encoding: .utf8
        )
        let editingSource = try String(
            contentsOf: packageRoot.appending(
                path: "Sources/LuxelPresentation/Editor/Views/TranscriptCardContent+Editing.swift"
            ),
            encoding: .utf8
        )
        let source = cardSource + editingSource

        #expect(source.contains("if canDeleteSelectedWord"))
        #expect(source.contains("Image(systemName: \"scissors\")"))
        #expect(source.contains("Image(systemName: \"list.bullet.rectangle.portrait\")"))
        #expect(source.contains("Image(systemName: \"arrow.uturn.backward\")"))
        #expect(source.contains("cutReviewMenu(side: side)"))
        #expect(source.contains("cutSelectionButton(side: side)"))
        #expect(source.contains(".onDeleteCommand"))
        #expect(source.contains("Cut selected words from the recording (Delete)"))
        #expect(source.contains(".accessibilityLabel(\"Cut selected words from recording\")"))
        #expect(source.contains("if canUndoLastCut"))
        #expect(source.contains("if !cutReviewItems.isEmpty"))
        #expect(source.contains("restoreCut(cut.id)"))
        #expect(source.contains("Review and restore removed transcript ranges"))
    }

    @Test("speaker and format labels avoid repeated toolbar text")
    func compactLabels() throws {
        let actionSource = try String(
            contentsOf: packageRoot.appending(
                path: "Sources/LuxelPresentation/Editor/Views/TranscriptCardContent+Actions.swift"
            ),
            encoding: .utf8
        )
        let exportSource = try String(
            contentsOf: packageRoot.appending(
                path: "Sources/LuxelPresentation/Editor/Views/LuxelEditorView+ExportControls.swift"
            ),
            encoding: .utf8
        )

        #expect(actionSource.contains("Text(\"\\(transcript.speakers.count)\")"))
        #expect(!actionSource.contains("\\(transcript.speakers.count) Speakers"))
        #expect(exportSource.contains("editorDisclosureCard(\"Format\")"))
        #expect(!exportSource.contains("controlRow(\"Format\")"))
    }

    @Test("guidance dismissal and a successful cut persist")
    func guidancePersistence() throws {
        let suiteName = "TranscriptCardDiscoverabilityTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let failedCut = try content(guidanceDefaults: defaults, deleteSelectedWord: { false })
        #expect(!failedCut.isEditingGuidanceDismissed)
        failedCut.performCut()
        #expect(!defaults.bool(forKey: TranscriptEditingGuidance.dismissalDefaultsKey))

        failedCut.dismissEditingGuidance()
        #expect(defaults.bool(forKey: TranscriptEditingGuidance.dismissalDefaultsKey))
        let dismissedReopen = try content(
            guidanceDefaults: defaults,
            deleteSelectedWord: { false }
        )
        #expect(dismissedReopen.isEditingGuidanceDismissed)

        defaults.set(false, forKey: TranscriptEditingGuidance.dismissalDefaultsKey)

        let successfulCut = try content(guidanceDefaults: defaults, deleteSelectedWord: { true })
        successfulCut.performCut()
        #expect(defaults.bool(forKey: TranscriptEditingGuidance.dismissalDefaultsKey))

        let reopened = try content(guidanceDefaults: defaults, deleteSelectedWord: { false })
        #expect(reopened.isEditingGuidanceDismissed)
    }

    @Test("cut review labels identify removed words and source range")
    func cutReviewLabel() throws {
        let card = try content(deleteSelectedWord: { false })
        let item = TranscriptCutReviewItem(
            id: "cut",
            text: "remove these words",
            sourceRange: try TimeRange(start: 61.2, end: 63.9)
        )

        #expect(card.cutRestoreLabel(item) == "Restore “remove these words” (1:01–1:03)")
    }

    @Test("auto-play is enabled by default and persists user changes")
    func autoPlayPreference() throws {
        let suiteName = "TranscriptCardAutoPlayTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let initial = try content(guidanceDefaults: defaults, deleteSelectedWord: { false })
        #expect(initial.isTranscriptAutoPlayEnabled)

        initial.isTranscriptAutoPlayEnabled = false

        let reopened = try content(guidanceDefaults: defaults, deleteSelectedWord: { false })
        #expect(!reopened.isTranscriptAutoPlayEnabled)

        let cardSource = try String(
            contentsOf: packageRoot.appending(
                path: "Sources/LuxelPresentation/Editor/Views/TranscriptCardContent.swift"
            ),
            encoding: .utf8
        )
        let capsuleSource = try String(
            contentsOf: packageRoot.appending(
                path: "Sources/LuxelPresentation/Editor/Views/EditorPlaybackCapsule.swift"
            ),
            encoding: .utf8
        )
        #expect(capsuleSource.contains("Toggle(\"Auto-play\""))
        #expect(capsuleSource.contains("TranscriptPlaybackPreferences.autoPlayDefaultsKey"))
        #expect(cardSource.contains("isTranscriptAutoPlayEnabled"))
    }

    private func content(
        guidanceDefaults: UserDefaults = .standard,
        deleteSelectedWord: @escaping () -> Bool
    ) throws -> TranscriptCardContent {
        let span = try TimedTranscriptSpan(id: "word", text: "Word", start: 0, end: 1)
        let transcript = try TurnSegmentedTranscript(
            spans: [span],
            turns: [
                TranscriptTurn(
                    id: "turn",
                    spanIDs: [span.id],
                    start: 0,
                    end: 1,
                    text: span.text
                )
            ],
            localeIdentifier: "en_US"
        )
        return TranscriptCardContent(
            transcript: transcript,
            words: try TranscriptWordIndex(transcript: transcript).words,
            displayRevision: 0,
            activeTurnID: nil,
            activeSpanID: nil,
            spansPerChunk: 32,
            selectedWordIDs: [],
            cutReviewItems: [],
            editStatusMessage: nil,
            canDeleteSelectedWord: true,
            canUndoLastCut: false,
            canClose: false,
            guidanceDefaults: guidanceDefaults,
            closeTranscript: {},
            selectWord: { _, _, _ in },
            deleteSelectedWord: deleteSelectedWord,
            undoLastCut: {},
            restoreCut: { _ in }
        )
    }
}

private let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
