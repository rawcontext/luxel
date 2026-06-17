import CoreGraphics
import LuxelCore
import LuxelPresentation
import SwiftUI

struct CropperLoupeView: View {
    let sample: CaptureLoupeSample
    let image: CGImage?
    let imageStatus: CropperLoupeImageStatus

    var body: some View {
        GlassPanel {
            HStack(alignment: .center, spacing: 10) {
                preview
                readout
            }
        }
        .accessibilityLabel("Selection loupe")
        .accessibilityValue(
            "\(sample.readout.cursor.xCoordinate), \(sample.readout.cursor.yCoordinate), \(selectionSummary)"
        )
    }

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(.black.opacity(0.46))

            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFill()
            } else {
                CropperLoupeGrid(sample: sample)
                    .padding(5)
                    .opacity(imageStatus == .unavailable ? 0.34 : 0.54)
            }

            crosshair
        }
        .frame(width: 104, height: 104)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(.white.opacity(0.20), lineWidth: 1)
        }
    }

    private var crosshair: some View {
        ZStack {
            Rectangle()
                .fill(.white.opacity(0.82))
                .frame(width: 1, height: 22)
            Rectangle()
                .fill(.white.opacity(0.82))
                .frame(width: 22, height: 1)
            Circle()
                .fill(.white.opacity(0.92))
                .frame(width: 3, height: 3)
        }
        .shadow(color: .black.opacity(0.55), radius: 1, x: 0, y: 0)
    }

    private var readout: some View {
        VStack(alignment: .leading, spacing: 5) {
            metric("X", value: sample.readout.cursor.xCoordinate)
            metric("Y", value: sample.readout.cursor.yCoordinate)

            Rectangle()
                .fill(.white.opacity(0.16))
                .frame(height: 1)
                .padding(.vertical, 1)

            if let selection = sample.readout.selection {
                metric("W", value: selection.width)
                metric("H", value: selection.height)
            } else {
                Text("No selection")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(width: 58, alignment: .leading)
    }

    private func metric(_ label: String, value: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 11, alignment: .leading)

            Text(value.formatted(.number.grouping(.automatic)))
                .font(.caption2.monospacedDigit().weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: 13)
    }

    private var selectionSummary: String {
        guard let selection = sample.readout.selection else {
            return "No selection"
        }

        return "\(selection.width)x\(selection.height)"
    }
}
