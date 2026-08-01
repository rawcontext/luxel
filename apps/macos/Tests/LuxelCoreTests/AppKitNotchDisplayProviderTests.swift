import AppKit
import CoreGraphics
import LuxelCore
import Testing

@Suite("AppKit notch display provider")
struct AppKitNotchDisplayProviderTests {
    @Test("display updates yield initial and notification snapshots")
    @MainActor
    func displayUpdatesYieldInitialAndNotificationSnapshots() async throws {
        let notificationCenter = NotificationCenter()
        let notificationName = Notification.Name("AppKitNotchDisplayProviderTests.screenChanged")
        let firstDisplay = try descriptor(displayID: 1)
        let secondDisplay = try descriptor(displayID: 2)
        var snapshots = [
            [firstDisplay],
            [secondDisplay]
        ]
        let stream = AppKitNotchDisplayProvider.displayUpdates(
            notificationCenter: notificationCenter,
            notificationName: notificationName
        ) {
            snapshots.removeFirst()
        }
        var iterator = stream.makeAsyncIterator()

        let initialSnapshot = await iterator.next()
        notificationCenter.post(name: notificationName, object: nil)
        let changedSnapshot = await iterator.next()

        #expect(initialSnapshot == [firstDisplay])
        #expect(changedSnapshot == [secondDisplay])
    }

    @Test("descriptor maps AppKit screen geometry into notch display facts")
    func descriptorMapsAppKitScreenGeometryIntoNotchDisplayFacts() throws {
        let descriptor = try #require(
            makeDescriptor(
                displayID: 1,
                width: 1512,
                safeAreaTop: 34,
                auxiliaryTopLeftArea: CGRect(x: 0, y: 948, width: 640, height: 34),
                auxiliaryTopRightArea: CGRect(x: 872, y: 948, width: 640, height: 34)
            ))

        #expect(descriptor.displayID == DisplayID(1))
        #expect(descriptor.frame == (try rect(x: 0, y: 0, width: 1512, height: 982)))
        #expect(descriptor.safeAreaInsets == (try NotchSafeAreaInsets(top: 34)))
        #expect(descriptor.auxiliaryTopLeftArea == (try rect(x: 0, y: 948, width: 640, height: 34)))
        #expect(descriptor.auxiliaryTopRightArea == (try rect(x: 872, y: 948, width: 640, height: 34)))
        #expect(descriptor.isBuiltIn)
        #expect(descriptor.isVisible)
        #expect(
            NotchGeometry.resolve(from: descriptor)?.cameraHousingRect
                == (try rect(x: 640, y: 948, width: 232, height: 34)))
    }

    @Test("descriptor rejects missing display id and invalid screen facts")
    func descriptorRejectsMissingDisplayIDAndInvalidScreenFacts() {
        #expect(
            makeDescriptor(displayID: nil, width: 1512, safeAreaTop: 34) == nil)

        #expect(
            makeDescriptor(displayID: 1, width: 0, safeAreaTop: 34) == nil)

        #expect(
            makeDescriptor(displayID: 1, width: 1512, safeAreaTop: .nan) == nil)
    }

    private func rect(
        x originX: Double,
        y originY: Double,
        width: Double,
        height: Double
    ) throws -> NotchScreenRect {
        try NotchScreenRect(x: originX, y: originY, width: width, height: height)
    }

    private func descriptor(displayID: CGDirectDisplayID) throws -> NotchDisplayDescriptor {
        try #require(
            AppKitNotchDisplayProvider.descriptor(
                displayID: displayID,
                frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                safeAreaInsets: NSEdgeInsets(top: 34, left: 0, bottom: 0, right: 0),
                auxiliaryTopLeftArea: CGRect(x: 0, y: 948, width: 640, height: 34),
                auxiliaryTopRightArea: CGRect(x: 872, y: 948, width: 640, height: 34),
                isBuiltIn: true
            ))
    }

    private func makeDescriptor(
        displayID: CGDirectDisplayID?,
        width: Double,
        safeAreaTop: Double,
        auxiliaryTopLeftArea: CGRect? = nil,
        auxiliaryTopRightArea: CGRect? = nil
    ) -> NotchDisplayDescriptor? {
        AppKitNotchDisplayProvider.descriptor(
            displayID: displayID,
            frame: CGRect(x: 0, y: 0, width: width, height: 982),
            safeAreaInsets: NSEdgeInsets(top: safeAreaTop, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: auxiliaryTopLeftArea,
            auxiliaryTopRightArea: auxiliaryTopRightArea,
            isBuiltIn: true
        )
    }
}
