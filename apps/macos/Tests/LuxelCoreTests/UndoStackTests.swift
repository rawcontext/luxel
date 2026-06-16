import LuxelCore
import Testing

@Suite("Undo stack")
struct UndoStackTests {
    @Test("push records undo states and undo records redo states")
    func pushUndoRedo() {
        var stack = UndoStack(initialState: "initial")

        stack.push("first")
        stack.push("second")

        #expect(stack.current == "second")
        #expect(stack.canUndo)
        #expect(!stack.canRedo)
        #expect(stack.undo() == "first")
        #expect(stack.current == "first")
        #expect(stack.canRedo)
        #expect(stack.undo() == "initial")
        #expect(stack.undo() == nil)
        #expect(stack.redo() == "first")
        #expect(stack.redo() == "second")
        #expect(stack.redo() == nil)
    }

    @Test("new pushes clear redo history")
    func newPushClearsRedoHistory() {
        var stack = UndoStack(initialState: 0)

        stack.push(1)
        stack.push(2)
        stack.undo()
        stack.push(3)

        #expect(stack.current == 3)
        #expect(!stack.canRedo)
        #expect(stack.undo() == 1)
    }

    @Test("duplicate pushes are ignored")
    func duplicatePushesAreIgnored() {
        var stack = UndoStack(initialState: 0)

        stack.push(1)
        stack.push(1)

        #expect(stack.undoCount == 1)
        #expect(stack.undo() == 0)
    }

    @Test("capacity limits undo history")
    func capacityLimitsUndoHistory() {
        var stack = UndoStack(initialState: 0, capacity: 3)

        stack.push(1)
        stack.push(2)
        stack.push(3)
        stack.push(4)

        #expect(stack.undoCount == 3)
        #expect(stack.undo() == 3)
        #expect(stack.undo() == 2)
        #expect(stack.undo() == 1)
        #expect(stack.undo() == nil)
    }

    @Test("coalescing token merges consecutive pushes")
    func coalescingTokenMergesConsecutivePushes() {
        var stack = UndoStack(initialState: 0)

        stack.push(1, coalescingToken: "trim-start")
        stack.push(2, coalescingToken: "trim-start")
        stack.push(3, coalescingToken: "trim-start")

        #expect(stack.current == 3)
        #expect(stack.undoCount == 1)
        #expect(stack.undo() == 0)
    }

    @Test("different coalescing tokens create separate undo steps")
    func differentCoalescingTokensCreateSeparateUndoSteps() {
        var stack = UndoStack(initialState: 0)

        stack.push(1, coalescingToken: "trim-start")
        stack.push(2, coalescingToken: "trim-end")

        #expect(stack.undoCount == 2)
        #expect(stack.undo() == 1)
    }
}
