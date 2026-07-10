import AppKit
import LuxelCore
import SwiftUI

struct TranscriptCardContent: View {
    let transcript: TurnSegmentedTranscript
    let activeTurnID: String?
    let activeSpanID: String?
    let spansPerChunk: Int
    let canClose: Bool
    let closeTranscript: () -> Void
    let seekToSpan: (TimedTranscriptSpan) -> Void

    @State private var displayPlan: TranscriptDisplayPlan
    @State private var searchQuery = ""
    @State private var selectedSearchMatchID: String?
    @State private var searchMatches: [TranscriptSearchMatch]

    init(
        transcript: TurnSegmentedTranscript,
        activeTurnID: String?,
        activeSpanID: String?,
        spansPerChunk: Int,
        canClose: Bool,
        closeTranscript: @escaping () -> Void,
        seekToSpan: @escaping (TimedTranscriptSpan) -> Void
    ) {
        self.transcript = transcript
        self.activeTurnID = activeTurnID
        self.activeSpanID = activeSpanID
        self.spansPerChunk = spansPerChunk
        self.canClose = canClose
        self.closeTranscript = closeTranscript
        self.seekToSpan = seekToSpan
        let displayPlan = TranscriptDisplayPlan(
            transcript: transcript,
            spansPerChunk: spansPerChunk
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
            rebuildDisplayPlan(transcript: transcript, spansPerChunk: spansPerChunk)
        }
        .onChange(of: spansPerChunk) { _, spansPerChunk in
            rebuildDisplayPlan(transcript: transcript, spansPerChunk: spansPerChunk)
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

            Spacer(minLength: 8)

            TranscriptSearchControl(
                query: $searchQuery,
                selectedMatchIndex: selectedSearchMatchIndex,
                matchCount: searchMatches.count,
                selectPrevious: selectPreviousSearchMatch,
                selectNext: selectNextSearchMatch
            )

            Button {
                copyTranscript(transcript)
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
                        matchedSearchSpanIDs: matchedSearchSpanIDs,
                        currentSearchSpanIDs: currentSearchSpanIDs,
                        seekToSpan: seekToSpan
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

    private func rebuildDisplayPlan(transcript: TurnSegmentedTranscript, spansPerChunk: Int) {
        displayPlan = TranscriptDisplayPlan(
            transcript: transcript,
            spansPerChunk: spansPerChunk
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

    private func copyTranscript(_ transcript: TurnSegmentedTranscript) {
        // Non-diarized transcripts copy exactly as before; speaker/source
        // prefixes appear only when speaker labels exist.
        let text = transcript.turns.map { turn in
            guard !transcript.speakers.isEmpty else {
                return turn.text
            }

            var labels: [String] = []
            if let speaker = transcript.speaker(for: turn.speakerID) {
                labels.append(speaker.displayName)
            }
            if let source = turn.source {
                labels.append(source.displayName)
            }

            guard !labels.isEmpty else {
                return turn.text
            }

            return "\(labels.joined(separator: " — ")): \(turn.text)"
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
