import Foundation
import Security

public struct CommandLineCredentialStore: Sendable {
    private let service: String

    public init(service: String = "media.luxel.command-line.app") {
        self.service = service
    }

    public func secret(clientID: UUID) -> Data? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(
            [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: clientID.uuidString.lowercased(),
                kSecReturnData: true,
                kSecMatchLimit: kSecMatchLimitOne
            ] as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    public func saveSecret(_ secret: Data, clientID: UUID) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: clientID.uuidString.lowercased()
        ]
        let status = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData: secret] as CFDictionary
        )
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData] = secret
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw CommandLineCredentialStoreError.keychain(addStatus)
            }
            return
        }
        guard status == errSecSuccess else {
            throw CommandLineCredentialStoreError.keychain(status)
        }
    }

    public func removeSecret(clientID: UUID) {
        SecItemDelete(
            [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: clientID.uuidString.lowercased()
            ] as CFDictionary)
    }

    public func makeSecret() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw CommandLineCredentialStoreError.keychain(status)
        }
        return Data(bytes)
    }
}

public enum CommandLineCredentialStoreError: Error, Equatable, Sendable {
    case keychain(OSStatus)
}
