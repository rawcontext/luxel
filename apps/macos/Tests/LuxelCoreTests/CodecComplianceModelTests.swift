import Foundation
import LuxelCore
import Testing

@Suite("Codec compliance models")
struct CodecComplianceModelTests {
    @Test("codec availability defaults to Apple-native export formats")
    func codecAvailabilityDefaultsToAppleNativeExportFormats() {
        #expect(CodecAvailability.none.registeredExternalFormats.isEmpty)
        #expect(
            CodecAvailability.none.availableExportFormats
                == [.hevc, .mp4, .proRes422, .proRes4444, .gif, .apng])
        #expect(CodecAvailability.none.supports(.mp4))
        #expect(!CodecAvailability.none.supports(.webm))
        #expect(!CodecAvailability.none.supports(.av1))
    }

    @Test("codec availability appends registered external formats in menu order")
    func codecAvailabilityAppendsRegisteredExternalFormatsInMenuOrder() throws {
        let availability = try CodecAvailability(registeredExternalFormats: [.av1, .webm])

        #expect(
            availability.availableExportFormats
                == [.av1, .webm, .hevc, .mp4, .proRes422, .proRes4444, .gif, .apng])
        #expect(availability.supports(.webm))
        #expect(availability.supports(.av1))
    }

    @Test("codec availability rejects Apple-native formats as external registrations")
    func codecAvailabilityRejectsAppleNativeFormatsAsExternalRegistrations() {
        #expect(throws: CodecAvailabilityError.unsupportedExternalFormat(.mp4)) {
            _ = try CodecAvailability(registeredExternalFormats: [.mp4, .webm])
        }
    }

    @Test("planned native codec stack is Mac App Store allowlist clean")
    func plannedNativeCodecStackIsAllowlistClean() {
        let policy = CodecLicensePolicy()

        #expect(policy.deniedShippedDependencies(in: CodecDependency.plannedNativeCodecStack).isEmpty)
        #expect(
            CodecDependency.plannedNativeCodecStack.map(\.id) == [
                "libvpx", "libopus", "svt-av1", "libaom"
            ])
        #expect(CodecDependency.plannedNativeCodecStack.last?.isFallbackOnly == true)
    }

    @Test("policy allows only the documented shipped-code licenses")
    func policyAllowsOnlyDocumentedShippedCodeLicenses() {
        let policy = CodecLicensePolicy()
        let allowed: [ThirdPartyLicense] = [
            .bsd2Clause,
            .bsd3Clause,
            .bsd3ClauseClear,
            .mit,
            .apache2,
            .zlib,
            .isc,
            .publicDomain
        ]
        let denied: [ThirdPartyLicense] = [
            .gpl2,
            .gpl3,
            .lgpl21,
            .lgpl3,
            .proprietary,
            .unknown
        ]

        for license in allowed {
            let dependency = CodecDependency(
                id: license.rawValue,
                name: license.rawValue,
                role: "Allowed dependency",
                license: license
            )

            #expect(policy.decision(for: dependency) == .allowed)
        }

        for license in denied {
            let dependency = CodecDependency(
                id: license.rawValue,
                name: license.rawValue,
                role: "Denied dependency",
                license: license
            )

            #expect(policy.decision(for: dependency) == .denied)
        }
    }

    @Test("development tools are exempt from shipped-code license gate")
    func developmentToolsAreExemptFromShippedCodeLicenseGate() {
        let tool = CodecDependency(
            id: "fixture-analyzer",
            name: "Fixture Analyzer",
            role: "Dev-time output validation",
            license: .gpl3,
            use: .developmentTool
        )

        #expect(CodecLicensePolicy().decision(for: tool) == .developmentToolExempt)
    }

    @Test("license gate passes for bundled codec dependencies")
    func licenseGatePassesForBundledCodecDependencies() throws {
        let ledgerURL = try packageRootURL().appending(path: "THIRD_PARTY_LICENSES.md")
        let markdown = try String(contentsOf: ledgerURL, encoding: .utf8)
        let ledger = try CodecLicenseLedgerMarkdownParser().parse(markdown)
        let report = CodecLicenseGate().validate(
            dependencies: CodecDependency.bundledNativeCodecStack,
            ledger: ledger
        )

        #expect(CodecDependency.bundledNativeCodecStack.map(\.id) == ["libvpx", "libopus", "svt-av1"])
        #expect(report.isPassing)
        #expect(report.violations.isEmpty)
    }

    @Test("third party licenses ledger file passes current release gate")
    func thirdPartyLicensesLedgerFilePassesCurrentReleaseGate() throws {
        let ledgerURL = try packageRootURL().appending(path: "THIRD_PARTY_LICENSES.md")
        let markdown = try String(contentsOf: ledgerURL, encoding: .utf8)
        let ledger = try CodecLicenseLedgerMarkdownParser().parse(markdown)

        let report = CodecLicenseGate().validate(
            dependencies: CodecDependency.bundledNativeCodecStack,
            ledger: ledger
        )

        #expect(ledger.entries.map(\.dependencyID) == ["libvpx", "libopus", "svt-av1"])
        #expect(report.isPassing)
        #expect(report.violations.isEmpty)
    }

    @Test("license ledger markdown parser reads structured dependency entries")
    func licenseLedgerMarkdownParserReadsStructuredDependencyEntries() throws {
        let markdown = """
      # Third-Party Licenses

      ## Dependency: libvpx
      Name: libvpx
      License: BSD-3-Clause
      Copyright: Copyright 2026 The libvpx authors
      License Text:
      Redistribution and use in source and binary forms are permitted.
      """

        let ledger = try CodecLicenseLedgerMarkdownParser().parse(markdown)

        #expect(
            ledger
                == CodecLicenseLedger(entries: [
                    CodecLicenseLedgerEntry(
                        dependencyID: "libvpx",
                        name: "libvpx",
                        license: .bsd3Clause,
                        copyrightNotice: "Copyright 2026 The libvpx authors",
                        licenseText: "Redistribution and use in source and binary forms are permitted."
                    )
                ]))
    }

    @Test("license ledger markdown parser stops dependency text at nondependency headings")
    func licenseLedgerMarkdownParserStopsDependencyTextAtNondependencyHeadings() throws {
        let markdown = """
      ## Dependency: libvpx
      Name: libvpx
      License: BSD-3-Clause
      Copyright: Copyright 2026 The libvpx authors
      License Text:
      Redistribution and use in source and binary forms are permitted.

      ## Swift Argument Parser

      This section is not a codec dependency.
      """

        let ledger = try CodecLicenseLedgerMarkdownParser().parse(markdown)

        #expect(ledger.entries.count == 1)
        #expect(!ledger.entries[0].licenseText.contains("Swift Argument Parser"))
    }

    @Test("license ledger markdown parser rejects unknown licenses")
    func licenseLedgerMarkdownParserRejectsUnknownLicenses() {
        let markdown = """
      ## Dependency: forbidden
      Name: Forbidden Codec
      License: GPL-ish
      Copyright: Copyright 2026 Example
      License Text:
      Example license text.
      """

        #expect(
            throws: CodecLicenseLedgerMarkdownParserError.unknownLicense(
                dependencyID: "forbidden",
                rawValue: "GPL-ish"
            )
        ) {
            _ = try CodecLicenseLedgerMarkdownParser().parse(markdown)
        }
    }

    @Test("license ledger markdown parser requires license text")
    func licenseLedgerMarkdownParserRequiresLicenseText() {
        let markdown = """
      ## Dependency: libopus
      Name: libopus
      License: BSD-3-Clause
      Copyright: Copyright 2026 The Opus authors
      License Text:

      """

        #expect(
            throws: CodecLicenseLedgerMarkdownParserError.missingLicenseText(
                dependencyID: "libopus"
            )
        ) {
            _ = try CodecLicenseLedgerMarkdownParser().parse(markdown)
        }
    }

    @Test("license gate requires ledger entries for planned shipped codec stack")
    func licenseGateRequiresLedgerEntriesForPlannedShippedCodecStack() {
        let report = CodecLicenseGate().validate(
            dependencies: CodecDependency.plannedNativeCodecStack,
            ledger: CodecLicenseLedger()
        )

        #expect(!report.isPassing)
        #expect(
            report.violations == [
                .missingLedgerEntry(dependencyID: "libvpx"),
                .missingLedgerEntry(dependencyID: "libopus"),
                .missingLedgerEntry(dependencyID: "svt-av1"),
                .missingLedgerEntry(dependencyID: "libaom")
            ])
    }

    @Test("license gate passes planned stack with matching license ledger")
    func licenseGatePassesPlannedStackWithMatchingLicenseLedger() {
        let ledger = CodecLicenseLedger(
            entries: CodecDependency.plannedNativeCodecStack.map { dependency in
                CodecLicenseLedgerEntry(
                    dependencyID: dependency.id,
                    name: dependency.name,
                    license: dependency.license,
                    copyrightNotice: "Copyright notice for \(dependency.name)",
                    licenseText: "\(dependency.license.rawValue) license text for \(dependency.name)"
                )
            }
        )

        let report = CodecLicenseGate().validate(
            dependencies: CodecDependency.plannedNativeCodecStack,
            ledger: ledger
        )

        #expect(report.isPassing)
    }

    @Test("license gate reports denied licenses and invalid ledger content")
    func licenseGateReportsDeniedLicensesAndInvalidLedgerContent() {
        let dependencies = [
            CodecDependency(
                id: "libvpx",
                name: "libvpx",
                role: "VP9 video encode",
                license: .bsd3Clause
            ),
            CodecDependency(
                id: "forbidden",
                name: "Forbidden Encoder",
                role: "Fixture",
                license: .gpl3
            ),
            CodecDependency(
                id: "dev-tool",
                name: "Dev Tool",
                role: "Fixture",
                license: .gpl3,
                use: .developmentTool
            )
        ]
        let ledger = CodecLicenseLedger(entries: [
            CodecLicenseLedgerEntry(
                dependencyID: "libvpx",
                name: "libvpx",
                license: .mit,
                copyrightNotice: "",
                licenseText: "   "
            ),
            CodecLicenseLedgerEntry(
                dependencyID: "libvpx",
                name: "libvpx duplicate",
                license: .bsd3Clause,
                copyrightNotice: "Copyright notice",
                licenseText: "BSD-3-Clause license text"
            )
        ])

        let report = CodecLicenseGate().validate(dependencies: dependencies, ledger: ledger)

        #expect(
            report.violations == [
                .duplicateLedgerEntry(dependencyID: "libvpx"),
                .licenseMismatch(dependencyID: "libvpx", expected: .bsd3Clause, actual: .mit),
                .missingCopyrightNotice(dependencyID: "libvpx"),
                .missingLicenseText(dependencyID: "libvpx"),
                .deniedShippedDependency(dependencyID: "forbidden", license: .gpl3)
            ])
    }

    @Test("shipped non-public-domain dependencies require bundled license text")
    func shippedDependenciesRequireBundledLicenseText() {
        let policy = CodecLicensePolicy()
        let shippedLibrary = CodecDependency(
            id: "libvpx",
            name: "libvpx",
            role: "VP9 video encode",
            license: .bsd3Clause
        )
        let publicDomainLibrary = CodecDependency(
            id: "public-domain-lib",
            name: "Public Domain Lib",
            role: "Fixture",
            license: .publicDomain
        )
        let tool = CodecDependency(
            id: "dev-tool",
            name: "Dev Tool",
            role: "Fixture",
            license: .bsd3Clause,
            use: .developmentTool
        )

        #expect(policy.requiresBundledLicenseText(shippedLibrary))
        #expect(!policy.requiresBundledLicenseText(publicDomainLibrary))
        #expect(!policy.requiresBundledLicenseText(tool))
    }

    private func packageRootURL() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "Tests" {
            let next = url.deletingLastPathComponent()
            try #require(next.path != url.path)
            url = next
        }

        return url.deletingLastPathComponent()
    }
}
