import AppKit
import LuxelCore
import SwiftUI

extension TranscriptCardContent {
    func markdownTimestampToggle(side: CGFloat) -> some View {
        Toggle(isOn: $includesMarkdownTimestamps) {
            Image(systemName: includesMarkdownTimestamps ? "clock.fill" : "clock")
        }
        .toggleStyle(.button)
        .buttonStyle(LuxelGlassCircleButtonStyle(side: side))
        .help("Show a timestamp before each turn in copied Markdown transcripts.")
        .accessibilityLabel("Include Timestamps in Markdown")
    }

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

            Text("\(transcript.speakers.count)")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.white.opacity(0.07), in: Capsule(style: .continuous))
        .help("Speaker count")
        .accessibilityLabel(
            transcript.speakers.count == 1
                ? LuxelLocalization.string("1 speaker detected")
                : LuxelLocalization.format("%d speakers detected", transcript.speakers.count))
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
        let previousIndex =
            selectedIndex == 0
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
        let metadata =
            markdownMetadata
            ?? TranscriptMarkdownMetadata(
                title: "Transcript",
                sourceFileName: nil,
                recordedAt: nil,
                duration: transcript.turns.last?.end ?? 0
            )
        let text = TranscriptCopyTextBuilder().text(
            transcript: transcript,
            visibleWords: words,
            hasCuts: !cutReviewItems.isEmpty,
            metadata: metadata,
            includesTimestamps: includesMarkdownTimestamps
        )
        let item = NSPasteboardItem()
        item.setString(
            text,
            forType: NSPasteboard.PasteboardType("net.daringfireball.markdown")
        )
        item.setString(text, forType: .string)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }
}
