import LuxelCore
import Testing

@Suite("Bundle app metadata reader")
struct BundleAppMetadataReaderTests {
    @Test("reads app metadata from bundle info dictionary")
    func readsAppMetadataFromBundleInfoDictionary() {
        let reader = BundleAppMetadataReader(
            infoDictionary: [
                "CFBundleDisplayName": "Luxel",
                "CFBundleShortVersionString": "0.1.0",
                "CFBundleVersion": "7",
                "NSHumanReadableCopyright": "Copyright"
            ]
        )

        let metadata = reader.read()

        #expect(metadata.displayName == "Luxel")
        #expect(metadata.version == "0.1.0")
        #expect(metadata.build == "7")
        #expect(metadata.versionSummary == "0.1.0 (7)")
        #expect(metadata.copyright == "Copyright")
    }

    @Test("falls back to stable defaults when optional metadata is missing")
    func fallsBackToStableDefaults() {
        let reader = BundleAppMetadataReader(
            infoDictionary: [
                "CFBundleName": "Luxel"
            ]
        )

        let metadata = reader.read()

        #expect(metadata.displayName == "Luxel")
        #expect(metadata.version == "0.0.0")
        #expect(metadata.build == "")
        #expect(metadata.versionSummary == "0.0.0")
        #expect(metadata.copyright == "")
    }
}
