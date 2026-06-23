import LuxelCore
import SwiftUI

struct AudioTranscriptPreview: View {
    @Bindable var model: LuxelEditorModel

    var body: some View {
        if let transcript = model.visibleTranscript {
            VStack {
                Spacer()

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(transcript.turns) { turn in
                                turnView(turn, transcript: transcript)
                                    .id(turn.id)
                            }
                        }
                        .padding(12)
                    }
                    .scrollIndicators(.never)
                    .frame(maxWidth: 640, maxHeight: 154)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.white.opacity(0.12), lineWidth: 1)
                    }
                    .textSelection(.enabled)
                    .onChange(of: model.activeTranscriptTurnID) { _, activeTurnID in
                        guard let activeTurnID else {
                            return
                        }

                        withAnimation(.easeOut(duration: 0.18)) {
                            proxy.scrollTo(activeTurnID, anchor: .center)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 126)
            }
            .allowsHitTesting(true)
        }
    }

    private func turnView(
        _ turn: TranscriptTurn,
        transcript: TurnSegmentedTranscript
    ) -> some View {
        let isActive = turn.id == model.activeTranscriptTurnID

        return VStack(alignment: .leading, spacing: 5) {
            if let source = turn.source {
                Text(source.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
            }

            transcriptText(for: turn, transcript: transcript)
                .font(.callout)
                .lineSpacing(2)
                .foregroundStyle(isActive ? .primary : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            isActive ? Color.accentColor.opacity(0.16) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            model.seekToTranscriptTurn(turn)
        }
    }

    private func transcriptText(
        for turn: TranscriptTurn,
        transcript: TurnSegmentedTranscript
    ) -> Text {
        var output = AttributedString()
        let spans = transcript.spans(for: turn)

        for (index, span) in spans.enumerated() {
            let prefix = index == 0 ? "" : " "
            var fragment = AttributedString(prefix + span.text)
            if span.id == model.activeTranscriptSpanID {
                fragment.inlinePresentationIntent = .stronglyEmphasized
                fragment.foregroundColor = .primary
            }
            output += fragment
        }

        return Text(output)
    }
}
