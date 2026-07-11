import AppKit
import LuxelCore
import SwiftUI

struct TranscriptCardContent: View {
    let transcript: TurnSegmentedTranscript
    let sentences: [TranscriptEditableSentence]
    let activeTurnID: String?
    let activeSpanID: String?
    let spansPerChunk: Int
    let selectedSentenceID: TranscriptEditableSentence.ID?
    let cutCount: Int
    let editStatusMessage: String?
    let canDeleteSelectedSentence: Bool
    let canClose: Bool
    let closeTranscript: () -> Void
    let selectSentence: (TranscriptEditableSentence) -> Void
    let deleteSelectedSentence: () -> Void

    @State private var displayPlan: TranscriptDisplayPlan
    @State private var searchQuery = ""
    @State private var selectedSearchMatchID: String?
    @State private var searchMatches: [TranscriptSearchMatch]
    @FocusState private var transcriptListIsFocused: Bool

    init(
        transcript: TurnSegmentedTranscript,
        sentences: [TranscriptEditableSentence],
        activeTurnID: String?,
        activeSpanID: String?,
        spansPerChunk: Int,
        selectedSentenceID: TranscriptEditableSentence.ID?,
        cutCount: Int,
        editStatusMessage: String?,
        canDeleteSelectedSentence: Bool,
        canClose: Bool,
        closeTranscript: @escaping () -> Void,
        selectSentence: @escaping (TranscriptEditableSentence) -> Void,
        deleteSelectedSentence: @escaping () -> Void
    ) {
        self.transcript = transcript
        self.sentences = sentences
        self.activeTurnID = activeTurnID
        self.activeSpanID = activeSpanID
        self.spansPerChunk = spansPerChunk
        self.selectedSentenceID = selectedSentenceID
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
                        selectedSentenceID: selectedSentenceID,
                        matchedSearchSpanIDs: matchedSearchSpanIDs,
                        currentSearchSpanIDs: currentSearchSpanIDs,
                        selectSentence: { sentence in
                            transcriptListIsFocused = true
                            selectSentence(sentence)
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

    private var selectedSearchMatchIndex: Int? {
        guard let selectedSearchMatchID else {
            return nil
        }

        return searchMatches.firstIndex { $0.id == selectedSearchMatchID }
    }

    private func rebuildDisplayPlan(
        transcript: TurnSegmentedTranscript,
        sentences: [TranscriptEditableSentence],
        spansPerChunk: Int
    ) {
        displayPlan = TranscriptDisplayPlan(
            transcript: transcript,
            sentences: sentences,
            sentencesPerChunk: spansPerChunk
        )
        updateSearchMatches(query: searchQuery)
    }

    private func updateSearchMatches(query: String) {
        let matches = displayPlan.searchMatches(for: query)
        searchMatches = matches

        if matches.isEmpty {
            selectedSearchMatchID = nil
        } else if let selectedSearchMatchID,
                  matches.contains(where: { $0.id == selectedSearchMatchID }) {
        } else {
            selectedSearchMatchID = matches[0].id
        }
    }

    private func selectPreviousSearchMatch() {
        guard !searchMatches.isEmpty else {
            selectedSearchMatchID = nil
            return
        }

        let selectedIndex = selectedSearchMatchIndex ?? 0
        let previousIndex =
            selectedIndex == 0 ? searchMatches.index(before: searchMatches.endIndex) : selectedIndex - 1
        selectedSearchMatchID = searchMatches[previousIndex].id
    }

    private func selectNextSearchMatch() {
        guard !searchMatches.isEmpty else {
            selectedSearchMatchID = nil
            return
        }

        let selectedIndex =
            selectedSearchMatchIndex ?? searchMatches.index(before: searchMatches.endIndex)
        let nextIndex = searchMatches.index(after: selectedIndex)
        selectedSearchMatchID = searchMatches[nextIndex == searchMatches.endIndex ? 0 : nextIndex].id
    }

    private func speakerChipInfo(for turn: TranscriptTurn) -> TranscriptSpeakerChip? {
        guard let speakerID = turn.speakerID,
              let index = transcript.speakers.firstIndex(where: { $0.id == speakerID })
        else {
            return nil
        }

        return TranscriptSpeakerChip(
            displayName: transcript.speakers[index].displayName,
            dotColor: TranscriptSpeakerPalette.dotColor(
                for: transcript.speakers[index].displayName),
            textColor: TranscriptSpeakerPalette.textColor(
                for: transcript.speakers[index].displayName)
        )
    }

    private func copyTranscript(
        _ transcript: TurnSegmentedTranscript,
        sentences: [TranscriptEditableSentence]
    ) {
        let text = transcript.turns.compactMap { turn -> String? in
            let turnText = sentences
                .filter { $0.turnID == turn.id }
                .map(\.text)
                .joined(separator: " ")
            guard !turnText.isEmpty else {
                return nil
            }
            guard !transcript.speakers.isEmpty else {
                return turnText
            }

            var labels: [String] = []
            if let speaker = transcript.speaker(for: turn.speakerID) {
                labels.append(speaker.displayName)
            }
            if let source = turn.source {
                labels.append(source.displayName)
            }

            guard !labels.isEmpty else {
                return turnText
            }

            return "\(labels.joined(separator: " — ")): \(turnText)"
        }
        .joined(separator: "\n\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

struct TranscriptSpeakerChip: Equatable {
    let displayName: String
    let dotColor: Color
    let textColor: Color
}

private struct TranscriptSearchControl: View {
    @Binding var query: String

    let selectedMatchIndex: Int?
    let matchCount: Int
    let selectPrevious: () -> Void
    let selectNext: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))

                TextField("Search", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .onSubmit {
                        selectNext()
                    }
                    .help("Search the transcript.")

                Text(counterText)
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(counterForegroundStyle)
                    .layoutPriority(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(width: 170)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.black.opacity(0.22))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                    }
            }

            if matchCount > 0 {
                Button(action: selectPrevious) {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(LuxelGlassCircleButtonStyle(side: 24))
                .help("Previous match")
                .accessibilityLabel("Previous transcript search match")

                Button(action: selectNext) {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(LuxelGlassCircleButtonStyle(side: 24))
                .help("Next match")
                .accessibilityLabel("Next transcript search match")
            }
        }
        .animation(.easeOut(duration: 0.15), value: matchCount > 0)
    }

    private var counterText: String {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "0/0"
        }

        return "\(selectedMatchIndex.map { $0 + 1 } ?? 0)/\(matchCount)"
    }

    private var counterForegroundStyle: Color {
        if matchCount == 0, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .red
        }

        return .white.opacity(0.4)
    }
}
