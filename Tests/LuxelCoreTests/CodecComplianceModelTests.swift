import LuxelCore
import Testing

@Suite("Codec compliance models")
struct CodecComplianceModelTests {
    @Test("codec availability defaults to Apple-native export formats")
    func codecAvailabilityDefaultsToAppleNativeExportFormats() {
        #expect(CodecAvailability.none.registeredExternalFormats.isEmpty)
        #expect(CodecAvailability.none.availableExportFormats == [.mp4, .hevc, .gif, .apng])
        #expect(CodecAvailability.none.supports(.mp4))
        #expect(!CodecAvailability.none.supports(.webm))
        #expect(!CodecAvailability.none.supports(.av1))
    }

    @Test("codec availability appends registered external formats in menu order")
    func codecAvailabilityAppendsRegisteredExternalFormatsInMenuOrder() throws {
        let availability = try CodecAvailability(registeredExternalFormats: [.av1, .webm])

        #expect(availability.availableExportFormats == [.mp4, .hevc, .gif, .apng, .webm, .av1])
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
        #expect(CodecDependency.plannedNativeCodecStack.map(\.id) == ["libvpx", "libopus", "svt-av1", "libaom"])
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
}
