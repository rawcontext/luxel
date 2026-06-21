import Foundation
import SwiftUI

struct CodecAcknowledgementsView: View {
    @Environment(\.dismiss) private var dismiss

    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Text("Acknowledgements")
                    .font(.title3.weight(.semibold))

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Close")
                .help("Close")
            }

            ScrollView {
                Text(text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(width: 560, height: 440)
    }
}

enum CodecAcknowledgementsResource {
    static func bundledText(bundle: Bundle = .main) -> String {
        guard let url = bundle.url(forResource: "ThirdPartyLicenses", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return "No third-party codec acknowledgements are bundled."
        }

        return text
    }
}
