@MainActor
public protocol PointerDisplayProvider: AnyObject {
    func displayIDContainingPointer() -> DisplayID?
}
