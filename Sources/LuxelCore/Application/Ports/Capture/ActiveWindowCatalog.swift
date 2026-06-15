@MainActor
public protocol ActiveWindowCatalog: AnyObject {
    func orderedActiveWindowIDs() -> [UInt32]
}
