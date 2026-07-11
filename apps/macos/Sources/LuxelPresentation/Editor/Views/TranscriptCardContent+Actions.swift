import AppKit
import LuxelCore
import SwiftUI

extension TranscriptCardContent {
    var speakerCountChip: some View {
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

    var selectedSearchMatchIndex: Int? {
        guard let selectedSearchMatchID else {
            return nil
        }
        return searchMatches.firstIndex { $0.id == selectedSearchMatchID }
    }

    func rebuildDisplayPlan(
        transcript: TurnSegmentedTranscript,
        words: [TranscriptEditableWord],
        spansPerChunk: Int
    ) {
        displayPlan = TranscriptDisplayPlan(
            transcript: transcript,
            words: words,
            wordsPerChunk: spansPerChunk
        )
        updateSearchMatches(query: searchQuery)
    }

    func updateSearchMatches(query: String) {
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

    func selectPreviousSearchMatch() {
        guard !searchMatches.isEmpty else {
            selectedSearchMatchID = nil
            return
        }
        let selectedIndex = selectedSearchMatchIndex ?? 0
        let previousIndex = selectedIndex == 0
            ? searchMatches.index(before: searchMatches.endIndex)
            : selectedIndex - 1
        selectedSearchMatchID = searchMatches[previousIndex].id
    }

    func selectNextSearchMatch() {
        guard !searchMatches.isEmpty else {
            selectedSearchMatchID = nil
            return
        }
        let selectedIndex =
            selectedSearchMatchIndex ?? searchMatches.index(before: searchMatches.endIndex)
        let nextIndex = searchMatches.index(after: selectedIndex)
        selectedSearchMatchID = searchMatches[nextIndex == searchMatches.endIndex ? 0 : nextIndex].id
    }

    func speakerChipInfo(for turn: TranscriptTurn) -> TranscriptSpeakerChip? {
        guard let speakerID = turn.speakerID,
              let index = transcript.speakers.firstIndex(where: { $0.id == speakerID })
        else {
            return nil
        }
        return TranscriptSpeakerChip(
            displayName: transcript.speakers[index].displayName,
            dotColor: TranscriptSpeakerPalette.dotColor(for: transcript.speakers[index].displayName),
            textColor: TranscriptSpeakerPalette.textColor(for: transcript.speakers[index].displayName)
        )
    }

    func copyTranscript(
        _ transcript: TurnSegmentedTranscript,
        words: [TranscriptEditableWord]
    ) {
        let text = TranscriptCopyTextBuilder().text(
            transcript: transcript,
            visibleWords: words,
            hasCuts: !cutReviewItems.isEmpty
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
