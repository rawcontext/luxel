import LuxelCore
import Testing

@Suite("Capture target service")
struct CaptureTargetServiceTests {
    @Test("available displays returns catalog displays")
    func availableDisplaysReturnsCatalogDisplays() async throws {
        let display = try DisplayBounds(id: DisplayID(12), x: 0, y: 0, width: 1280, height: 720)
        let catalog = FakeCaptureTargetCatalog(displays: [display], targets: [])
        let service = CaptureTargetService(catalog: catalog)

        let displays = try await service.availableDisplays()

        #expect(displays == [display])
    }

    @Test("available targets returns catalog targets")
    func availableTargetsReturnsCatalogTargets() async throws {
        let target = try CaptureTargetOption(
            id: "display-12",
            kind: .display,
            title: "Display 1",
            target: .display(DisplayID(12)),
            pixelSize: PixelSize(width: 1280, height: 720)
        )
        let catalog = FakeCaptureTargetCatalog(displays: [], targets: [target])
        let service = CaptureTargetService(catalog: catalog)

        let targets = try await service.availableTargets()

        #expect(targets == [target])
    }

    @Test("menu filter hides known utility windows")
    func menuFilterHidesKnownUtilityWindows() throws {
        let display = try CaptureTargetOption(
            id: "display-12",
            kind: .display,
            title: "Display 1",
            target: .display(DisplayID(12)),
            pixelSize: PixelSize(width: 1280, height: 720)
        )
        let appIconWindow = try windowTarget(id: 1, title: "App Icon Window")
        let gestureOverlay = try windowTarget(id: 2, title: "Gesture Blocking Overlay")
        let realWindow = try windowTarget(id: 3, title: "Codex")

        let targets = CaptureTargetMenuFilter().visibleTargets(from: [
            display,
            appIconWindow,
            gestureOverlay,
            realWindow
        ])

        #expect(targets == [display, realWindow])
    }

    @Test("service forwards explicit refresh to catalog")
    func serviceForwardsExplicitRefreshToCatalog() async throws {
        let catalog = SpyCaptureTargetCatalog(snapshots: [
            try makeSnapshot(displayID: 12)
        ])
        let service = CaptureTargetService(catalog: catalog)

        try await service.refresh()

        #expect(await catalog.refreshCallCount == 1)
    }

    @Test("cached catalog reuses snapshot for repeated reads")
    func cachedCatalogReusesSnapshotForRepeatedReads() async throws {
        let upstream = SpyCaptureTargetCatalog(snapshots: [
            try makeSnapshot(displayID: 12)
        ])
        let catalog = CachedCaptureTargetCatalog(upstream: upstream)

        let firstTargets = try await catalog.availableTargets()
        let secondTargets = try await catalog.availableTargets()
        let displays = try await catalog.availableDisplays()

        #expect(firstTargets == secondTargets)
        #expect(displays == [try display(id: 12)])
        #expect(await upstream.snapshotCallCount == 1)
        #expect(await upstream.displayCallCount == 0)
        #expect(await upstream.targetCallCount == 0)
    }

    @Test("cached catalog refresh replaces snapshot")
    func cachedCatalogRefreshReplacesSnapshot() async throws {
        let upstream = SpyCaptureTargetCatalog(snapshots: [
            try makeSnapshot(displayID: 12),
            try makeSnapshot(displayID: 34)
        ])
        let catalog = CachedCaptureTargetCatalog(upstream: upstream)

        let initialTargets = try await catalog.availableTargets()
        try await catalog.refresh()
        let refreshedTargets = try await catalog.availableTargets()

        #expect(initialTargets.first?.id == "display-12")
        #expect(refreshedTargets.first?.id == "display-34")
        #expect(await upstream.snapshotCallCount == 2)
        #expect(await upstream.displayCallCount == 0)
        #expect(await upstream.targetCallCount == 0)
    }

    private func makeSnapshot(displayID: UInt32) throws -> CaptureTargetCatalogSnapshot {
        try CaptureTargetCatalogSnapshot(
            displays: [display(id: displayID)],
            targets: [target(id: displayID)]
        )
    }

    private func display(id: UInt32) throws -> DisplayBounds {
        try DisplayBounds(id: DisplayID(id), x: 0, y: 0, width: 1280, height: 720)
    }

    private func target(id: UInt32) throws -> CaptureTargetOption {
        try CaptureTargetOption(
            id: "display-\(id)",
            kind: .display,
            title: "Display \(id)",
            target: .display(DisplayID(id)),
            pixelSize: PixelSize(width: 1280, height: 720)
        )
    }

    private func windowTarget(id: UInt32, title: String) throws -> CaptureTargetOption {
        try CaptureTargetOption(
            id: "window-\(id)",
            kind: .window,
            title: title,
            target: .window(id: id),
            pixelSize: PixelSize(width: 640, height: 480)
        )
    }
}

private struct FakeCaptureTargetCatalog: CaptureTargetCatalog {
    let displays: [DisplayBounds]
    let targets: [CaptureTargetOption]

    func availableDisplays() async throws -> [DisplayBounds] {
        displays
    }

    func availableTargets() async throws -> [CaptureTargetOption] {
        targets
    }
}

private actor SpyCaptureTargetCatalog: CaptureTargetCatalog {
    private var snapshots: [CaptureTargetCatalogSnapshot]
    private(set) var displayCallCount = 0
    private(set) var targetCallCount = 0
    private(set) var snapshotCallCount = 0
    private(set) var refreshCallCount = 0

    init(snapshots: [CaptureTargetCatalogSnapshot]) {
        self.snapshots = snapshots
    }

    func availableDisplays() async throws -> [DisplayBounds] {
        displayCallCount += 1
        return currentSnapshot.displays
    }

    func availableTargets() async throws -> [CaptureTargetOption] {
        targetCallCount += 1
        let snapshot = currentSnapshot
        if snapshots.count > 1 {
            snapshots.removeFirst()
        }
        return snapshot.targets
    }

    func snapshot() async throws -> CaptureTargetCatalogSnapshot {
        snapshotCallCount += 1
        let snapshot = currentSnapshot
        if snapshots.count > 1 {
            snapshots.removeFirst()
        }
        return snapshot
    }

    func refresh() async throws {
        refreshCallCount += 1
    }

    private var currentSnapshot: CaptureTargetCatalogSnapshot {
        snapshots.first ?? CaptureTargetCatalogSnapshot(displays: [], targets: [])
    }
}
