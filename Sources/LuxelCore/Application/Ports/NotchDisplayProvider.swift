@MainActor
public protocol NotchDisplayProvider: AnyObject {
    func displays() -> [NotchDisplayDescriptor]
}
