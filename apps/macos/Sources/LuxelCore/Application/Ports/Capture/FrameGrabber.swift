public protocol FrameGrabber: Sendable {
    func grab(_ request: FrameGrabRequest) async throws -> FrameGrabImageData
}
