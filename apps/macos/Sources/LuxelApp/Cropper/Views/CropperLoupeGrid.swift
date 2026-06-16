import LuxelCore
import SwiftUI

struct CropperLoupeGrid: View {
    let sample: CaptureLoupeSample

    var body: some View {
        Canvas { context, size in
            let columns = min(max(sample.sourceRect.width, 1), 24)
            let rows = min(max(sample.sourceRect.height, 1), 24)
            let cellWidth = size.width / CGFloat(columns)
            let cellHeight = size.height / CGFloat(rows)

            for row in 0..<rows {
                for column in 0..<columns {
                    let intensity = ((row + column).isMultiple(of: 2) ? 0.18 : 0.28)
                    let rect = CGRect(
                        x: CGFloat(column) * cellWidth,
                        y: CGFloat(row) * cellHeight,
                        width: cellWidth,
                        height: cellHeight
                    )
                    context.fill(
                        Path(rect),
                        with: .color(.white.opacity(intensity))
                    )
                }
            }

            var gridPath = Path()
            for column in 0...columns {
                let gridX = CGFloat(column) * cellWidth
                gridPath.move(to: CGPoint(x: gridX, y: 0))
                gridPath.addLine(to: CGPoint(x: gridX, y: size.height))
            }
            for row in 0...rows {
                let gridY = CGFloat(row) * cellHeight
                gridPath.move(to: CGPoint(x: 0, y: gridY))
                gridPath.addLine(to: CGPoint(x: size.width, y: gridY))
            }
            context.stroke(gridPath, with: .color(.white.opacity(0.20)), lineWidth: 0.5)
        }
    }
}
