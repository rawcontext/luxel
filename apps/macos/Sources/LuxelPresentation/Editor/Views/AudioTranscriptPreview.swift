import AppKit
import LuxelCore
import SwiftUI

struct AudioTranscriptPreview: View {
    private enum Layout {
        static let transcriptSpansPerChunk = 32
    }

    @Bindable var model: LuxelEditorModel

    var body: some View {
        transcriptColumn
    }

    private var transcriptColumn: some View {
        VStack(spacing: 10) {
            if model.shouldShowSpeechRecognitionPrompt {
                HStack {
                    Spacer()

                    Button {
                        model.enableSpeechRecognition()
                    } label: {
                        Label("Enable Speech Recognition", systemImage: "waveform")
                    }
                    .buttonStyle(LuxelGlassPillButtonStyle(isProminent: true))
                    .fixedSize()
                    .help("Turn speech recognition on for this recording.")

                    if model.canCloseTranscriptPanel {
                        closeTranscriptButton
                    }

                    Spacer()
                }
            } else if model.shouldShowTranscriptProgress {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    transcriptProgressRow(at: timeline.date)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(transcriptProgressTitle(at: timeline.date))
                }
            } else if model.shouldShowTranscriptFailure {
                transcriptFailureRow
            }

            if let transcript = model.visibleTranscript {
                transcriptCard(transcript)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func transcriptProgressRow(at date: Date) -> some View {
        LuxelGlassIsland(cornerRadius: 18) {
            HStack(spacing: 10) {
                Image(systemName: "clock")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))

                Text(transcriptProgressTitle(at: date))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)

                TranscriptProgressBar()
                    .frame(maxWidth: .infinity)

                if model.canCloseTranscriptPanel {
                    closeTranscriptButton
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
    }

    private var transcriptFailureRow: some View {
        LuxelGlassIsland(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Transcription unavailable", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 13, weight: .semibold))
                Text(model.transcriptFailureMessage ?? "Transcription failed.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
                Button("Retry") {
                    model.refreshTranscriptionConfiguration()
                }
                .buttonStyle(LuxelGlassPillButtonStyle())
                .fixedSize()
                .help("Try generating the transcript again.")
            }
            .padding(14)
        }
    }

    private func transcriptCard(_ transcript: TurnSegmentedTranscript) -> some View {
        let activeTurnID = model.activeTranscriptTurnID
        let activeSpanID = model.activeTranscriptSpanID

        let content = TranscriptCardContent(
            transcript: transcript,
            words: model.visibleTranscriptWords,
            displayRevision: model.transcriptDisplayRevision,
            activeTurnID: activeTurnID,
            activeSpanID: activeSpanID,
            spansPerChunk: Layout.transcriptSpansPerChunk,
            isCompact: !model.hasAudioOnlySource,
            selectedWordIDs: model.selectedTranscriptWordIDs,
            cutReviewItems: model.transcriptCutReviewItems,
            editStatusMessage: model.transcriptEditStatusMessage,
            canDeleteSelectedWord: model.canDeleteSelectedTranscriptWord,
            canUndoLastCut: model.canUndoLastTranscriptCut,
            canClose: model.canCloseTranscriptPanel,
            closeTranscript: {
                model.hideTranscriptPanel()
            },
            selectWord: { word, extendingSelection in
                model.selectTranscriptWord(
                    word,
                    extendingSelection: extendingSelection
                )
            },
            deleteSelectedWord: {
                model.deleteSelectedTranscriptWord()
            },
            undoLastCut: {
                model.undoLastTranscriptCut()
            },
            restoreCut: { cutID in
                model.restoreTranscriptCut(id: cutID)
            }
        )

        return LuxelGlassIsland(cornerRadius: 18) {
            content
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var closeTranscriptButton: some View {
        Button {
            model.hideTranscriptPanel()
        } label: {
            Image(systemName: "xmark")
        }
        .buttonStyle(LuxelGlassCircleButtonStyle())
        .help("Close transcript")
        .accessibilityLabel("Close transcript")
    }

    private func transcriptProgressTitle(at date: Date) -> String {
        if model.isSpeakerModelPreparing {
            return "Preparing speaker model..."
        }

        guard let elapsed = model.transcriptExtractionElapsedTime(at: date) else {
            return "Preparing transcript..."
        }

        return "Transcribing audio... \(elapsed)"
    }
}

private struct TranscriptProgressBar: View {
    @State private var isAnimating = false

    var body: some View {
        GeometryReader { proxy in
            Capsule(style: .continuous)
                .fill(.white.opacity(0.8))
                .frame(width: proxy.size.width * 0.35)
                .offset(x: isAnimating ? proxy.size.width * 0.65 : 0)
        }
        .frame(height: 3)
        .background(.white.opacity(0.12), in: Capsule(style: .continuous))
        .clipShape(Capsule(style: .continuous))
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}
