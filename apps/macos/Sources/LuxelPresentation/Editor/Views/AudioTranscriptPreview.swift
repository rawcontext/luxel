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
        VStack {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)

                Text("Transcribing audio...")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
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
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Transcribing audio")
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
            }
            .padding(.top, 14)
            .padding(.trailing, 16)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(true)
    }

    private func transcriptCard(_ transcript: TurnSegmentedTranscript) -> some View {
        VStack(spacing: 0) {
            transcriptToolbar(transcript)

            Divider()
                .opacity(0.45)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(transcript.turns) { turn in
                            turnView(turn, transcript: transcript)
                                .id(turn.id)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .scrollIndicators(.never)
                .onChange(of: model.activeTranscriptTurnID) { _, activeTurnID in
                    guard let activeTurnID else {
                        return
                    }

                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(activeTurnID, anchor: .center)
                    }
                }
            }
        }
        .frame(maxWidth: Layout.transcriptCardMaxWidth)
        .frame(height: Layout.transcriptCardHeight)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
    }

    private func transcriptToolbar(_ transcript: TurnSegmentedTranscript) -> some View {
        HStack {
            Text("Transcript")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

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
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
    }

    private func turnView(
        _ turn: TranscriptTurn,
        transcript: TurnSegmentedTranscript
    ) -> some View {
        let isActive = turn.id == model.activeTranscriptTurnID

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let source = turn.source {
                    Text(source.displayName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                }

                Text(formatTranscriptTime(turn.start))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            transcriptSpanFlow(for: turn, transcript: transcript)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            isActive ? Color.accentColor.opacity(0.16) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
    }

    private func transcriptSpanFlow(
        for turn: TranscriptTurn,
        transcript: TurnSegmentedTranscript
    ) -> some View {
        let spans = transcript.spans(for: turn)
        let isActiveTurn = turn.id == model.activeTranscriptTurnID

        return TranscriptSpanFlowLayout(horizontalSpacing: 4, verticalSpacing: 5) {
            ForEach(spans) { span in
                spanText(span, isActiveTurn: isActiveTurn)
            }
        }
    }

    private func spanText(
        _ span: TimedTranscriptSpan,
        isActiveTurn: Bool
    ) -> some View {
        let isActiveSpan = span.id == model.activeTranscriptSpanID

        return Button {
            model.seekToTranscriptSpan(span)
        } label: {
            Text(span.text)
                .font(.callout)
                .foregroundStyle(isActiveSpan || isActiveTurn ? .primary : .secondary)
                .underline(isActiveSpan, color: .primary.opacity(0.75))
                .padding(.horizontal, 2)
                .padding(.vertical, 1)
                .background(
                    isActiveSpan ? Color.accentColor.opacity(0.18) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 3)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help("Jump to \(formatTranscriptTime(span.start))")
    }

    private func copyTranscript(_ transcript: TurnSegmentedTranscript) {
        let text = transcript.turns.map(\.text).joined(separator: "\n\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func formatTranscriptTime(_ time: TimeInterval) -> String {
        let totalSeconds = max(0, Int(time.rounded(.down)))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
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
