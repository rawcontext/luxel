import AppKit
import LuxelCore
import SwiftUI

struct AudioTranscriptPreview: View {
    private enum Layout {
        static let transcriptCardHeight: CGFloat = 300
        static let transcriptCardMaxWidth: CGFloat = 640
        static let transcriptHorizontalPadding: CGFloat = 24
        static let transcriptTopPadding: CGFloat = 86
        static let progressCardMaxWidth: CGFloat = 360
        static let transcriptSpansPerChunk = 32
    }

    @Bindable var model: LuxelEditorModel

    var body: some View {
        if model.shouldShowSpeechRecognitionPrompt {
            speechRecognitionPrompt
        } else if model.shouldShowTranscriptProgress {
            transcriptProgress
        } else if let transcript = model.visibleTranscript {
            VStack {
                transcriptCard(transcript)
                    .padding(.horizontal, Layout.transcriptHorizontalPadding)
                    .padding(.top, Layout.transcriptTopPadding)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(true)
        }
    }

    private var transcriptProgress: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            VStack {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)

                        Text(transcriptProgressTitle(at: timeline.date))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 0)

                        if model.canCloseTranscriptPanel {
                            closeTranscriptButton
                        }
                    }

                    ProgressView()
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .frame(maxWidth: Layout.progressCardMaxWidth)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }
                .padding(.horizontal, Layout.transcriptHorizontalPadding)
                .padding(.top, Layout.transcriptTopPadding)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(model.canCloseTranscriptPanel)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(transcriptProgressTitle(at: timeline.date))
        }
    }

    private var speechRecognitionPrompt: some View {
        VStack {
            HStack {
                Spacer()

                Button {
                    model.enableSpeechRecognition()
                } label: {
                    Label("Enable Speech Recognition", systemImage: "waveform")
                }
                .buttonStyle(.glassProminent)
                .controlSize(.regular)

                if model.canCloseTranscriptPanel {
                    closeTranscriptButton
                }
            }
            .padding(.top, 14)
            .padding(.trailing, 16)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(true)
    }

    private func transcriptCard(_ transcript: TurnSegmentedTranscript) -> some View {
        let activeTurnID = model.activeTranscriptTurnID
        let activeSpanID = model.activeTranscriptSpanID

        return TranscriptCardContent(
            transcript: transcript,
            activeTurnID: activeTurnID,
            activeSpanID: activeSpanID,
            spansPerChunk: Layout.transcriptSpansPerChunk,
            canClose: model.canCloseTranscriptPanel,
            closeTranscript: {
                model.hideTranscriptPanel()
            }
        ) { span in
            model.seekToTranscriptSpan(span)
        }
        .frame(maxWidth: Layout.transcriptCardMaxWidth)
        .frame(height: Layout.transcriptCardHeight)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
    }

    private var closeTranscriptButton: some View {
        Button {
            model.hideTranscriptPanel()
        } label: {
            Image(systemName: "xmark")
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Close transcript")
        .accessibilityLabel("Close transcript")
    }

    private func transcriptProgressTitle(at date: Date) -> String {
        guard let elapsed = model.transcriptExtractionElapsedTime(at: date) else {
            return "Preparing transcript..."
        }

        return "Transcribing audio... \(elapsed)"
    }
}

private struct TranscriptCardContent: View {
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

            Divider()
                .opacity(0.45)

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
        HStack(spacing: 10) {
            Text("Transcript")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

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
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Copy transcript")
            .accessibilityLabel("Copy transcript")

            if canClose {
                Button {
                    closeTranscript()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Close transcript")
                .accessibilityLabel("Close transcript")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
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

    private func copyTranscript(_ transcript: TurnSegmentedTranscript) {
        let text = transcript.turns.map(\.text).joined(separator: "\n\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct TranscriptSearchControl: View {
    @Binding var query: String

    let selectedMatchIndex: Int?
    let matchCount: Int
    let selectPrevious: () -> Void
    let selectNext: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            TextField("Search", text: $query)
                .textFieldStyle(.plain)
                .font(.caption.weight(.medium))
                .frame(width: 132)
                .padding(.horizontal, 8)
                .onSubmit {
                    selectNext()
                }

            Divider()
                .frame(height: 20)
                .opacity(0.5)

            Text(counterText)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(counterForegroundStyle)
                .frame(width: 42, alignment: .center)

            Button(action: selectPrevious) {
                Image(systemName: "chevron.up")
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(buttonForegroundStyle)
            .disabled(matchCount == 0)
            .help("Previous match")
            .accessibilityLabel("Previous transcript search match")

            Button(action: selectNext) {
                Image(systemName: "chevron.down")
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(buttonForegroundStyle)
            .disabled(matchCount == 0)
            .help("Next match")
            .accessibilityLabel("Next transcript search match")
        }
        .padding(.vertical, 2)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
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

        return .secondary
    }

    private var buttonForegroundStyle: Color {
        matchCount == 0 ? .secondary.opacity(0.45) : .secondary
    }
}

private struct TranscriptDisplayPlan {
    let chunks: [TranscriptDisplayChunk]

    private let chunkIDBySpanID: [String: String]
    private let searchTurns: [TranscriptSearchTurn]

    init(transcript: TurnSegmentedTranscript, spansPerChunk: Int) {
        let spansByID = Dictionary(uniqueKeysWithValues: transcript.spans.map { ($0.id, $0) })
        let maxSpanCount = max(1, spansPerChunk)
        var chunks: [TranscriptDisplayChunk] = []
        var chunkIDBySpanID: [String: String] = [:]
        var searchTurns: [TranscriptSearchTurn] = []

        for turn in transcript.turns {
            let spans = turn.spanIDs.compactMap { spansByID[$0] }
            searchTurns.append(TranscriptSearchTurn(turn: turn, spans: spans))
            var chunkIndex = 0
            var startIndex = spans.startIndex

            while startIndex < spans.endIndex {
                let endIndex =
                    spans.index(startIndex, offsetBy: maxSpanCount, limitedBy: spans.endIndex)
                    ?? spans.endIndex
                let chunkSpans = Array(spans[startIndex..<endIndex])
                let chunkID = chunkIndex == 0 ? turn.id : "\(turn.id)-chunk-\(chunkIndex)"

                chunks.append(
                    TranscriptDisplayChunk(
                        id: chunkID,
                        turn: turn,
                        spans: chunkSpans,
                        showsHeader: chunkIndex == 0
                    ))
                for span in chunkSpans {
                    chunkIDBySpanID[span.id] = chunkID
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

private struct TranscriptDisplayChunk: Identifiable {
    let id: String
    let turn: TranscriptTurn
    let spans: [TimedTranscriptSpan]
    let showsHeader: Bool
}

private struct TranscriptSearchTurn {
    let turn: TranscriptTurn
    let spans: [TimedTranscriptSpan]
}

private struct TranscriptSearchMatch: Identifiable, Equatable {
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

private struct TranscriptChunkView: View {
    let chunk: TranscriptDisplayChunk
    let isActiveTurn: Bool
    let activeSpanID: String?
    let matchedSearchSpanIDs: Set<String>
    let currentSearchSpanIDs: Set<String>
    let seekToSpan: (TimedTranscriptSpan) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: chunk.showsHeader ? 6 : 0) {
            if chunk.showsHeader {
                HStack(spacing: 6) {
                    if let source = chunk.turn.source {
                        Text(source.displayName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                    }

                    Text(formatTranscriptTime(chunk.turn.start))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }

            TranscriptSpanFlowLayout(horizontalSpacing: 4, verticalSpacing: 5) {
                ForEach(chunk.spans) { span in
                    TranscriptSpanButton(
                        span: span,
                        isActiveTurn: isActiveTurn,
                        isActiveSpan: span.id == activeSpanID,
                        isSearchMatch: matchedSearchSpanIDs.contains(span.id),
                        isCurrentSearchMatch: currentSearchSpanIDs.contains(span.id),
                        seekToSpan: seekToSpan
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.top, chunk.showsHeader ? 8 : 2)
        .padding(.bottom, 6)
        .background(
            isActiveTurn ? Color.accentColor.opacity(0.16) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
    }
}

private struct TranscriptSpanButton: View {
    let span: TimedTranscriptSpan
    let isActiveTurn: Bool
    let isActiveSpan: Bool
    let isSearchMatch: Bool
    let isCurrentSearchMatch: Bool
    let seekToSpan: (TimedTranscriptSpan) -> Void

    var body: some View {
        Button {
            seekToSpan(span)
        } label: {
            Text(span.text)
                .font(.callout)
                .foregroundStyle(
                    isActiveSpan || isActiveTurn || isSearchMatch ? .primary : .secondary
                )
                .underline(isActiveSpan, color: .primary.opacity(0.75))
                .padding(.horizontal, 2)
                .padding(.vertical, 1)
                .background(
                    spanBackground,
                    in: RoundedRectangle(cornerRadius: 3)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help("Jump to \(formatTranscriptTime(span.start))")
    }

    private var spanBackground: Color {
        if isCurrentSearchMatch {
            return .yellow.opacity(0.34)
        }

        if isSearchMatch {
            return .yellow.opacity(0.18)
        }

        if isActiveSpan {
            return Color.accentColor.opacity(0.18)
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
