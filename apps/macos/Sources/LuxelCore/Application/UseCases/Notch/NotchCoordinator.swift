public final class NotchCoordinator: @unchecked Sendable {
    private let presenter: any NotchPresenter

    public init(presenter: any NotchPresenter) {
        self.presenter = presenter
    }

    @MainActor
    public var interactions: AsyncStream<NotchInteraction> {
        presenter.interactions
    }

    @MainActor
    @discardableResult
    public func observeDisplayProvider(
        _ displayProvider: any NotchDisplayProvider,
        activities: [NotchActivity],
        preferences: NotchSurfacePreferences = .defaults,
        presentationState: NotchPresentationState = .collapsed,
        motion: NotchMotion = .standard,
        reduceMotion: Bool = false
    ) -> NotchCoordinatorObservation {
        observeDisplayUpdates(
            displayProvider.displayUpdates,
            activities: activities,
            preferences: preferences,
            presentationState: presentationState,
            motion: motion,
            reduceMotion: reduceMotion
        )
    }

    @discardableResult
    public func observeDisplayUpdates(
        _ displayUpdates: AsyncStream<[NotchDisplayDescriptor]>,
        activities: [NotchActivity],
        preferences: NotchSurfacePreferences = .defaults,
        presentationState: NotchPresentationState = .collapsed,
        motion: NotchMotion = .standard,
        reduceMotion: Bool = false
    ) -> NotchCoordinatorObservation {
        let (results, continuation) = AsyncStream<NotchCoordinatorResult>.makeStream()
        let task = Task { [weak self] in
            defer {
                continuation.finish()
            }

            for await displays in displayUpdates {
                guard !Task.isCancelled else {
                    break
                }

                guard let self else {
                    break
                }

                let result = await present(
                    activities: activities,
                    displays: displays,
                    preferences: preferences,
                    presentationState: presentationState,
                    motion: motion,
                    reduceMotion: reduceMotion
                )
                continuation.yield(result)
            }
        }

        return NotchCoordinatorObservation(results: results, task: task)
    }

    @discardableResult
    public func present(
        activities: [NotchActivity],
        displays: [NotchDisplayDescriptor],
        preferences: NotchSurfacePreferences = .defaults,
        presentationState: NotchPresentationState = .collapsed,
        motion: NotchMotion = .standard,
        reduceMotion: Bool = false
    ) async -> NotchCoordinatorResult {
        let selection = RecordingSurfaceSelector.select(
            from: displays,
            preferences: preferences
        )
        guard case .notch(let geometry) = selection else {
            await presenter.release()
            return NotchCoordinatorResult(selection: selection, update: nil)
        }

        let activity = NotchActivityResolver.resolve(activities)
        let viewModel = NotchActivityPresentation.viewModel(for: activity)
        let update = NotchPresentationUpdate(
            geometry: geometry,
            activity: activity,
            presentationState: presentationState,
            viewModel: viewModel,
            motion: motion.variant(reduceMotion: reduceMotion)
        )

        await presenter.acquire(on: geometry)
        await presenter.present(update)

        return NotchCoordinatorResult(selection: selection, update: update)
    }

    public func setExpanded(_ isExpanded: Bool) async {
        await presenter.setExpanded(isExpanded)
    }
}

public final class NotchCoordinatorObservation: Sendable {
    public let results: AsyncStream<NotchCoordinatorResult>
    private let task: Task<Void, Never>

    init(
        results: AsyncStream<NotchCoordinatorResult>,
        task: Task<Void, Never>
    ) {
        self.results = results
        self.task = task
    }

    public func cancel() {
        task.cancel()
    }

    deinit {
        task.cancel()
    }
}

public struct NotchCoordinatorResult: Equatable, Sendable {
    public let selection: RecordingSurfaceSelection
    public let update: NotchPresentationUpdate?

    public init(selection: RecordingSurfaceSelection, update: NotchPresentationUpdate?) {
        self.selection = selection
        self.update = update
    }
}
