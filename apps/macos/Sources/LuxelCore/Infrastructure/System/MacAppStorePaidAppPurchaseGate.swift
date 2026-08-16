import Foundation
import Security
import StoreKit

public struct MacAppStorePaidAppPurchaseGate: PurchaseGate {
    public enum AppTransactionEntitlement: Sendable {
        case verified(bundleID: String)
        case unverified
        case unavailable
    }

    private let isTestFlightBuild: @Sendable () -> Bool
    private let currentBundleID: @Sendable () -> String?
    private let appTransactionEntitlement: @Sendable () async -> AppTransactionEntitlement

    public init(
        isTestFlightBuild: @escaping @Sendable () -> Bool = {
            Self.isTestFlightBuild(appBundleURL: Bundle.main.bundleURL)
        },
        currentBundleID: @escaping @Sendable () -> String? = {
            Bundle.main.bundleIdentifier
        },
        appTransactionEntitlement: @escaping @Sendable () async -> AppTransactionEntitlement = {
            await Self.currentAppTransactionEntitlement()
        }
    ) {
        self.isTestFlightBuild = isTestFlightBuild
        self.currentBundleID = currentBundleID
        self.appTransactionEntitlement = appTransactionEntitlement
    }

    public func isEntitled() async -> Bool {
        if isTestFlightBuild() {
            return true
        }

        guard let currentBundleID = currentBundleID() else {
            return false
        }

        switch await appTransactionEntitlement() {
        case .verified(let appTransactionBundleID):
            return appTransactionBundleID == currentBundleID
        case .unverified, .unavailable:
            return false
        }
    }

    public static func isTestFlightBuild(appBundleURL: URL) -> Bool {
        hasTestFlightSignature(at: Bundle(url: appBundleURL)?.executableURL)
    }

    public static func enclosingAppBundleURL(containing executableURL: URL) -> URL? {
        var candidateURL = executableURL
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()

        while candidateURL.path != "/" {
            if candidateURL.pathExtension == "app" {
                return candidateURL
            }
            candidateURL.deleteLastPathComponent()
        }

        return nil
    }

    public func entitlementChanges() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let task = Task {
                continuation.yield(await isEntitled())
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    @usableFromInline
    static func currentAppTransactionEntitlement() async -> AppTransactionEntitlement {
        do {
            switch try await AppTransaction.shared {
            case .verified(let appTransaction):
                return .verified(bundleID: appTransaction.bundleID)
            case .unverified:
                return .unverified
            }
        } catch {
            return .unavailable
        }
    }

    @usableFromInline
    static let testFlightCodeRequirement = #"""
        anchor apple generic
        and identifier "com.rawcontext.luxel"
        and certificate 1[field.1.2.840.113635.100.6.2.1] exists
        and certificate leaf[field.1.2.840.113635.100.6.1.25.1] exists
    """#

    @usableFromInline
    static func hasTestFlightSignature(at executableURL: URL?) -> Bool {
        guard let executableURL else {
            return false
        }

        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(executableURL as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode
        else {
            return false
        }

        var testFlightRequirement: SecRequirement?
        guard SecRequirementCreateWithString(
            testFlightCodeRequirement as CFString,
            [],
            &testFlightRequirement
        ) == errSecSuccess,
        let testFlightRequirement,
        SecStaticCodeCheckValidity(
            staticCode,
            SecCSFlags(rawValue: kSecCSBasicValidateOnly),
            testFlightRequirement
        ) == errSecSuccess
        else {
            return false
        }

        return true
    }
}
