import LuxelCore
import SwiftUI

extension LuxelEditorView {
    var keystrokesVisibleSelection: Binding<Bool> {
        Binding {
            model.keystrokeOptions?.isVisible ?? false
        } set: {
            model.updateKeystrokeOptions(isVisible: $0)
        }
    }

    var keystrokeAnchorSelection: Binding<KeystrokeOverlayAnchor> {
        Binding {
            model.keystrokeOptions?.anchor ?? .bottomCenter
        } set: {
            model.updateKeystrokeOptions(anchor: $0)
        }
    }

    var keystrokeSizeSelection: Binding<KeystrokeOverlaySize> {
        Binding {
            model.keystrokeOptions?.size ?? .medium
        } set: {
            model.updateKeystrokeOptions(size: $0)
        }
    }

    var keystrokeThemeSelection: Binding<KeystrokeOverlayTheme> {
        Binding {
            model.keystrokeOptions?.theme ?? .darkGlass
        } set: {
            model.updateKeystrokeOptions(theme: $0)
        }
    }

    var keystrokeDurationSelection: Binding<Double> {
        Binding {
            model.keystrokeOptions?.displayDuration ?? 1.5
        } set: {
            model.updateKeystrokeOptions(displayDuration: $0)
        }
    }

    func formatSelectionBinding(_ format: ExportFormat) -> Binding<Bool> {
        Binding {
            model.selectedFormats.contains(format)
        } set: { isSelected in
            model.setFormatSelection(format, isSelected: isSelected)
        }
    }

    var includeAudioSelection: Binding<Bool> {
        Binding {
            model.includesAudio
        } set: { includesAudio in
            model.setIncludesAudio(includesAudio)
        }
    }

    var audioVolumeSelection: Binding<Double> {
        Binding {
            model.audioVolume
        } set: { volume in
            model.setAudioVolume(volume)
        }
    }

    var normalizeAudioSelection: Binding<Bool> {
        Binding {
            model.normalizeAudio
        } set: { normalizeAudio in
            model.setNormalizeAudio(normalizeAudio)
        }
    }

    var studioVoiceSelection: Binding<Bool> {
        Binding {
            model.studioVoiceEnabled
        } set: { enabled in
            model.setStudioVoiceEnabled(enabled)
        }
    }

    var qualitySelection: Binding<ExportQuality> {
        Binding {
            model.quality
        } set: { quality in
            model.setQuality(quality)
        }
    }

    var gifLoopModeSelection: Binding<EditorGIFLoopModeKind> {
        Binding {
            model.gifLoopModeKind
        } set: { kind in
            model.setGIFLoopModeKind(kind)
        }
    }

    var gifLoopCountSelection: Binding<Int> {
        Binding {
            model.gifLoopCount
        } set: { count in
            model.setGIFLoopCount(count)
        }
    }

    var gifDitheringSelection: Binding<GIFDitheringMode> {
        Binding {
            model.gifDithering
        } set: { mode in
            model.setGIFDithering(mode)
        }
    }

    var trimStartSelection: Binding<Double> {
        Binding {
            model.trimStart
        } set: { value in
            model.setTrimStart(value)
        }
    }

    var trimEndSelection: Binding<Double> {
        Binding {
            model.trimEnd
        } set: { value in
            model.setTrimEnd(value)
        }
    }

    var sizePresetSelection: Binding<EditorSizePreset?> {
        Binding {
            model.sizePreset
        } set: { preset in
            model.setSizePreset(preset)
        }
    }

    var outputWidthSelection: Binding<Int> {
        Binding {
            model.outputWidth
        } set: { value in
            model.setOutputWidth(value)
        }
    }

    var outputHeightSelection: Binding<Int> {
        Binding {
            model.outputHeight
        } set: { value in
            model.setOutputHeight(value)
        }
    }

    var frameRateSelection: Binding<Int> {
        Binding {
            model.frameRate
        } set: { value in
            model.setFrameRate(value)
        }
    }

    var playbackSpeedSelection: Binding<Double> {
        Binding {
            model.playbackSpeedValue
        } set: { value in
            model.setPlaybackSpeed(value)
        }
    }

    var shouldCropSelection: Binding<Bool> {
        Binding {
            model.shouldCrop
        } set: { shouldCrop in
            model.setShouldCrop(shouldCrop)
        }
    }

    func gifDitheringLabel(_ mode: GIFDitheringMode) -> String {
        switch mode {
        case .auto:
            "Auto"
        case .none:
            "None"
        case .ordered:
            "Ordered"
        case .diffusion:
            "Diffusion"
        }
    }
}
