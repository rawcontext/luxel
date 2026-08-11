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

    public static func isTestFlightBuild(
        receiptURL: URL?,
        betaReportsActive: Bool
    ) -> Bool {
        betaReportsActive && receiptURL?.lastPathComponent == "sandboxReceipt"
    }

    public static func isTestFlightBuild(appBundleURL: URL) -> Bool {
        isTestFlightBuild(
            receiptURL: appStoreReceiptURL(in: appBundleURL),
            betaReportsActive: betaReportsActiveEntitlement(
                at: Bundle(url: appBundleURL)?.executableURL
            )
        )
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
    static func appStoreReceiptURL(in appBundleURL: URL) -> URL? {
        let receiptDirectoryURL = appBundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("_MASReceipt", isDirectory: true)
        let sandboxReceiptURL = receiptDirectoryURL.appendingPathComponent("sandboxReceipt")

        if FileManager.default.fileExists(atPath: sandboxReceiptURL.path) {
            return sandboxReceiptURL
        }

        let productionReceiptURL = receiptDirectoryURL.appendingPathComponent("receipt")
        if FileManager.default.fileExists(atPath: productionReceiptURL.path) {
            return productionReceiptURL
        }

        return nil
    }

    @usableFromInline
    static func betaReportsActiveEntitlement(at executableURL: URL?) -> Bool {
        guard let executableURL else {
            return false
        }

        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(executableURL as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode
        else {
            return false
        }

        let appStoreRequirementText = #"""
            anchor apple generic
            and identifier "com.rawcontext.luxel"
            and certificate leaf[field.1.2.840.113635.100.6.1.9] exists
        """#
        var appStoreRequirement: SecRequirement?
        guard SecRequirementCreateWithString(
            appStoreRequirementText as CFString,
            [],
            &appStoreRequirement
        ) == errSecSuccess,
        let appStoreRequirement,
        SecStaticCodeCheckValidity(staticCode, [], appStoreRequirement) == errSecSuccess
        else {
            return false
        }

        var signingInformation: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInformation
        ) == errSecSuccess,
        let signingInformation = signingInformation as? [String: Any],
        let entitlements = signingInformation[kSecCodeInfoEntitlementsDict as String]
            as? [String: Any]
        else {
            return false
        }

        return entitlements["beta-reports-active"] as? Bool == true
    }
}
