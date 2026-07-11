import Foundation
import SwiftUI

extension TranscriptCardContent {
    var editingGuidance: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "text.cursor")
                .foregroundStyle(.white.opacity(0.75))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("Edit by text")
                    .font(.system(size: 12, weight: .semibold))
                Text("Select words, then choose Cut from recording or press Delete.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.72))
                Text(
                    "Non-destructive: your original recording is safe, and cuts can be undone or restored."
                )
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.72))
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 8)

            Button {
                dismissEditingGuidance()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(LuxelGlassCircleButtonStyle(side: 24))
            .help("Dismiss transcript editing guidance")
            .accessibilityLabel("Dismiss transcript editing guidance")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    func cutReviewMenu(side: CGFloat) -> some View {
        Menu {
            ForEach(cutReviewItems) { cut in
                Button {
                    restoreCut(cut.id)
                } label: {
                    Label(cutRestoreLabel(cut), systemImage: "arrow.uturn.backward")
                }
            }
        } label: {
            Image(systemName: "list.bullet.rectangle.portrait")
        }
        .menuStyle(.button)
        .buttonStyle(LuxelGlassCircleButtonStyle(side: side))
        .help("Review and restore removed transcript ranges")
        .accessibilityLabel(
            "Review \(cutReviewItems.count) \(cutReviewItems.count == 1 ? "cut" : "cuts")"
        )
        .accessibilityHint("Opens a menu of removed transcript ranges that can be restored.")
    }

    func dismissEditingGuidance() {
        isEditingGuidanceDismissed = true
    }

    func performCut() {
        if deleteSelectedWord() {
            dismissEditingGuidance()
        }
    }

    func cutRestoreLabel(_ cut: TranscriptCutReviewItem) -> String {
        let range = "\(formattedTime(cut.sourceRange.start))–\(formattedTime(cut.sourceRange.end))"
        return cut.text.isEmpty ? "Restore \(range)" : "Restore “\(cut.text)” (\(range))"
    }

    private func formattedTime(_ time: TimeInterval) -> String {
        let totalSeconds = max(0, Int(time.rounded(.down)))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
