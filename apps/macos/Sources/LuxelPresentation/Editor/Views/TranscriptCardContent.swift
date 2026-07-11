import AppKit
import LuxelCore
import SwiftUI

enum TranscriptEditingGuidance {
    static let dismissalDefaultsKey = "transcriptEditingGuidanceDismissed"
}

enum TranscriptPlaybackPreferences {
    static let autoPlayDefaultsKey = "transcriptAutoPlayEnabled"
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
    let selectWord: (TranscriptEditableWord, Bool, Bool) -> Void
    let deleteSelectedWord: () -> Bool
    let undoLastCut: () -> Void
    let restoreCut: (String) -> Void

    @State var displayPlan = TranscriptDisplayPlan()
    @State var searchQuery = ""
    @State var selectedSearchMatchID: String?
    @State var searchMatches: [TranscriptSearchMatch] = []
    @FocusState var transcriptListIsFocused: Bool
    @AppStorage var isEditingGuidanceDismissed: Bool
    @AppStorage var isTranscriptAutoPlayEnabled: Bool

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
        selectWord: @escaping (TranscriptEditableWord, Bool, Bool) -> Void,
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
        _isTranscriptAutoPlayEnabled = AppStorage(
            wrappedValue: true,
            TranscriptPlaybackPreferences.autoPlayDefaultsKey,
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

            Spacer(minLength: 8)

            TranscriptSearchControl(
                query: $searchQuery,
                selectedMatchIndex: selectedSearchMatchIndex,
                matchCount: searchMatches.count,
                selectPrevious: selectPreviousSearchMatch,
                selectNext: selectNextSearchMatch
            )

            transcriptEditActionButtons(side: 30)

            if canUndoLastCut {
                undoCutButton(side: 30)
            }

            Button {
                copyTranscript(transcript, words: words)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(LuxelGlassCircleButtonStyle())
            .help("Copy transcript")
            .accessibilityLabel("Copy transcript")

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
                            selectWord(
                                word,
                                extendingSelection,
                                isTranscriptAutoPlayEnabled
                            )
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

            if !cutReviewItems.isEmpty
                || canDeleteSelectedWord
                || canUndoLastCut
                || editStatusMessage != nil {
                HStack(spacing: 8) {
                    transcriptEditActionButtons(side: 24)

                    if let editStatusMessage {
                        Text(editStatusMessage)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    if canUndoLastCut {
                        undoCutButton(side: 24)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    func transcriptEditActionButtons(side: CGFloat) -> some View {
        HStack(spacing: 6) {
            if !cutReviewItems.isEmpty {
                cutReviewMenu(side: side)
            }

            if canDeleteSelectedWord {
                cutSelectionButton(side: side)
            }
        }
    }

    func undoCutButton(side: CGFloat) -> some View {
        Button {
            undoLastCut()
        } label: {
            Image(systemName: "arrow.uturn.backward")
        }
        .buttonStyle(LuxelGlassCircleButtonStyle(side: side))
        .help("Undo the transcript cut. You can also press Command-Z.")
        .accessibilityLabel("Undo")
        .accessibilityHint("Restores the words and media removed by the last transcript cut.")
    }

    func cutSelectionButton(side: CGFloat) -> some View {
        Button {
            performCut()
        } label: {
            Image(systemName: "scissors")
        }
        .buttonStyle(LuxelGlassCircleButtonStyle(side: side))
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
