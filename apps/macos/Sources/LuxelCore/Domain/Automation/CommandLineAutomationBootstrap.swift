import CryptoKit
import Foundation

public enum CommandLineAutomationBootstrapAction: String, Equatable, Sendable {
    case pair
    case run
}

public struct CommandLineAutomationBootstrapInvocation: Equatable, Sendable {
    public let action: CommandLineAutomationBootstrapAction
    public let requestID: UUID
    public let endpoint: URL
    public let clientName: String?
    public let clientID: UUID?
    public let requestDigest: String?
    public let timestamp: Int64?
    public let nonce: String?
    public let signature: String?
    public let protocolVersion: Int

    public init(
        action: CommandLineAutomationBootstrapAction,
        requestID: UUID,
        endpoint: URL,
        clientName: String? = nil,
        clientID: UUID? = nil,
        requestDigest: String? = nil,
        timestamp: Int64? = nil,
        nonce: String? = nil,
        signature: String? = nil,
        protocolVersion: Int = CommandLineAutomationProtocol.version
    ) {
        self.action = action
        self.requestID = requestID
        self.endpoint = endpoint
        self.clientName = clientName
        self.clientID = clientID
        self.requestDigest = requestDigest
        self.timestamp = timestamp
        self.nonce = nonce
        self.signature = signature
        self.protocolVersion = protocolVersion
    }

    public func withSignature(_ signature: String) -> Self {
        Self(
            action: action,
            requestID: requestID,
            endpoint: endpoint,
            clientName: clientName,
            clientID: clientID,
            requestDigest: requestDigest,
            timestamp: timestamp,
            nonce: nonce,
            signature: signature,
            protocolVersion: protocolVersion
        )
    }

    public func url(scheme: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "cli"
        components.path = "/\(action.rawValue)"
        var items = [
            URLQueryItem(name: "protocolVersion", value: String(protocolVersion)),
            URLQueryItem(name: "requestID", value: requestID.uuidString.lowercased()),
            URLQueryItem(name: "endpoint", value: endpoint.absoluteString)
        ]
        if let clientName { items.append(URLQueryItem(name: "clientName", value: clientName)) }
        if let clientID {
            items.append(URLQueryItem(name: "clientID", value: clientID.uuidString.lowercased()))
        }
        if let requestDigest { items.append(URLQueryItem(name: "requestDigest", value: requestDigest)) }
        if let timestamp { items.append(URLQueryItem(name: "timestamp", value: String(timestamp))) }
        if let nonce { items.append(URLQueryItem(name: "nonce", value: nonce)) }
        if let signature { items.append(URLQueryItem(name: "signature", value: signature)) }
        components.queryItems = items
        return components.url!
    }

    fileprivate var canonicalAuthenticationData: Data? {
        guard action == .run,
            let clientID,
            let requestDigest,
            let timestamp,
            let nonce
        else { return nil }
        return Data(
            [
                String(protocolVersion),
                requestID.uuidString.lowercased(),
                clientID.uuidString.lowercased(),
                endpoint.absoluteString,
                requestDigest,
                String(timestamp),
                nonce
            ].joined(separator: "\n").utf8
        )
    }
}

public enum CommandLineAutomationBootstrapParser {
    public static func parse(
        _ url: URL,
        expectedScheme: String
    ) throws -> CommandLineAutomationBootstrapInvocation {
        guard url.scheme?.lowercased() == expectedScheme.lowercased(), url.host == "cli" else {
            throw CommandLineAutomationBootstrapError.invalidURL
        }
        guard
            let action = CommandLineAutomationBootstrapAction(
                rawValue: url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            )
        else {
            throw CommandLineAutomationBootstrapError.invalidURL
        }
        let query = try uniqueQuery(url)
        let version = Int(query["protocolVersion"] ?? "1") ?? 0
        guard version == CommandLineAutomationProtocol.version else {
            throw CommandLineAutomationBootstrapError.unsupportedProtocolVersion(version)
        }
        guard let requestID = UUID(uuidString: try required("requestID", in: query)),
            let endpoint = URL(string: try required("endpoint", in: query))
        else {
            throw CommandLineAutomationBootstrapError.invalidURL
        }
        try validateLoopback(endpoint)

        switch action {
        case .pair:
            let clientName = try required("clientName", in: query)
            guard !clientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CommandLineAutomationBootstrapError.invalidURL
            }
            return CommandLineAutomationBootstrapInvocation(
                action: action,
                requestID: requestID,
                endpoint: endpoint,
                clientName: clientName,
                protocolVersion: version
            )
        case .run:
            guard let clientID = UUID(uuidString: try required("clientID", in: query)),
                let timestamp = Int64(try required("timestamp", in: query))
            else {
                throw CommandLineAutomationBootstrapError.invalidURL
            }
            let digest = try required("requestDigest", in: query)
            let nonce = try required("nonce", in: query)
            let signature = try required("signature", in: query)
            guard digest.count == 64,
                digest.allSatisfy(\.isHexDigit),
                (16...128).contains(nonce.count),
                signature.count == 64,
                signature.allSatisfy(\.isHexDigit)
            else {
                throw CommandLineAutomationBootstrapError.invalidURL
            }
            return CommandLineAutomationBootstrapInvocation(
                action: action,
                requestID: requestID,
                endpoint: endpoint,
                clientID: clientID,
                requestDigest: digest.lowercased(),
                timestamp: timestamp,
                nonce: nonce,
                signature: signature.lowercased(),
                protocolVersion: version
            )
        }
    }

    private static func uniqueQuery(_ url: URL) throws -> [String: String] {
        guard
            let percentEncodedQuery = URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
            )?.percentEncodedQuery
        else {
            return [:]
        }
        var values: [String: String] = [:]
        for pair in percentEncodedQuery.split(separator: "&", omittingEmptySubsequences: false) {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2,
                let name = formQueryValue(String(parts[0])),
                let value = formQueryValue(String(parts[1])),
                values[name] == nil
            else {
                throw CommandLineAutomationBootstrapError.invalidURL
            }
            values[name] = value
        }
        return values
    }

    private static func formQueryValue(_ value: String) -> String? {
        value.replacingOccurrences(of: "+", with: "%20").removingPercentEncoding
    }

    private static func required(_ name: String, in query: [String: String]) throws -> String {
        guard let value = query[name], !value.isEmpty else {
            throw CommandLineAutomationBootstrapError.invalidURL
        }
        return value
    }

    public static func validateLoopback(_ endpoint: URL) throws {
        let pathComponents = endpoint.pathComponents
        let sessionToken = pathComponents.count == 3 ? pathComponents[2] : ""
        guard endpoint.scheme == "http",
            endpoint.user == nil,
            endpoint.password == nil,
            endpoint.port != nil,
            endpoint.query == nil,
            endpoint.fragment == nil,
            endpoint.host == "127.0.0.1" || endpoint.host == "::1",
            pathComponents.count == 3,
            pathComponents[1] == "session",
            (32...128).contains(sessionToken.count),
            sessionToken.allSatisfy(\.isHexDigit)
        else {
            throw CommandLineAutomationBootstrapError.nonLoopbackEndpoint
        }
    }
}

public enum CommandLineAutomationAuthentication {
    public static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).hexString
    }

    public static func signature(
        for invocation: CommandLineAutomationBootstrapInvocation,
        secret: Data
    ) -> String {
        guard let canonical = invocation.canonicalAuthenticationData else { return "" }
        return HMAC<SHA256>.authenticationCode(
            for: canonical,
            using: SymmetricKey(data: secret)
        ).hexString
    }

    public static func authenticate(
        _ invocation: CommandLineAutomationBootstrapInvocation,
        secret: Data
    ) -> Bool {
        guard let signature = invocation.signature else { return false }
        let expected = self.signature(for: invocation.withSignature(""), secret: secret)
        return Data(expected.utf8).constantTimeEquals(Data(signature.utf8))
    }
}

public enum CommandLineAutomationBootstrapError: Error, Equatable, Sendable {
    case invalidURL
    case nonLoopbackEndpoint
    case unsupportedProtocolVersion(Int)
}

extension Sequence where Element == UInt8 {
    fileprivate var hexString: String { map { String(format: "%02x", $0) }.joined() }
}

extension Data {
    fileprivate func constantTimeEquals(_ other: Data) -> Bool {
        guard count == other.count else { return false }
        var difference: UInt8 = 0
        for (lhs, rhs) in zip(self, other) { difference |= lhs ^ rhs }
        return difference == 0
    }
}
