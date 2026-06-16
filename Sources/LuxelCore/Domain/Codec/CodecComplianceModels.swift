import Foundation

public enum ThirdPartyLicense: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case bsd2Clause = "BSD-2-Clause"
    case bsd3Clause = "BSD-3-Clause"
    case bsd3ClauseClear = "BSD-3-Clause-Clear"
    case mit = "MIT"
    case apache2 = "Apache-2.0"
    case zlib
    case isc = "ISC"
    case publicDomain = "Public Domain"
    case gpl2 = "GPL-2.0"
    case gpl3 = "GPL-3.0"
    case lgpl21 = "LGPL-2.1"
    case lgpl3 = "LGPL-3.0"
    case proprietary
    case unknown
}

public enum CodecDependencyUse: String, Codable, Equatable, Sendable {
    case shippedLibrary
    case developmentTool
}

public struct CodecDependency: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let role: String
    public let license: ThirdPartyLicense
    public let patentGrant: String?
    public let use: CodecDependencyUse
    public let isFallbackOnly: Bool

    public init(
        id: String,
        name: String,
        role: String,
        license: ThirdPartyLicense,
        patentGrant: String? = nil,
        use: CodecDependencyUse = .shippedLibrary,
        isFallbackOnly: Bool = false
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.license = license
        self.patentGrant = patentGrant
        self.use = use
        self.isFallbackOnly = isFallbackOnly
    }

    public static let plannedNativeCodecStack: [CodecDependency] = [
        CodecDependency(
            id: "libvpx",
            name: "libvpx",
            role: "VP9 video encode",
            license: .bsd3Clause,
            patentGrant: "Google Additional IP Rights Grant"
        ),
        CodecDependency(
            id: "libopus",
            name: "libopus",
            role: "Opus audio encode",
            license: .bsd3Clause,
            patentGrant: "Xiph, Broadcom, and Microsoft/Skype patent grants"
        ),
        CodecDependency(
            id: "svt-av1",
            name: "SVT-AV1",
            role: "AV1 video encode",
            license: .bsd3ClauseClear,
            patentGrant: "Alliance for Open Media Patent License 1.0"
        ),
        CodecDependency(
            id: "libaom",
            name: "libaom",
            role: "Fallback AV1 video encode",
            license: .bsd2Clause,
            patentGrant: "AOM Patent License 1.0",
            isFallbackOnly: true
        )
    ]

    public static let bundledNativeCodecStack: [CodecDependency] = [
        CodecDependency(
            id: "libvpx",
            name: "libvpx",
            role: "VP9 video encode",
            license: .bsd3Clause,
            patentGrant: "Google Additional IP Rights Grant"
        ),
        CodecDependency(
            id: "libopus",
            name: "libopus",
            role: "Opus audio encode",
            license: .bsd3Clause,
            patentGrant: "Xiph, Broadcom, and Microsoft/Skype patent grants"
        )
    ]
}

public enum CodecLicenseDecision: Equatable, Sendable {
    case allowed
    case developmentToolExempt
    case denied
}

public struct CodecLicensePolicy: Equatable, Sendable {
    public static let macAppStoreShippedAllowlist: Set<ThirdPartyLicense> = [
        .bsd2Clause,
        .bsd3Clause,
        .bsd3ClauseClear,
        .mit,
        .apache2,
        .zlib,
        .isc,
        .publicDomain
    ]

    public init() {}

    public func decision(for dependency: CodecDependency) -> CodecLicenseDecision {
        switch dependency.use {
        case .developmentTool:
            .developmentToolExempt
        case .shippedLibrary:
            Self.macAppStoreShippedAllowlist.contains(dependency.license) ? .allowed : .denied
        }
    }

    public func deniedShippedDependencies(in dependencies: [CodecDependency]) -> [CodecDependency] {
        dependencies.filter { decision(for: $0) == .denied }
    }

    public func requiresBundledLicenseText(_ dependency: CodecDependency) -> Bool {
        dependency.use == .shippedLibrary && dependency.license != .publicDomain
    }
}
