import AVFoundation
import AppKit
import LuxelCore
import SwiftUI

struct RecentRecordingThumbnail: View {
    private static let size = CGSize(width: 60, height: 38)

    @State private var thumbnail: NSImage?

    let recording: PastRecording

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            thumbnailContent

            Image(systemName: badgeSystemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(.black.opacity(0.56), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(.white.opacity(0.14), lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .padding(4)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .task(id: thumbnailRequest) {
            await loadThumbnail()
        }
        .accessibilityLabel("Recent recording preview")
    }

    @ViewBuilder
    private var thumbnailContent: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .scaledToFill()
                .frame(width: Self.size.width, height: Self.size.height)
                .clipped()
        } else {
            ZStack {
                Rectangle()
                    .fill(.white.opacity(0.08))

                Image(systemName: placeholderSystemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var thumbnailRequest: RecentRecordingThumbnailRequest {
        RecentRecordingThumbnailRequest(
            fileURL: thumbnailURL,
            isAudioOnly: recording.options.isAudioOnly
        )
    }

    private var thumbnailURL: URL {
        recording.latestExport?.fileURL ?? recording.primaryMediaURL
    }

    private var placeholderSystemImage: String {
        recording.options.isAudioOnly ? "waveform" : "film"
    }

    private var badgeSystemImage: String {
        recording.options.isAudioOnly ? "waveform" : "film"
    }

    @MainActor
    private func loadThumbnail() async {
        thumbnail = await Self.thumbnail(for: thumbnailRequest)
    }

    @MainActor
    private static func thumbnail(for request: RecentRecordingThumbnailRequest) async -> NSImage? {
        guard !request.isAudioOnly else {
            return nil
        }

        if request.fileURL.isImageLikeMedia {
            return NSImage(contentsOf: request.fileURL)
        }

        return await videoThumbnail(for: request.fileURL)
    }

    @MainActor
    private static func videoThumbnail(for fileURL: URL) async -> NSImage? {
        let asset = AVURLAsset(url: fileURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: size.width * 2, height: size.height * 2)

        for time in [
            CMTime(seconds: 0.2, preferredTimescale: 600),
            .zero
        ] {
            if let image = try? await generator.image(at: time).image {
                return NSImage(cgImage: image, size: .zero)
            }
        }

        return nil
    }
}

private struct RecentRecordingThumbnailRequest: Equatable {
    let fileURL: URL
    let isAudioOnly: Bool
}

struct RecentRecordingMetadataLabel: View {
    @State private var durationText: String?

    let recording: PastRecording

    var body: some View {
        Text(metadataText)
            .task(id: mediaURL) {
                durationText = nil
                durationText = await Self.durationText(for: mediaURL)
            }
    }

    private var metadataText: String {
        let components = [
            durationText,
            fileSizeText,
            formatText
        ].compactMap { text -> String? in
            guard let text, !text.isEmpty else {
                return nil
            }

            return text
        }

        if !components.isEmpty {
            return components.joined(separator: " · ")
        }

        return recording.date.formatted(date: .abbreviated, time: .shortened)
    }

    private var mediaURL: URL {
        recording.latestExport?.fileURL ?? recording.primaryMediaURL
    }

    private var fileSizeText: String? {
        if let fileSizeBytes = recording.latestExport?.fileSizeBytes {
            return ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
        }

        guard let fileSizeBytes = try? mediaURL.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return nil
        }

        return ByteCountFormatter.string(fromByteCount: Int64(fileSizeBytes), countStyle: .file)
    }

    private var formatText: String? {
        if let exportFormat = recording.latestExport?.format.prettyName {
            return exportFormat
        }

        let fileExtension = mediaURL.pathExtension
        guard !fileExtension.isEmpty else {
            return nil
        }

        return fileExtension.uppercased()
    }

    private static func durationText(for fileURL: URL) async -> String? {
        let asset = AVURLAsset(url: fileURL)

        do {
            let duration = try await asset.load(.duration)
            let seconds = duration.seconds
            guard seconds.isFinite, seconds > 0 else {
                return nil
            }

            return RecordingDurationFormatter.elapsedTime(
                seconds,
                padsMinutesWhenNoHours: true
            )
        } catch {
            return nil
        }
    }

}
