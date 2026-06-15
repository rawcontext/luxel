import SwiftUI

struct SelectionNumberField: View {
    let title: String
    @Binding var value: Int

    var body: some View {
        HStack(spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 10, alignment: .leading)

            TextField(title, value: $value, format: .number)
                .labelsHidden()
                .font(.callout)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(width: 58)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}
