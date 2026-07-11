import AVKit
import Foundation
import LuxelCore

extension LuxelEditorModel {
    var exportProgressTitle: String {
        exportProgress?.actionTitle ?? statusMessage
    }

    var exportProgressValue: Double {
        exportProgress?.progress ?? 0
    }

    var exportEstimateTaskID: ExportEstimateTaskID? {
        guard let source else {
            return nil
        }

        return ExportEstimateTaskID(
            sourceFileURL: source.fileURL,
            formats: supportedFormats,
            trimStart: trimStart,
            trimEnd: trimEnd,
            transcriptCuts: transcriptEditPlan.cuts.map {
                ExportEstimateTaskID.TranscriptCut(
                    start: $0.sourceRange.start,
                    end: $0.sourceRange.end
                )
            },
            outputWidth: outputWidth,
            outputHeight: outputHeight,
            frameRate: frameRate,
            playbackSpeed: playbackSpeed.value,
            quality: quality,
            gifLoopModeKind: gifLoopModeKind,
            gifLoopCount: gifLoopCount,
            gifDithering: gifDithering,
            shouldMute: shouldMute,
            shouldCrop: shouldCrop
        )
    }

    var exportEstimateSummary: String? {
        exportEstimateSummary(for: format)
    }

    func exportEstimateSummary(for format: ExportFormat) -> String? {
        if estimatingExportSizeFormats.contains(format) {
            return "Estimating..."
        }

        guard let exportEstimate = exportEstimatesByFormat[format] else {
            return nil
        }

        let formatted = ByteCountFormatter.string(
            fromByteCount: exportEstimate.bytes, countStyle: .file)

        switch exportEstimate.confidence {
        case .exact:
            return formatted
        case .modeled, .sampled:
            return "~ \(formatted)"
        }
    }

    var exportedURL: URL? {
        if case .exported(let url) = status {
            return url
        }

        if case .exportedBatch(let urls) = status {
            return urls.first
        }

        if case .saved(let url) = status {
            return url
        }

        return nil
    }

    var exportedOpenURL: URL? {
        if case .exportedBatch(let urls) = status {
            return urls.first?.deletingLastPathComponent()
        }

        return exportedURL
    }

    var usesAlphaPreviewBackground: Bool {
        hasVideoSource && source?.hasAlpha == true
    }

    var sourceSummary: String {
        guard let source else {
            return "No recording loaded"
        }

        var parts = [
            source.fileURL.lastPathComponent,
            formatTime(source.duration)
        ]

        if source.hasVideo {
            parts.append("\(source.pixelSize.width)x\(source.pixelSize.height)")
            parts.append(source.hasAudio ? "audio" : "no audio")
        } else {
            parts.append("audio")
        }

        if source.hasVideo, source.hasAlpha {
            parts.append("alpha")
        }

        return parts.joined(separator: " | ")
    }

    var outputDirectorySummary: String {
        let name = outputDirectory.lastPathComponent
        return name.isEmpty ? outputDirectory.path : name
    }

    var statusMessage: String {
        switch status {
        case .empty:
            "No recording loaded"
        case .loading(let fileName):
            "Loading \(fileName)"
        case .ready:
            sourceSummary
        case .exporting:
            "Exporting \(selectedFormatSummary)"
        case .savingOriginal:
            "Saving original"
        case .copyingFrame:
            "Copying frame"
        case .savingFrame:
            "Saving frame"
        case .copiedFrame:
            "Copied frame"
        case .savedFrame(let url):
            "Saved \(url.lastPathComponent)"
        case .exported(let url):
            "Exported \(url.lastPathComponent)"
        case .exportedBatch(let urls):
            "Exported \(urls.count) files"
        case .saved(let url):
            "Saved \(url.lastPathComponent)"
        case .canceled:
            "Export canceled"
        case .discarded(let fileName):
            "Discarded \(fileName)"
        case .failed(let message):
            message
        }
    }

    var sidebarStatusMessage: String? {
        switch status {
        case .empty, .ready:
            nil
        default:
            statusMessage
        }
    }

}
