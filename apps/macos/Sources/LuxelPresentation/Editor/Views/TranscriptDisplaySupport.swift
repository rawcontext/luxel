import LuxelCore
import SwiftUI

struct TranscriptDisplayPlan {
    let chunks: [TranscriptDisplayChunk]

    private let chunkIDBySpanID: [String: String]
    private let searchTurns: [TranscriptSearchTurn]

    init(
        transcript: TurnSegmentedTranscript,
        sentences: [TranscriptEditableSentence],
        sentencesPerChunk: Int
    ) {
        let spansByID = Dictionary(uniqueKeysWithValues: transcript.spans.map { ($0.id, $0) })
        let visibleSpanIDs = Set(sentences.flatMap(\.spanIDs))
        let maxSentenceCount = max(1, sentencesPerChunk)
        var chunks: [TranscriptDisplayChunk] = []
        var chunkIDBySpanID: [String: String] = [:]
        var searchTurns: [TranscriptSearchTurn] = []

        for turn in transcript.turns {
            let turnSentences = sentences.filter { $0.turnID == turn.id }
            guard !turnSentences.isEmpty else {
                continue
            }
            let spans = turn.spanIDs.compactMap { spansByID[$0] }.filter {
                visibleSpanIDs.contains($0.id)
            }
            searchTurns.append(TranscriptSearchTurn(turn: turn, spans: spans))
            var chunkIndex = 0
            var startIndex = turnSentences.startIndex

            while startIndex < turnSentences.endIndex {
                let endIndex =
                    turnSentences.index(
                        startIndex,
                        offsetBy: maxSentenceCount,
                        limitedBy: turnSentences.endIndex
                    ) ?? turnSentences.endIndex
                let chunkSentences = Array(turnSentences[startIndex..<endIndex])
                let chunkID = chunkIndex == 0 ? turn.id : "\(turn.id)-chunk-\(chunkIndex)"

                chunks.append(
                    TranscriptDisplayChunk(
                        id: chunkID,
                        turn: turn,
                        sentences: chunkSentences,
                        showsHeader: chunkIndex == 0
                    ))
                for sentence in chunkSentences {
                    for spanID in sentence.spanIDs {
                        chunkIDBySpanID[spanID] = chunkID
                    }
                }

                chunkIndex += 1
                startIndex = endIndex
            }
        }

        self.chunks = chunks
        self.chunkIDBySpanID = chunkIDBySpanID
        self.searchTurns = searchTurns
    }

    func scrollTargetID(activeSpanID: String?, activeTurnID: String?) -> String? {
        if let activeSpanID, let chunkID = chunkIDBySpanID[activeSpanID] {
            return chunkID
        }

        return activeTurnID
    }

    func searchMatches(for query: String) -> [TranscriptSearchMatch] {
        let normalizedQuery = normalizeSearchText(query)
        guard !normalizedQuery.isEmpty else {
            return []
        }

        var matches: [TranscriptSearchMatch] = []

        for searchTurn in searchTurns {
            let searchableTurn = SearchableTranscriptTurn(spans: searchTurn.spans)
            var searchRange = searchableTurn.text.startIndex..<searchableTurn.text.endIndex
            var matchIndex = 0

            while let range = searchableTurn.text.range(of: normalizedQuery, range: searchRange) {
                let spanIDs = searchableTurn.spanIDs(overlapping: range)
                if let targetSpanID = spanIDs.first,
                   let chunkID = chunkIDBySpanID[targetSpanID] {
                    matches.append(
                        TranscriptSearchMatch(
                            id: "\(searchTurn.turn.id)-match-\(matchIndex)",
                            chunkID: chunkID,
                            spanIDs: Set(spanIDs)
                        ))
                }

                matchIndex += 1
                searchRange = range.upperBound..<searchableTurn.text.endIndex
            }
        }

        return matches
    }
}

struct TranscriptDisplayChunk: Identifiable {
    let id: String
    let turn: TranscriptTurn
    let sentences: [TranscriptEditableSentence]
    let showsHeader: Bool
}

private struct TranscriptSearchTurn {
    let turn: TranscriptTurn
    let spans: [TimedTranscriptSpan]
}

struct TranscriptSearchMatch: Identifiable, Equatable {
    let id: String
    let chunkID: String
    let spanIDs: Set<String>
}

private struct SearchableTranscriptTurn {
    struct SpanRange {
        let spanID: String
        let range: Range<String.Index>
    }

    let text: String
    let spanRanges: [SpanRange]

    init(spans: [TimedTranscriptSpan]) {
        var text = ""
        var spanRanges: [SpanRange] = []

        for span in spans {
            if !text.isEmpty {
                text.append(" ")
            }

            let start = text.endIndex
            text.append(normalizeSearchText(span.text))
            let end = text.endIndex
            spanRanges.append(SpanRange(spanID: span.id, range: start..<end))
        }

        self.text = text
        self.spanRanges = spanRanges
    }

    func spanIDs(overlapping range: Range<String.Index>) -> [String] {
        spanRanges.compactMap { spanRange in
            rangesOverlap(spanRange.range, range) ? spanRange.spanID : nil
        }
    }
}

struct TranscriptChunkView: View {
    let chunk: TranscriptDisplayChunk
    let speakerChip: TranscriptSpeakerChip?
    let isActiveTurn: Bool
    let activeSpanID: String?
    let selectedSentenceID: TranscriptEditableSentence.ID?
    let matchedSearchSpanIDs: Set<String>
    let currentSearchSpanIDs: Set<String>
    let selectSentence: (TranscriptEditableSentence) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: chunk.showsHeader ? 6 : 0) {
            if chunk.showsHeader {
                HStack(spacing: 6) {
                    if let speakerChip {
                        Text(formatTranscriptTime(chunk.turn.start))
                            .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.4))

                        HStack(spacing: 5) {
                            Circle()
                                .fill(speakerChip.dotColor)
                                .frame(width: 6, height: 6)

                            Text(speakerChip.displayName)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(speakerChip.textColor)
                        }
                        .padding(.leading, 7)
                        .padding(.trailing, 9)
                        .padding(.vertical, 2)
                        .background(
                            speakerChip.dotColor.opacity(0.14),
                            in: RoundedRectangle(cornerRadius: 10)
                        )

                        if let source = chunk.turn.source {
                            Text(source.displayName)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.55))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(
                                    .white.opacity(0.07),
                                    in: RoundedRectangle(cornerRadius: 10)
                                )
                        }
                    } else {
                        if let source = chunk.turn.source {
                            Text(source.displayName)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.55))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    .white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                        }

                        Text(formatTranscriptTime(chunk.turn.start))
                            .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }

            TranscriptSpanFlowLayout(horizontalSpacing: 4, verticalSpacing: 7) {
                ForEach(chunk.sentences) { sentence in
                    TranscriptSentenceButton(
                        sentence: sentence,
                        isActiveTurn: isActiveTurn,
                        isActiveSpan: sentence.spanIDs.contains(activeSpanID ?? ""),
                        isSelected: sentence.id == selectedSentenceID,
                        isSearchMatch: !matchedSearchSpanIDs.isDisjoint(with: sentence.spanIDs),
                        isCurrentSearchMatch: !currentSearchSpanIDs.isDisjoint(with: sentence.spanIDs),
                        selectSentence: selectSentence
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.top, chunk.showsHeader ? 10 : 2)
        .padding(.bottom, 6)
    }
}

private struct TranscriptSentenceButton: View {
    let sentence: TranscriptEditableSentence
    let isActiveTurn: Bool
    let isActiveSpan: Bool
    let isSelected: Bool
    let isSearchMatch: Bool
    let isCurrentSearchMatch: Bool
    let selectSentence: (TranscriptEditableSentence) -> Void

    var body: some View {
        Button {
            selectSentence(sentence)
        } label: {
            Text(sentence.text)
                .font(.system(size: 13))
                .foregroundStyle(
                    isActiveSpan || isActiveTurn || isSearchMatch
                        ? Color.white : Color.white.opacity(0.75)
                )
                .underline(isActiveSpan, color: .white.opacity(0.75))
                .padding(.horizontal, 2)
                .padding(.vertical, 1)
                .background(
                    spanBackground,
                    in: RoundedRectangle(cornerRadius: 4)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(
            LuxelLocalization.format(
                "transcript.jumpToTime.help",
                defaultValue: "Jump to %@",
                formatTranscriptTime(sentence.sourceRange.start))
        )
    }

    private var spanBackground: Color {
        if isCurrentSearchMatch {
            return .white.opacity(0.3)
        }

        if isSelected {
            return .blue.opacity(0.4)
        }

        if isSearchMatch {
            return .white.opacity(0.18)
        }

        if isActiveSpan {
            return .white.opacity(0.14)
        }

        return .clear
    }
}

private struct TranscriptSpanFlowLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentRowWidth: CGFloat = 0
        var currentRowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var widestRow: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let proposedRowWidth =
                currentRowWidth == 0 ? size.width : currentRowWidth + horizontalSpacing + size.width

            if currentRowWidth > 0, proposedRowWidth > maxWidth {
                widestRow = max(widestRow, currentRowWidth)
                totalHeight += currentRowHeight + verticalSpacing
                currentRowWidth = size.width
                currentRowHeight = size.height
            } else {
                currentRowWidth = proposedRowWidth
                currentRowHeight = max(currentRowHeight, size.height)
            }
        }

        widestRow = max(widestRow, currentRowWidth)
        totalHeight += currentRowHeight

        return CGSize(width: proposal.width ?? widestRow, height: totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var currentRowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > bounds.minX, currentX + size.width > bounds.maxX {
                currentX = bounds.minX
                currentY += currentRowHeight + verticalSpacing
                currentRowHeight = 0
            }

            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            currentX += size.width + horizontalSpacing
            currentRowHeight = max(currentRowHeight, size.height)
        }
    }
}

private func formatTranscriptTime(_ time: TimeInterval) -> String {
    let totalSeconds = max(0, Int(time.rounded(.down)))
    return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
}

private func normalizeSearchText(_ text: String) -> String {
    text
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .lowercased()
}

private func rangesOverlap(_ lhs: Range<String.Index>, _ rhs: Range<String.Index>) -> Bool {
    lhs.lowerBound < rhs.upperBound && rhs.lowerBound < lhs.upperBound
}
