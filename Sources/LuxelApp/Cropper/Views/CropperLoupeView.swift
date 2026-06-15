import LuxelCore
import LuxelPresentation
import SwiftUI

struct CropperLoupeView: View {
    let sample: CaptureLoupeSample

    var body: some View {
        GlassPanel {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(.black.opacity(0.46))

                    CropperLoupeGrid(sample: sample)
                        .padding(6)

                    Rectangle()
                        .fill(.white.opacity(0.78))
                        .frame(width: 1)

                    Rectangle()
                        .fill(.white.opacity(0.78))
                        .frame(height: 1)
                }
                .frame(width: 136, height: 74)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                HStack(spacing: 8) {
                    Text("x \(sample.readout.cursor.x) y \(sample.readout.cursor.y)")
                    Spacer(minLength: 8)
                    Text(selectionSummary)
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.primary)
            }
        }
        .accessibilityLabel("Selection loupe")
        .accessibilityValue("\(sample.readout.cursor.x), \(sample.readout.cursor.y), \(selectionSummary)")
    }

    private var selectionSummary: String {
        guard let selection = sample.readout.selection else {
            return "No selection"
        }

        return "\(selection.width)x\(selection.height)"
    }
}
