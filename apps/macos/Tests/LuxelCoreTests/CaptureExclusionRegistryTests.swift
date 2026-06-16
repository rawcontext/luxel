import Foundation
import LuxelCore
import Testing

@Suite("Capture exclusion registry")
struct CaptureExclusionRegistryTests {
    @Test("registry snapshots unique sorted window IDs")
    func registrySnapshotsUniqueSortedWindowIDs() async {
        let registry = CaptureExclusionRegistry()

        await registry.register(windowIDs: [42, 7, 42])
        await registry.register(windowIDs: [9, 7])

        #expect(await registry.excludedWindowIDs() == [7, 9, 42])
    }

    @Test("unregister removes only matching registration")
    func unregisterRemovesOnlyMatchingRegistration() async {
        let registry = CaptureExclusionRegistry()
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000701")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000702")!

        await registry.register(windowIDs: [11, 12], registrationID: firstID)
        await registry.register(windowID: 13, registrationID: secondID)
        await registry.unregister(firstID)

        #expect(await registry.excludedWindowIDs() == [13])
    }

    @Test("empty registration clears existing registration")
    func emptyRegistrationClearsExistingRegistration() async {
        let registry = CaptureExclusionRegistry()
        let registrationID = UUID(uuidString: "00000000-0000-0000-0000-000000000703")!

        await registry.register(windowID: 21, registrationID: registrationID)
        await registry.register(windowIDs: [], registrationID: registrationID)

        #expect(await registry.excludedWindowIDs().isEmpty)
    }
}
