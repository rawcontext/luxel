import LuxelCore
import SwiftUI

struct PermissionRow: View {
    let title: String
    let status: PermissionStatus
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: status.symbolName)
                .foregroundStyle(status.tint)
                .frame(width: 18)

            Text(title)
            Spacer()

            if status == .authorized {
                Text(status.title)
                    .foregroundStyle(.secondary)
            } else {
                Button(actionTitle, systemImage: "lock.open", action: action)
                    .labelStyle(.iconOnly)
                    .help(actionTitle)
            }
        }
        .font(.callout)
    }
}
