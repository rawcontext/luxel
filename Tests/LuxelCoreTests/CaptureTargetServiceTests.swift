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
