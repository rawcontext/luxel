import AppKit
import LuxelCore
import SwiftUI

enum TranscriptEditingGuidance {
    static let dismissalDefaultsKey = "transcriptEditingGuidanceDismissed"
}

struct TranscriptCardContent: View {
    let transcript: TurnSegmentedTranscript
    let words: [TranscriptEditableWord]
    let displayRevision: Int
    let activeTurnID: String?
    let activeSpanID: String?
    let spansPerChunk: Int
    let isCompact: Bool
    let selectedWordIDs: Set<TranscriptEditableWord.ID>
    let cutReviewItems: [TranscriptCutReviewItem]
    let editStatusMessage: String?
    let canDeleteSelectedWord: Bool
    let canUndoLastCut: Bool
    let canClose: Bool
    let closeTranscript: () -> Void
    let selectWord: (TranscriptEditableWord, Bool) -> Void
    let deleteSelectedWord: () -> Bool
    let undoLastCut: () -> Void
    let restoreCut: (String) -> Void

    @State var displayPlan = TranscriptDisplayPlan()
    @State var searchQuery = ""
    @State var selectedSearchMatchID: String?
    @State var searchMatches: [TranscriptSearchMatch] = []
    @FocusState var transcriptListIsFocused: Bool
    @AppStorage var isEditingGuidanceDismissed: Bool

    init(
        transcript: TurnSegmentedTranscript,
        words: [TranscriptEditableWord],
        displayRevision: Int,
        activeTurnID: String?,
        activeSpanID: String?,
        spansPerChunk: Int,
        isCompact: Bool = false,
        selectedWordIDs: Set<TranscriptEditableWord.ID>,
        cutReviewItems: [TranscriptCutReviewItem],
        editStatusMessage: String?,
        canDeleteSelectedWord: Bool,
        canUndoLastCut: Bool,
        canClose: Bool,
        guidanceDefaults: UserDefaults = .standard,
        closeTranscript: @escaping () -> Void,
        selectWord: @escaping (TranscriptEditableWord, Bool) -> Void,
        deleteSelectedWord: @escaping () -> Bool,
        undoLastCut: @escaping () -> Void,
        restoreCut: @escaping (String) -> Void
    ) {
        self.transcript = transcript
        self.words = words
        self.displayRevision = displayRevision
        self.activeTurnID = activeTurnID
        self.activeSpanID = activeSpanID
        self.spansPerChunk = spansPerChunk
        self.isCompact = isCompact
        self.selectedWordIDs = selectedWordIDs
        self.cutReviewItems = cutReviewItems
        self.editStatusMessage = editStatusMessage
        self.canDeleteSelectedWord = canDeleteSelectedWord
        self.canUndoLastCut = canUndoLastCut
        self.canClose = canClose
        self.closeTranscript = closeTranscript
        self.selectWord = selectWord
        self.deleteSelectedWord = deleteSelectedWord
        self.undoLastCut = undoLastCut
        self.restoreCut = restoreCut
        _isEditingGuidanceDismissed = AppStorage(
            wrappedValue: false,
            TranscriptEditingGuidance.dismissalDefaultsKey,
            store: guidanceDefaults
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if isCompact {
                compactTranscriptToolbar
            } else {
                transcriptToolbar
            }

            LuxelGlassRowDivider()

            if !isEditingGuidanceDismissed {
                editingGuidance
                LuxelGlassRowDivider()
            }

            transcriptList
        }
        .onChange(of: searchQuery) { _, query in
            updateSearchMatches(query: query)
        }
        .onAppear {
            rebuildDisplayPlan(
                transcript: transcript,
                words: words,
                spansPerChunk: spansPerChunk
            )
        }
        .onChange(of: displayRevision) {
            rebuildDisplayPlan(
                transcript: transcript,
                words: words,
                spansPerChunk: spansPerChunk
            )
        }
        .onChange(of: spansPerChunk) { _, spansPerChunk in
            rebuildDisplayPlan(
                transcript: transcript,
                words: words,
                spansPerChunk: spansPerChunk
            )
        }
    }

    private var transcriptToolbar: some View {
        HStack(spacing: 8) {
            Text("Transcript")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))

            if !transcript.speakers.isEmpty {
                speakerCountChip
            }

            if let editStatusMessage {
                Text(editStatusMessage)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }

            if canUndoLastCut {
                undoCutButton
            }

            Spacer(minLength: 8)

            TranscriptSearchControl(
                query: $searchQuery,
                selectedMatchIndex: selectedSearchMatchIndex,
                matchCount: searchMatches.count,
                selectPrevious: selectPreviousSearchMatch,
                selectNext: selectNextSearchMatch
            )

            if !cutReviewItems.isEmpty {
                cutReviewMenu
            }

            Button {
                copyTranscript(transcript, words: words)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(LuxelGlassCircleButtonStyle())
            .help("Copy transcript")
            .accessibilityLabel("Copy transcript")

            if canDeleteSelectedWord {
                cutSelectionButton
            }

            if canClose {
                Button {
                    closeTranscript()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(LuxelGlassCircleButtonStyle())
                .help("Close transcript")
                .accessibilityLabel("Close transcript")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var transcriptList: some View {
        let selectedSearchMatch = searchMatches.first { $0.id == selectedSearchMatchID }
        let matchedSearchSpanIDs = Set(searchMatches.flatMap(\.spanIDs))
        let currentSearchSpanIDs = selectedSearchMatch?.spanIDs ?? []
        let scrollTargetID =
            selectedSearchMatch?.chunkID
            ?? displayPlan.scrollTargetID(activeSpanID: activeSpanID, activeTurnID: activeTurnID)

        return ScrollViewReader { proxy in
            List {
                ForEach(displayPlan.chunks) { chunk in
                    TranscriptChunkView(
                        chunk: chunk,
                        speakerChip: speakerChipInfo(for: chunk.turn),
                        isActiveTurn: chunk.turn.id == activeTurnID,
                        activeSpanID: activeSpanID,
                        selectedWordIDs: selectedWordIDs,
                        matchedSearchSpanIDs: matchedSearchSpanIDs,
                        currentSearchSpanIDs: currentSearchSpanIDs,
                        selectWord: { word, extendingSelection in
                            transcriptListIsFocused = true
                            selectWord(word, extendingSelection)
                        }
                    )
                    .id(chunk.id)
                    .listRowInsets(EdgeInsets(top: 1, leading: 14, bottom: 1, trailing: 14))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.never)
            .environment(\.defaultMinListRowHeight, 0)
            .focusable()
            .focused($transcriptListIsFocused)
            .onDeleteCommand {
                guard canDeleteSelectedWord else {
                    return
                }
                performCut()
            }
            .onChange(of: scrollTargetID) { _, targetID in
                guard let targetID else {
                    return
                }

                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(targetID, anchor: .center)
                }
            }
        }
    }

}

extension TranscriptCardContent {
    var compactTranscriptToolbar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Text("Transcript")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))

                if !transcript.speakers.isEmpty {
                    speakerCountChip
                }

                Spacer(minLength: 8)

                if !cutReviewItems.isEmpty {
                    cutReviewMenu
                }

                if canClose {
                    Button {
                        closeTranscript()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(LuxelGlassCircleButtonStyle(side: 24))
                    .help("Close transcript")
                    .accessibilityLabel("Close transcript")
                }
            }

            HStack(spacing: 6) {
                TranscriptSearchControl(
                    query: $searchQuery,
                    selectedMatchIndex: selectedSearchMatchIndex,
                    matchCount: searchMatches.count,
                    isCompact: true,
                    selectPrevious: selectPreviousSearchMatch,
                    selectNext: selectNextSearchMatch
                )

                Button {
                    copyTranscript(transcript, words: words)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(LuxelGlassCircleButtonStyle(side: 24))
                .help("Copy transcript")
                .accessibilityLabel("Copy transcript")
            }

            if canDeleteSelectedWord || canUndoLastCut || editStatusMessage != nil {
                HStack(spacing: 8) {
                    if canDeleteSelectedWord {
                        cutSelectionButton
                    }

                    if let editStatusMessage {
                        Text(editStatusMessage)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    if canUndoLastCut {
                        undoCutButton
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    var undoCutButton: some View {
        Button("Undo") {
            undoLastCut()
        }
        .buttonStyle(.plain)
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(.white.opacity(0.85))
        .help("Undo the transcript cut. You can also press Command-Z.")
        .accessibilityHint("Restores the words and media removed by the last transcript cut.")
    }

    var cutSelectionButton: some View {
        Button {
            performCut()
        } label: {
            HStack(spacing: 5) {
                Label("Cut from recording", systemImage: "scissors")
                Text("⌫")
                    .foregroundStyle(.white.opacity(0.55))
            }
            .font(.system(size: 10.5, weight: .semibold))
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(.white.opacity(0.09), in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Cut selected words from the recording (Delete)")
        .accessibilityLabel("Cut selected words from recording")
        .accessibilityHint(
            "Press Delete to cut the selected words. The original recording stays safe."
        )
    }
}

struct TranscriptSpeakerChip: Equatable {
    let displayName: String
    let dotColor: Color
    let textColor: Color
}
