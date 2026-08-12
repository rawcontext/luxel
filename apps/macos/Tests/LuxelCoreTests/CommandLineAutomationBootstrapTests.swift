import Foundation
import Testing

@testable import LuxelCore

struct CommandLineAutomationBootstrapTests {
    private struct AuthenticationFixture: Decodable {
        let requestID: UUID
        let clientID: UUID
        let endpoint: URL
        let requestDigest: String
        let timestamp: Int64
        let nonce: String
        let secret: String
        let signature: String
    }

    @Test("Pairing URLs accept only loopback callback endpoints")
    func pairingURL() throws {
        let request = "luxel://cli/pair?requestID=00000000-0000-0000-0000-000000000001&clientName=Terminal"
        let callback = "http%3A%2F%2F127.0.0.1%3A43123%2Fsession%2F0123456789abcdef0123456789abcdef"
        let url = try #require(URL(string: "\(request)&endpoint=\(callback)"))
        let invocation = try CommandLineAutomationBootstrapParser.parse(
            url,
            expectedScheme: "luxel"
        )
        #expect(invocation.action == .pair)
        #expect(invocation.clientName == "Terminal")
        #expect(invocation.endpoint.port == 43123)
    }

    @Test("Pairing URLs decode form-encoded client names")
    func pairingClientName() throws {
        let request = "luxel://cli/pair?requestID=00000000-0000-0000-0000-000000000001&clientName=Luxel+CLI%2BE2E"
        let callback = "http%3A%2F%2F127.0.0.1%3A43123%2Fsession%2F0123456789abcdef0123456789abcdef"
        let url = try #require(URL(string: "\(request)&endpoint=\(callback)"))
        let invocation = try CommandLineAutomationBootstrapParser.parse(
            url,
            expectedScheme: "luxel"
        )

        #expect(invocation.clientName == "Luxel CLI+E2E")
    }

    @Test("Run URLs round-trip authentication")
    func authenticatedRunURL() throws {
        let fixtureURL = try #require(
            Bundle.module.url(forResource: "authentication.json", withExtension: nil)
        )
        let fixture = try JSONDecoder().decode(
            AuthenticationFixture.self,
            from: Data(contentsOf: fixtureURL)
        )
        let invocation = CommandLineAutomationBootstrapInvocation(
            action: .run,
            requestID: fixture.requestID,
            endpoint: fixture.endpoint,
            clientID: fixture.clientID,
            requestDigest: fixture.requestDigest,
            timestamp: fixture.timestamp,
            nonce: fixture.nonce,
            signature: ""
        )
        let secret = Data(fixture.secret.utf8)
        let signature = CommandLineAutomationAuthentication.signature(
            for: invocation,
            secret: secret
        )
        #expect(signature == fixture.signature)
        let signed = invocation.withSignature(signature)
        let url = signed.url(scheme: "luxel")
        let parsed = try CommandLineAutomationBootstrapParser.parse(url, expectedScheme: "luxel")
        #expect(parsed == signed)
        #expect(CommandLineAutomationAuthentication.authenticate(parsed, secret: secret))
    }

    @Test("Remote endpoints are rejected")
    func rejectsRemoteEndpoint() throws {
        let url = try #require(URL(string:
                                    "luxel://cli/pair?requestID=00000000-0000-0000-0000-000000000001&clientName=Terminal&endpoint=https%3A%2F%2Fexample.com%2Fsession"
        ))
        #expect(throws: CommandLineAutomationBootstrapError.nonLoopbackEndpoint) {
            try CommandLineAutomationBootstrapParser.parse(url, expectedScheme: "luxel")
        }
    }

    @Test("Predictable callback routes are rejected")
    func rejectsPredictableCallbackRoute() throws {
        let url = try #require(URL(string:
                                    "luxel://cli/pair?requestID=00000000-0000-0000-0000-000000000001&clientName=Terminal&endpoint=http%3A%2F%2F127.0.0.1%3A43123%2Fsession"
        ))
        #expect(throws: CommandLineAutomationBootstrapError.nonLoopbackEndpoint) {
            try CommandLineAutomationBootstrapParser.parse(url, expectedScheme: "luxel")
        }
    }

    @Test("Request digests use lowercase SHA-256")
    func requestDigest() {
        #expect(
            CommandLineAutomationAuthentication.digest(Data("hello".utf8))
                == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        )
    }
}
