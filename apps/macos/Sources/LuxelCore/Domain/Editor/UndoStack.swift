public struct UndoStack<State: Equatable & Sendable>: Equatable, Sendable {
    public private(set) var current: State
    public let capacity: Int

    private var undoStates: [State]
    private var redoStates: [State]
    private var coalescingToken: String?

    public init(initialState: State, capacity: Int = 100) {
        self.current = initialState
        self.capacity = max(1, capacity)
        self.undoStates = []
        self.redoStates = []
        self.coalescingToken = nil
    }

    public var canUndo: Bool {
        !undoStates.isEmpty
    }

    public var canRedo: Bool {
        !redoStates.isEmpty
    }

    public var undoCount: Int {
        undoStates.count
    }

    public var redoCount: Int {
        redoStates.count
    }

    public mutating func push(_ state: State, coalescingToken token: String? = nil) {
        guard state != current else {
            return
        }

        if let token, token == coalescingToken, canUndo {
            current = state
            redoStates = []
            return
        }

        undoStates.append(current)
        if undoStates.count > capacity {
            undoStates.removeFirst(undoStates.count - capacity)
        }

        current = state
        redoStates = []
        coalescingToken = token
    }

    @discardableResult
    public mutating func undo() -> State? {
        guard let state = undoStates.popLast() else {
            return nil
        }

        redoStates.append(current)
        current = state
        coalescingToken = nil
        return current
    }

    @discardableResult
    public mutating func redo() -> State? {
        guard let state = redoStates.popLast() else {
            return nil
        }

        undoStates.append(current)
        if undoStates.count > capacity {
            undoStates.removeFirst(undoStates.count - capacity)
        }

        current = state
        coalescingToken = nil
        return current
    }
}
