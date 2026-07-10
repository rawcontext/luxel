import Foundation

public enum CodecLicenseLedgerMarkdownParserError: Error, Equatable, Sendable {
    case missingDependencyID
    case missingName(dependencyID: String)
    case missingLicense(dependencyID: String)
    case unknownLicense(dependencyID: String, rawValue: String)
    case missingCopyrightNotice(dependencyID: String)
    case missingLicenseText(dependencyID: String)
}

public struct CodecLicenseLedgerMarkdownParser: Equatable, Sendable {
    public init() {}

    public func parse(_ markdown: String) throws -> CodecLicenseLedger {
        var state = CodecLicenseLedgerParseState()
        for line in markdown.components(separatedBy: .newlines) {
            try state.consume(line)
        }
        return try state.ledger()
    }
}

private struct CodecLicenseLedgerParseState {
    var entries: [CodecLicenseLedgerEntry] = []
    var dependencyID: String?
    var name: String?
    var licenseRawValue: String?
    var copyrightNotice: String?
    var licenseTextLines: [String] = []
    var isReadingLicenseText = false

    mutating func consume(_ line: String) throws {
        if let nextDependencyID = dependencyIDHeading(in: line) {
            try appendCurrentEntry()
            guard !nextDependencyID.isBlank else {
                throw CodecLicenseLedgerMarkdownParserError.missingDependencyID
            }
            reset(dependencyID: nextDependencyID)
            return
        }
        if dependencyID != nil, isMarkdownHeading(line) {
            try appendCurrentEntry()
            reset(dependencyID: nil)
            return
        }
        guard dependencyID != nil else {
            return
        }
        if isReadingLicenseText {
            licenseTextLines.append(line)
        } else if let value = metadataValue(named: "Name", in: line) {
            name = value
        } else if let value = metadataValue(named: "License", in: line) {
            licenseRawValue = value
        } else if let value = metadataValue(named: "Copyright", in: line) {
            copyrightNotice = value
        } else if line.trimmingCharacters(in: .whitespaces) == "License Text:" {
            isReadingLicenseText = true
        }
    }

    mutating func ledger() throws -> CodecLicenseLedger {
        try appendCurrentEntry()
        return CodecLicenseLedger(entries: entries)
    }

    private mutating func appendCurrentEntry() throws {
        guard let dependencyID else {
            return
        }
        guard let name, !name.isBlank else {
            throw CodecLicenseLedgerMarkdownParserError.missingName(dependencyID: dependencyID)
        }
        guard let licenseRawValue, !licenseRawValue.isBlank else {
            throw CodecLicenseLedgerMarkdownParserError.missingLicense(dependencyID: dependencyID)
        }
        guard let license = ThirdPartyLicense(rawValue: licenseRawValue) else {
            throw CodecLicenseLedgerMarkdownParserError.unknownLicense(
                dependencyID: dependencyID,
                rawValue: licenseRawValue
            )
        }
        guard let copyrightNotice, !copyrightNotice.isBlank else {
            throw CodecLicenseLedgerMarkdownParserError.missingCopyrightNotice(
                dependencyID: dependencyID
            )
        }
        let licenseText = licenseTextLines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !licenseText.isBlank else {
            throw CodecLicenseLedgerMarkdownParserError.missingLicenseText(dependencyID: dependencyID)
        }
        entries.append(
            CodecLicenseLedgerEntry(
                dependencyID: dependencyID,
                name: name,
                license: license,
                copyrightNotice: copyrightNotice,
                licenseText: licenseText
            )
        )
    }

    private mutating func reset(dependencyID: String?) {
        self.dependencyID = dependencyID
        name = nil
        licenseRawValue = nil
        copyrightNotice = nil
        licenseTextLines = []
        isReadingLicenseText = false
    }

    private func dependencyIDHeading(in line: String) -> String? {
        let prefix = "## Dependency:"
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        guard trimmedLine.hasPrefix(prefix) else {
            return nil
        }

        return
            trimmedLine
            .dropFirst(prefix.count)
            .trimmingCharacters(in: .whitespaces)
    }

    private func metadataValue(named name: String, in line: String) -> String? {
        let prefix = "\(name):"
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        guard trimmedLine.hasPrefix(prefix) else {
            return nil
        }

        return
            trimmedLine
            .dropFirst(prefix.count)
            .trimmingCharacters(in: .whitespaces)
    }

    private func isMarkdownHeading(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("## ")
    }
}

extension String {
    fileprivate var isBlank: Bool {
        allSatisfy(\.isWhitespace)
    }
}
