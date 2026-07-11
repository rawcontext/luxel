import AppKit
import LuxelCore

extension TranscriptCardContent {
    var selectedSearchMatchIndex: Int? {
        guard let selectedSearchMatchID else {
            return nil
        }
        return searchMatches.firstIndex { $0.id == selectedSearchMatchID }
    }

    func rebuildDisplayPlan(
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
        sentences: [TranscriptEditableSentence]
    ) {
        let text = TranscriptCopyTextBuilder().text(
            transcript: transcript,
            visibleSentences: sentences,
            hasCuts: cutCount > 0
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
