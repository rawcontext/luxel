public struct CodecLicenseLedgerEntry: Codable, Equatable, Identifiable, Sendable {
    public let dependencyID: String
    public let name: String
    public let license: ThirdPartyLicense
    public let copyrightNotice: String
    public let licenseText: String

    public var id: String {
        dependencyID
    }

    public init(
        dependencyID: String,
        name: String,
        license: ThirdPartyLicense,
        copyrightNotice: String,
        licenseText: String
    ) {
        self.dependencyID = dependencyID
        self.name = name
        self.license = license
        self.copyrightNotice = copyrightNotice
        self.licenseText = licenseText
    }
}

public struct CodecLicenseLedger: Codable, Equatable, Sendable {
    public let entries: [CodecLicenseLedgerEntry]

    public init(entries: [CodecLicenseLedgerEntry] = []) {
        self.entries = entries
    }

    public func entries(for dependencyID: String) -> [CodecLicenseLedgerEntry] {
        entries.filter { $0.dependencyID == dependencyID }
    }
}

public enum CodecLicenseGateViolation: Equatable, Sendable {
    case deniedShippedDependency(dependencyID: String, license: ThirdPartyLicense)
    case missingLedgerEntry(dependencyID: String)
    case duplicateLedgerEntry(dependencyID: String)
    case licenseMismatch(dependencyID: String, expected: ThirdPartyLicense, actual: ThirdPartyLicense)
    case missingCopyrightNotice(dependencyID: String)
    case missingLicenseText(dependencyID: String)
}

public struct CodecLicenseGateReport: Equatable, Sendable {
    public let violations: [CodecLicenseGateViolation]

    public init(violations: [CodecLicenseGateViolation]) {
        self.violations = violations
    }

    public var isPassing: Bool {
        violations.isEmpty
    }
}

public struct CodecLicenseGate: Equatable, Sendable {
    private let policy: CodecLicensePolicy

    public init(policy: CodecLicensePolicy = CodecLicensePolicy()) {
        self.policy = policy
    }

    public func validate(
        dependencies: [CodecDependency],
        ledger: CodecLicenseLedger
    ) -> CodecLicenseGateReport {
        var violations: [CodecLicenseGateViolation] = []

        for dependency in dependencies where dependency.use == .shippedLibrary {
            if policy.decision(for: dependency) == .denied {
                violations.append(.deniedShippedDependency(
                    dependencyID: dependency.id,
                    license: dependency.license
                ))
                continue
            }

            guard policy.requiresBundledLicenseText(dependency) else {
                continue
            }

            let entries = ledger.entries(for: dependency.id)
            guard let entry = entries.first else {
                violations.append(.missingLedgerEntry(dependencyID: dependency.id))
                continue
            }

            if entries.count > 1 {
                violations.append(.duplicateLedgerEntry(dependencyID: dependency.id))
            }

            if entry.license != dependency.license {
                violations.append(.licenseMismatch(
                    dependencyID: dependency.id,
                    expected: dependency.license,
                    actual: entry.license
                ))
            }

            if entry.copyrightNotice.isBlank {
                violations.append(.missingCopyrightNotice(dependencyID: dependency.id))
            }

            if entry.licenseText.isBlank {
                violations.append(.missingLicenseText(dependencyID: dependency.id))
            }
        }

        return CodecLicenseGateReport(violations: violations)
    }
}

private extension String {
    var isBlank: Bool {
        allSatisfy(\.isWhitespace)
    }
}
