@MainActor
public protocol NotchDisplayProvider: AnyObject {
    func displays() -> [NotchDisplayDescriptor]
    var displayUpdates: AsyncStream<[NotchDisplayDescriptor]> { get }
}
