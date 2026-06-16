import SwiftUI

struct CheckerboardBackground: View {
    private let squareSize: CGFloat = 18

    var body: some View {
        Canvas { context, size in
            let columns = Int((size.width / squareSize).rounded(.up))
            let rows = Int((size.height / squareSize).rounded(.up))

            for row in 0...rows {
                for column in 0...columns where (row + column).isMultiple(of: 2) {
                    let rect = CGRect(
                        x: CGFloat(column) * squareSize,
                        y: CGFloat(row) * squareSize,
                        width: squareSize,
                        height: squareSize
                    )
                    context.fill(Path(rect), with: .color(.white.opacity(0.16)))
                }
            }
        }
        .background(Color.black)
    }
}
