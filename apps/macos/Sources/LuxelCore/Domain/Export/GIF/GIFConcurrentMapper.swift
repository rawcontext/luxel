import Dispatch
import Foundation

enum GIFConcurrentMapper {
    static func map<Output>(
        count: Int,
        _ transform: @Sendable (Int) throws -> Output
    ) throws -> [Output] {
        guard count > 0 else {
            return []
        }

        let results = ConcurrentResultCells<Output>(count: count)
        DispatchQueue.concurrentPerform(iterations: count) { index in
            results.store(Result { try transform(index) }, at: index)
        }

        return try results.finalizedOutputs()
    }
}

private final class ConcurrentResultCells<Output>: @unchecked Sendable {
    private let cells: UnsafeMutablePointer<Result<Output, any Error>?>
    private let count: Int

    init(count: Int) {
        self.count = count
        cells = .allocate(capacity: count)
        cells.initialize(repeating: nil, count: count)
    }

    deinit {
        cells.deinitialize(count: count)
        cells.deallocate()
    }

    func store(_ result: Result<Output, any Error>, at index: Int) {
        cells[index] = result
    }

    func finalizedOutputs() throws -> [Output] {
        try (0..<count).compactMap { index in
            try cells[index]?.get()
        }
    }
}
