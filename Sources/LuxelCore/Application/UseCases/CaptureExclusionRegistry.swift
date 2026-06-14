import Foundation

public actor CaptureExclusionRegistry {
    private var registrations: [UUID: Set<UInt32>] = [:]

    public init() {}

    @discardableResult
    public func register(windowID: UInt32, registrationID: UUID = UUID()) -> UUID {
        register(windowIDs: [windowID], registrationID: registrationID)
    }

    @discardableResult
    public func register(windowIDs: [UInt32], registrationID: UUID = UUID()) -> UUID {
        let windowIDs = Set(windowIDs)

        if windowIDs.isEmpty {
            registrations.removeValue(forKey: registrationID)
        } else {
            registrations[registrationID] = windowIDs
        }

        return registrationID
    }

    public func unregister(_ registrationID: UUID) {
        registrations.removeValue(forKey: registrationID)
    }

    public func excludedWindowIDs() -> [UInt32] {
        Array(Set(registrations.values.flatMap(\.self))).sorted()
    }
}
