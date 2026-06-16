public protocol ErrorReporter {
    @MainActor func record(_ error: any Error, context: String)
}

public struct NoopErrorReporter: ErrorReporter {
    public init() {}

    public func record(_ error: any Error, context: String) {}
}
