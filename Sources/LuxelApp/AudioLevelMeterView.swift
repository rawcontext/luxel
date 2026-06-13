import LuxelCore
import SwiftUI

struct AudioLevelMeterView: View {
    let sample: AudioLevelSample

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<12, id: \.self) { index in
                Capsule()
                    .fill(fillColor(for: index))
                    .frame(width: 7, height: barHeight(for: index))
            }
        }
        .frame(height: 18, alignment: .center)
        .accessibilityLabel("Input Level")
        .accessibilityValue("\(Int((sample.peak * 100).rounded())) percent")
    }

    private func barHeight(for index: Int) -> CGFloat {
        6 + CGFloat(index) * 0.8
    }

    private func fillColor(for index: Int) -> Color {
        let threshold = Double(index + 1) / 12
        guard sample.peak >= threshold else {
            return .secondary.opacity(0.25)
        }

        if threshold > 0.85 {
            return .red
        }

        if threshold > 0.65 {
            return .yellow
        }

        return .green
    }
}
