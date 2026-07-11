import AppKit
import LuxelCore
import SwiftUI

struct TranscriptCardContent: View {
    let transcript: TurnSegmentedTranscript
    let sentences: [TranscriptEditableSentence]
    let activeTurnID: String?
    let activeSpanID: String?
    let spansPerChunk: Int
    let selectedSentenceIDs: Set<TranscriptEditableSentence.ID>
    let cutCount: Int
    let editStatusMessage: String?
    let canDeleteSelectedSentence: Bool
    let canClose: Bool
    let closeTranscript: () -> Void
    let selectSentence: (TranscriptEditableSentence, Bool) -> Void
    let deleteSelectedSentence: () -> Void

    @State var displayPlan: TranscriptDisplayPlan
    @State var searchQuery = ""
    @State var selectedSearchMatchID: String?
    @State var searchMatches: [TranscriptSearchMatch]
    @FocusState var transcriptListIsFocused: Bool

    init(
        transcript: TurnSegmentedTranscript,
        sentences: [TranscriptEditableSentence],
        activeTurnID: String?,
        activeSpanID: String?,
        spansPerChunk: Int,
        selectedSentenceIDs: Set<TranscriptEditableSentence.ID>,
        cutCount: Int,
        editStatusMessage: String?,
        canDeleteSelectedSentence: Bool,
        canClose: Bool,
        closeTranscript: @escaping () -> Void,
        selectSentence: @escaping (TranscriptEditableSentence, Bool) -> Void,
        deleteSelectedSentence: @escaping () -> Void
    ) {
        self.transcript = transcript
        self.sentences = sentences
        self.activeTurnID = activeTurnID
        self.activeSpanID = activeSpanID
        self.spansPerChunk = spansPerChunk
        self.selectedSentenceIDs = selectedSentenceIDs
        self.cutCount = cutCount
        self.editStatusMessage = editStatusMessage
        self.canDeleteSelectedSentence = canDeleteSelectedSentence
        self.canClose = canClose
        self.closeTranscript = closeTranscript
        self.selectSentence = selectSentence
        self.deleteSelectedSentence = deleteSelectedSentence
        let displayPlan = TranscriptDisplayPlan(
            transcript: transcript,
            sentences: sentences,
            sentencesPerChunk: spansPerChunk
        )
        _displayPlan = State(
            initialValue: displayPlan)
        _searchMatches = State(
            initialValue: displayPlan.searchMatches(for: ""))
    }

    var body: some View {
        VStack(spacing: 0) {
            transcriptToolbar

            LuxelGlassRowDivider()

            transcriptList
        }
        .onChange(of: searchQuery) { _, query in
            updateSearchMatches(query: query)
        }
        .onChange(of: transcript) { _, transcript in
            rebuildDisplayPlan(
                transcript: transcript,
                sentences: sentences,
                spansPerChunk: spansPerChunk
            )
        }
        .onChange(of: sentences) { _, sentences in
            rebuildDisplayPlan(
                transcript: transcript,
                sentences: sentences,
                spansPerChunk: spansPerChunk
            )
        }
        .onChange(of: spansPerChunk) { _, spansPerChunk in
            rebuildDisplayPlan(
                transcript: transcript,
                sentences: sentences,
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

            if cutCount > 0 {
                Text("\(cutCount) \(cutCount == 1 ? "cut" : "cuts")")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
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

            Button {
                copyTranscript(transcript, sentences: sentences)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(LuxelGlassCircleButtonStyle())
            .help("Copy transcript")
            .accessibilityLabel("Copy transcript")

            Button {
                deleteSelectedSentence()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(LuxelGlassCircleButtonStyle())
            .disabled(!canDeleteSelectedSentence)
            .help("Cut selected transcript sentence")
            .accessibilityLabel("Cut selected transcript sentence")

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

    private var speakerCountChip: some View {
        HStack(spacing: 6) {
            HStack(spacing: -3) {
                ForEach(
                    Array(transcript.speakers.prefix(3).enumerated()),
                    id: \.element.id
                ) { _, speaker in
                    Circle()
                        .fill(TranscriptSpeakerPalette.dotColor(for: speaker.displayName))
                        .frame(width: 8, height: 8)
                        .overlay {
                            Circle().strokeBorder(.black.opacity(0.6), lineWidth: 1.5)
                        }
                }
            }

            Text(
                transcript.speakers.count == 1
                    ? "1 Speaker" : "\(transcript.speakers.count) Speakers"
            )
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel("\(transcript.speakers.count) speakers detected")
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
                        selectedSentenceIDs: selectedSentenceIDs,
                        matchedSearchSpanIDs: matchedSearchSpanIDs,
                        currentSearchSpanIDs: currentSearchSpanIDs,
                        selectSentence: { sentence, extendingSelection in
                            transcriptListIsFocused = true
                            selectSentence(sentence, extendingSelection)
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
                guard canDeleteSelectedSentence else {
                    return
                }
                deleteSelectedSentence()
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

struct TranscriptSpeakerChip: Equatable {
    let displayName: String
    let dotColor: Color
    let textColor: Color
}
