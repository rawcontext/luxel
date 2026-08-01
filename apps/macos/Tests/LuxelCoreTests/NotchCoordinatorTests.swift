import Foundation
import LuxelCore
import Testing

@Suite("Notch coordinator")
struct NotchCoordinatorTests {
    @Test("present acquires notch surface and sends resolved activity update")
    func presentAcquiresNotchSurfaceAndSendsResolvedActivityUpdate() async throws {
        let presenter = SpyNotchPresenter()
        let coordinator = NotchCoordinator(presenter: presenter)
        let display = try testBuiltInNotchedDisplay()
        let coverage = try NotchReplayBufferCoverage(coveredDuration: 30, requestedDuration: 60)
        let recording = NotchActivity.recording(elapsed: 42, audioLevel: .silent, muted: false)

        let result = await coordinator.present(
            activities: [
                .replayBuffering(coverage: coverage),
                recording
            ],
            displays: [display],
            presentationState: .expanded
        )

        let update = try #require(result.update)
        let geometry = try #require(NotchGeometry.resolve(from: display))
        #expect(result.selection == .notch(geometry))
        #expect(update.geometry == geometry)
        #expect(update.activity == recording)
        #expect(update.presentationState == .expanded)
        #expect(update.viewModel == NotchActivityPresentation.viewModel(for: recording))
        #expect(update.motion == .standard)
        #expect(
            await presenter.commands() == [
                .acquire(geometry),
                .present(update)
            ])
    }

    @Test("present uses reduced motion when requested")
    func presentUsesReducedMotionWhenRequested() async throws {
        let presenter = SpyNotchPresenter()
        let coordinator = NotchCoordinator(presenter: presenter)

        let result = await coordinator.present(
            activities: [.idleHover],
            displays: [try testBuiltInNotchedDisplay()],
            reduceMotion: true
        )

        #expect(result.update?.motion == .reduced)
    }

    @Test("present passes recording action replacement into view model")
    func presentPassesRecordingActionReplacementIntoViewModel() async throws {
        let presenter = SpyNotchPresenter()
        let coordinator = NotchCoordinator(presenter: presenter)
        let recording = NotchActivity.recording(elapsed: 5, audioLevel: .silent, muted: false)

        let result = await coordinator.present(
            activities: [recording],
            displays: [try testBuiltInNotchedDisplay()],
            presentationState: .expanded,
            recordingActionToReplace: .recordArea
        )

        #expect(
            result.update?.viewModel.actions.map(\.id) == [
                .recordFullscreen,
                .stopRecording,
                .recordAudioOnly,
                .openSettings
            ])
    }

    @Test("present releases presenter when notch is unavailable")
    func presentReleasesPresenterWhenNotchIsUnavailable() async throws {
        let presenter = SpyNotchPresenter()
        let coordinator = NotchCoordinator(presenter: presenter)

        let result = await coordinator.present(
            activities: [.idleHover],
            displays: []
        )

        #expect(result.selection == .floatingHUD(.noNotchedDisplay))
        #expect(result.update == nil)
        #expect(await presenter.commands() == [.release])
    }

    @Test("present releases presenter when notch is disabled")
    func presentReleasesPresenterWhenNotchIsDisabled() async throws {
        let presenter = SpyNotchPresenter()
        let coordinator = NotchCoordinator(presenter: presenter)

        let result = await coordinator.present(
            activities: [.idleHover],
            displays: [try testBuiltInNotchedDisplay()],
            preferences: NotchSurfacePreferences(isEnabled: false)
        )

        #expect(result.selection == .floatingHUD(.notchDisabled))
        #expect(result.update == nil)
        #expect(await presenter.commands() == [.release])
    }

    @Test("display update observation migrates from notch to fallback")
    func displayUpdateObservationMigratesFromNotchToFallback() async throws {
        let presenter = SpyNotchPresenter()
        let coordinator = NotchCoordinator(presenter: presenter)
        let displayUpdates = AsyncStream<[NotchDisplayDescriptor]>.makeStream()
        let recording = NotchActivity.recording(elapsed: 5, audioLevel: .silent, muted: false)

        let observation = coordinator.observeDisplayUpdates(
            displayUpdates.stream,
            activities: [recording]
        )
        var results = observation.results.makeAsyncIterator()

        let notchedDisplay = try testBuiltInNotchedDisplay()
        displayUpdates.continuation.yield([notchedDisplay])
        let notchedResult = try #require(await results.next())
        let geometry = try #require(NotchGeometry.resolve(from: notchedDisplay))
        let notchedUpdate = try #require(notchedResult.update)
        #expect(notchedResult.selection == .notch(geometry))
        #expect(notchedUpdate.activity == recording)

        displayUpdates.continuation.yield([])
        let fallbackResult = try #require(await results.next())
        #expect(fallbackResult.selection == .floatingHUD(.noNotchedDisplay))
        #expect(fallbackResult.update == nil)
        #expect(
            await presenter.commands() == [
                .acquire(geometry),
                .present(notchedUpdate),
                .release
            ])

        observation.cancel()
        displayUpdates.continuation.finish()
    }

    @Test("display provider observation uses provider update stream")
    @MainActor
    func displayProviderObservationUsesProviderUpdateStream() async throws {
        let presenter = SpyNotchPresenter()
        let coordinator = NotchCoordinator(presenter: presenter)
        let displayUpdates = AsyncStream<[NotchDisplayDescriptor]>.makeStream()
        let displayProvider = StubNotchDisplayProvider(displayUpdates: displayUpdates.stream)

        let observation = coordinator.observeDisplayProvider(
            displayProvider,
            activities: [.idleHover],
            reduceMotion: true
        )
        var results = observation.results.makeAsyncIterator()

        let notchedDisplay = try testBuiltInNotchedDisplay()
        displayUpdates.continuation.yield([notchedDisplay])
        let result = try #require(await results.next())
        let geometry = try #require(NotchGeometry.resolve(from: notchedDisplay))
        #expect(result.selection == .notch(geometry))
        #expect(result.update?.motion == .reduced)

        observation.cancel()
        displayUpdates.continuation.finish()
    }

    @Test("set expanded forwards to presenter")
    func setExpandedForwardsToPresenter() async {
        let presenter = SpyNotchPresenter()
        let coordinator = NotchCoordinator(presenter: presenter)

        await coordinator.setExpanded(true)

        #expect(await presenter.commands() == [.setExpanded(true)])
    }

}

@MainActor
private final class StubNotchDisplayProvider: NotchDisplayProvider {
    let displayUpdates: AsyncStream<[NotchDisplayDescriptor]>

    init(displayUpdates: AsyncStream<[NotchDisplayDescriptor]>) {
        self.displayUpdates = displayUpdates
    }

    func displays() -> [NotchDisplayDescriptor] {
        []
    }
}

private enum SpyNotchPresenterCommand: Equatable {
    case acquire(NotchGeometry)
    case present(NotchPresentationUpdate)
    case setExpanded(Bool)
    case release
}

private final class SpyNotchPresenter: NotchPresenter, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedCommands: [SpyNotchPresenterCommand] = []

    var interactions: AsyncStream<NotchInteraction> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func acquire(on geometry: NotchGeometry) async {
        append(.acquire(geometry))
    }

    func present(_ update: NotchPresentationUpdate) async {
        append(.present(update))
    }

    func setExpanded(_ isExpanded: Bool) async {
        append(.setExpanded(isExpanded))
    }

    func release() async {
        append(.release)
    }

    func commands() async -> [SpyNotchPresenterCommand] {
        lock.withLock {
            recordedCommands
        }
    }

    private func append(_ command: SpyNotchPresenterCommand) {
        lock.withLock {
            recordedCommands.append(command)
        }
    }
}
