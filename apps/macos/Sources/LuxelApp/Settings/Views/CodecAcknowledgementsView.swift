import Foundation
import LuxelCore
import SwiftUI

struct CodecAcknowledgementsView: View {
    @Environment(\.dismiss) private var dismiss

    let text: String

    private var blocks: [AcknowledgementBlock] {
        AcknowledgementBlock.parse(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(blocks) { block in
                        blockView(block)
                    }
                }
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 12)
            }
        }
        .padding(20)
        .frame(width: 640, height: 540)
    }

    @ViewBuilder
    private func blockView(_ block: AcknowledgementBlock) -> some View {
        switch block.kind {
        case .title(let text):
            Text(text)
                .font(.system(size: 15, weight: .bold))
                .padding(.bottom, 8)
        case .heading(let text):
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .padding(.top, 18)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .bottom) {
                    Divider()
                }
        case .listItem(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(.secondary)
                    .frame(width: 4, height: 4)
                    .padding(.top, 5)

                Text(text)
                    .font(.system(size: 12))
            }
            .padding(.bottom, 4)
        case .field(let label, let value):
            let styledLabel = Text(verbatim: label)
                .font(.system(size: 12, weight: .semibold))
            let styledValue = Text(verbatim: value)
                .font(.system(size: 12))
            Text("\(styledLabel): \(styledValue)")
                .padding(.bottom, 4)
        case .paragraph(let text):
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.primary.opacity(0.85))
                .padding(.bottom, 8)
        }
    }
}

struct AcknowledgementBlock: Identifiable {
    enum Kind {
        case title(String)
        case heading(String)
        case listItem(String)
        case field(label: String, value: String)
        case paragraph(String)
    }

    let id: Int
    let kind: Kind

    private static let fieldLabels = ["Name", "License Text", "License", "Copyright"]

    static func parse(_ markdown: String) -> [AcknowledgementBlock] {
        var kinds: [Kind] = []
        var paragraph: [String] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else {
                return
            }

            kinds.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph = []
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flushParagraph()
            } else if line.hasPrefix("# ") {
                flushParagraph()
                kinds.append(.title(String(line.dropFirst(2))))
            } else if line.hasPrefix("## ") {
                flushParagraph()
                kinds.append(.heading(headingText(String(line.dropFirst(3)))))
            } else if let item = listItemText(line) {
                flushParagraph()
                kinds.append(.listItem(item))
            } else if let field = fieldKind(line) {
                flushParagraph()
                kinds.append(field)
            } else {
                paragraph.append(line)
            }
        }

        flushParagraph()
        return kinds.enumerated().map { AcknowledgementBlock(id: $0.offset, kind: $0.element) }
    }

    private static func headingText(_ heading: String) -> String {
        heading.hasPrefix("Dependency: ")
            ? String(heading.dropFirst("Dependency: ".count)) : heading
    }

    private static func listItemText(_ line: String) -> String? {
        if line.hasPrefix("- ") || line.hasPrefix("* ") {
            return String(line.dropFirst(2))
        }

        // The top-of-file component list uses "1. libvpx — ..." entries; body
        // text such as license clauses keeps its own numbering as paragraphs.
        if let dotIndex = line.firstIndex(of: "."),
            line.distance(from: line.startIndex, to: dotIndex) <= 2,
            !line[line.startIndex..<dotIndex].isEmpty,
            line[line.startIndex..<dotIndex].allSatisfy(\.isNumber),
            line.contains(" — ") {
            let itemStart = line.index(dotIndex, offsetBy: 1)
            return String(line[itemStart...]).trimmingCharacters(in: .whitespaces)
        }

        return nil
    }

    private static func fieldKind(_ line: String) -> Kind? {
        for label in fieldLabels {
            let prefix = "\(label):"
            guard line.hasPrefix(prefix) else {
                continue
            }

            let value = String(line.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else {
                return nil
            }

            return .field(label: label, value: value)
        }

        return nil
    }
}

enum CodecAcknowledgementsResource {
    static func bundledText(bundle: Bundle = .main) -> String {
        guard let url = bundle.url(forResource: "ThirdPartyLicenses", withExtension: "md"),
            let text = try? String(contentsOf: url, encoding: .utf8),
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return LuxelLocalization.string(
                "acknowledgements.unavailable",
                defaultValue: "No third-party acknowledgements are bundled."
            )
        }

        return text
    }
}
