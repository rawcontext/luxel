import AppKit
import LuxelCore
import SwiftUI

public struct LuxelEditorView: View {
    @Bindable var model: LuxelEditorModel
    @State var editableFileName = ""
    @State var isEditingFileName = false
    @FocusState var isFileNameFocused: Bool

    public init(model: LuxelEditorModel) {
        self.model = model
    }
}

extension LuxelEditorView {
    public var body: some View {
        HStack(spacing: 12) {
            preview

            controls
                .frame(width: 280)
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .frame(minWidth: 900, minHeight: 560)
        .tint(.white)
        .preferredColorScheme(.dark)
        .navigationTitle(model.source?.fileURL.lastPathComponent ?? "Luxel")
        .background {
            LuxelGlassWindowBackground()
                .overlay(LuxelGlassWindowChromeConfigurator())
        }
        .onDisappear {
            model.pausePlayback()
        }
    }

    @ViewBuilder
    private var preview: some View {
        if model.hasAudioOnlySource {
            audioStage
        } else {
            videoStage
        }
    }

    private var audioStage: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                recordingNavigationButtons

                Spacer(minLength: 0)
            }

            AudioTranscriptPreview(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    if !showsTranscriptContent {
                        ContentUnavailableView("Audio Recording", systemImage: "waveform")
                            .foregroundStyle(.secondary)
                            .allowsHitTesting(false)
                    }

                    if case .loading = model.status {
                        ProgressView()
                            .controlSize(.large)
                    }
                }

            if model.hasSource {
                EditorPlaybackCapsule(model: model)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(minWidth: 540, maxWidth: .infinity, maxHeight: .infinity)
    }

    private var videoStage: some View {
        // Mirrors audioStage: navigation lives in a row above the stage so the
        // arrows do not move when flipping between audio and video recordings.
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                recordingNavigationButtons

                Spacer(minLength: 0)

                transcriptPreviewControls
            }

            ScrollView {
                VStack(spacing: 10) {
                    if showsTranscriptContent {
                        AudioTranscriptPreview(model: model)
                    }

                    videoFrame
                        .containerRelativeFrame(.vertical)
                }
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .frame(minWidth: 540, maxWidth: .infinity, maxHeight: .infinity)
    }

    private var videoFrame: some View {
        ZStack {
            if model.usesAlphaPreviewBackground {
                CheckerboardBackground()
            } else {
                Rectangle()
                    .fill(.black)
            }

            if model.hasVideoSource {
                LuxelPlayerView(
                    player: model.player,
                    usesAlphaBackground: model.usesAlphaPreviewBackground
                )
                .background(model.usesAlphaPreviewBackground ? .clear : .black)
            } else {
                ContentUnavailableView("No Recording", systemImage: "film")
                    .foregroundStyle(.secondary)
            }

            if case .loading = model.status {
                ProgressView()
                    .controlSize(.large)
            }
            if let options = model.keystrokeOptions,
               options.isVisible,
               !model.activeKeystrokeChips.isEmpty {
                KeystrokeChipStackView(chips: model.activeKeystrokeChips, options: options)
                    .padding(28)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: keystrokePreviewAlignment(options.anchor)
                    )
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
        .overlay(alignment: .bottom) {
            if model.hasSource {
                EditorPlaybackCapsule(model: model)
                    .padding(.horizontal, 48)
                    .padding(.bottom, 14)
            }
        }
        .contextMenu {
            Button("Copy Frame") {
                model.copyCurrentFrame()
            }
            .disabled(!model.canGrabFrame)

            Button("Save Frame As...") {
                model.saveCurrentFrameAs()
            }
            .disabled(!model.canGrabFrame)
        }
    }

    private var showsTranscriptContent: Bool {
        model.shouldShowSpeechRecognitionPrompt
            || model.shouldShowTranscriptProgress
            || model.shouldShowTranscriptFailure
            || model.visibleTranscript != nil
    }

    private var recordingNavigationButtons: some View {
        HStack(spacing: 6) {
            recordingNavigationButton(
                title: "Back",
                systemImage: "chevron.left",
                isEnabled: model.canNavigateToNewerRecording
            ) {
                await model.navigateToNewerRecording()
            }
            .help("Open newer recording")

            recordingNavigationButton(
                title: "Forward",
                systemImage: "chevron.right",
                isEnabled: model.canNavigateToOlderRecording
            ) {
                await model.navigateToOlderRecording()
            }
            .help("Open older recording")
        }
    }

    @ViewBuilder
    private var transcriptPreviewControls: some View {
        if model.canShowVideoTranscriptToggle {
            Button {
                model.toggleTranscriptPanel()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 11, weight: .medium))

                    Text(transcriptPreviewButtonTitle)
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    Capsule(style: .continuous)
                        .fill(EditorStageChromeStyle.fill)
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                        }
                }
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .help(transcriptPreviewButtonHelp)
        }
    }

    private var transcriptPreviewButtonTitle: String {
        if model.isTranscriptExtractionActive {
            return "Transcribing"
        }

        return "Transcript"
    }

    private var transcriptPreviewButtonHelp: String {
        model.isTranscriptPanelVisible ? "Hide transcript" : "Show transcript"
    }

    private func recordingNavigationButton(
        title: String,
        systemImage: String,
        isEnabled: Bool,
        action: @escaping @MainActor () async -> Void
    ) -> some View {
        Button {
            Task {
                await action()
            }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(isEnabled ? 0.8 : 0.3))
                .frame(width: 32, height: 32)
                .background {
                    Circle()
                        .fill(EditorStageChromeStyle.fill)
                        .overlay {
                            Circle()
                                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                        }
                }
                .contentShape(Circle())
                .accessibilityLabel(title)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                header
                exportControls
                if model.showsExportProgressPanel {
                    exportProgressPanel
                }
                timelineControls
                if model.keystrokeTimeline != nil {
                    keystrokeControls
                }
                outputControls
                if let sidebarStatusMessage = model.sidebarStatusMessage {
                    statusControls(sidebarStatusMessage)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }

    private func keystrokePreviewAlignment(_ anchor: KeystrokeOverlayAnchor) -> Alignment {
        switch anchor {
        case .topLeft:
            .topLeading
        case .topCenter:
            .top
        case .topRight:
            .topTrailing
        case .bottomLeft:
            .bottomLeading
        case .bottomCenter:
            .bottom
        case .bottomRight:
            .bottomTrailing
        }
    }

}
