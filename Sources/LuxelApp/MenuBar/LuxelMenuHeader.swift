import SwiftUI

struct LuxelMenuHeader: View {
    let model: LuxelMenuModel

    var body: some View {
        HStack {
            Text("Luxel")
                .font(.headline)
            Spacer()
            Image(systemName: model.screenRecordingStatus.symbolName)
                .foregroundStyle(model.screenRecordingStatus.tint)
        }
    }
}
