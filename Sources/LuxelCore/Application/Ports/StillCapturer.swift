public protocol StillCapturer: Sendable {
    func capture(_ request: ScreenshotRequest) async throws -> ImageData
}
