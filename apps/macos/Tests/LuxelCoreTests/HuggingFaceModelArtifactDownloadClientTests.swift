import CryptoKit
import Foundation
import LuxelCore
import Testing

@Suite("Hugging Face model transport", .serialized)
struct HuggingFaceTransportTests {
    @Test("downloads the exact commit URL to a file and reports bytes")
    func downloadsExactCommitURL() async throws {
        let data = Data("fixture bytes".utf8)
        let capture = RequestCapture()
        ModelDownloadURLProtocol.storage.handler = { request in
            capture.record(request)
            return .response(status: 200, headers: [:], data: data)
        }
        let destination = temporaryDestination()
        let progress = ProgressCapture()
        let client = makeClient()

        try await client.download(
            request(destination: destination, data: data)
        ) { bytes in
            await progress.append(bytes)
        }

        #expect(try Data(contentsOf: destination) == data)
        let request = try #require(capture.request)
        #expect(
            request.url?.absoluteString
                == "https://huggingface.co/Fixture/model/resolve/"
                + "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/nested/payload.bin"
        )
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "LuxelTests/1")
        #expect((await progress.values).last == Int64(data.count))
    }

    @Test("retries bounded transient statuses but not permanent 4xx")
    func retriesOnlyTransientStatuses() async throws {
        let data = Data("fixture".utf8)
        let transientCount = Counter()
        ModelDownloadURLProtocol.storage.handler = { _ in
            let attempt = transientCount.increment()
            return .response(status: attempt == 1 ? 500 : 200, headers: [:], data: data)
        }
        try await makeClient().download(
            request(destination: temporaryDestination(), data: data),
            progress: { _ in }
        )
        #expect(transientCount.value == 2)

        let permanentCount = Counter()
        ModelDownloadURLProtocol.storage.handler = { _ in
            _ = permanentCount.increment()
            return .response(status: 404, headers: [:], data: Data())
        }
        await #expect(throws: LocalModelFailure.httpStatus(404)) {
            try await makeClient().download(
                request(destination: temporaryDestination(), data: data),
                progress: { _ in }
            )
        }
        #expect(permanentCount.value == 1)

        let rateLimitCount = Counter()
        ModelDownloadURLProtocol.storage.handler = { _ in
            _ = rateLimitCount.increment()
            return .response(status: 429, headers: ["Retry-After": "1"], data: Data())
        }
        await #expect(throws: LocalModelFailure.rateLimited) {
            try await makeClient().download(
                request(destination: temporaryDestination(), data: data),
                progress: { _ in }
            )
        }
        #expect(rateLimitCount.value == 3)
    }

    @Test("retries transient URL errors with a strict attempt bound")
    func retriesTransientURLErrors() async throws {
        let data = Data("fixture".utf8)
        let count = Counter()
        ModelDownloadURLProtocol.storage.handler = { _ in
            let attempt = count.increment()
            return attempt == 1
                ? .failure(URLError(.networkConnectionLost))
                : .response(status: 200, headers: [:], data: data)
        }

        try await makeClient().download(
            request(destination: temporaryDestination(), data: data),
            progress: { _ in }
        )
        #expect(count.value == 2)

        let boundedCount = Counter()
        ModelDownloadURLProtocol.storage.handler = { _ in
            _ = boundedCount.increment()
            return .failure(URLError(.timedOut))
        }
        await #expect(throws: LocalModelFailure.self) {
            try await makeClient().download(
                request(destination: temporaryDestination(), data: data),
                progress: { _ in }
            )
        }
        #expect(boundedCount.value == 3)
    }

    @Test("cancellation interrupts retry backoff")
    func cancellationInterruptsRetryBackoff() async throws {
        let data = Data("fixture".utf8)
        let gate = RetrySleepGate()
        ModelDownloadURLProtocol.storage.handler = { _ in
            .response(status: 500, headers: [:], data: Data())
        }
        let client = makeClient(sleep: { _ in
            await gate.started()
            try await Task.sleep(for: .seconds(3_600))
        })
        let task = Task {
            try await client.download(
                request(destination: temporaryDestination(), data: data),
                progress: { _ in }
            )
        }
        await gate.waitUntilStarted()
        task.cancel()

        await #expect(throws: LocalModelFailure.canceled) {
            try await task.value
        }
    }

    @Test("redirect policy permits reviewed CDN hosts and rejects unsafe destinations")
    func redirectPolicyIsFailClosed() {
        let policy = HuggingFaceRedirectPolicy()
        #expect(policy.allows(URL(string: "https://huggingface.co/a/b")!, isInitial: true))
        #expect(policy.allows(URL(string: "https://us.aws.cdn.hf.co/xet/file")!, isInitial: false))
        #expect(!policy.allows(URL(string: "http://huggingface.co/a")!, isInitial: true))
        #expect(!policy.allows(URL(string: "https://user@huggingface.co/a")!, isInitial: true))
        #expect(!policy.allows(URL(string: "https://huggingface.co:444/a")!, isInitial: true))
        #expect(!policy.allows(URL(string: "https://evil.example/a")!, isInitial: false))
        #expect(!policy.allows(URL(string: "https://127.0.0.1/a")!, isInitial: false))
    }

    @Test("oversized responses fail without promotion")
    func oversizedResponseFails() async {
        let expected = Data("small".utf8)
        ModelDownloadURLProtocol.storage.handler = { _ in
            .response(status: 200, headers: [:], data: Data(repeating: 1, count: 100))
        }
        await #expect(throws: LocalModelFailure.responseTooLarge) {
            try await makeClient().download(
                request(destination: temporaryDestination(), data: expected),
                progress: { _ in }
            )
        }
    }

    @Test("undersized responses fail exact byte validation")
    func undersizedResponseFails() async {
        let expected = Data("expected".utf8)
        ModelDownloadURLProtocol.storage.handler = { _ in
            .response(status: 200, headers: [:], data: Data("short".utf8))
        }
        await #expect(
            throws: LocalModelFailure.unexpectedByteCount(
                expected: Int64(expected.count),
                actual: 5
            )
        ) {
            try await makeClient().download(
                request(destination: temporaryDestination(), data: expected),
                progress: { _ in }
            )
        }
    }

    private func makeClient(
        sleep: @escaping HuggingFaceModelArtifactDownloadClient.Sleep = { _ in }
    ) -> HuggingFaceModelArtifactDownloadClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ModelDownloadURLProtocol.self]
        return HuggingFaceModelArtifactDownloadClient(
            maximumAttempts: 3,
            userAgent: "LuxelTests/1",
            sessionConfiguration: configuration,
            sleep: sleep
        )
    }

    private func request(destination: URL, data: Data) -> LocalModelArtifactDownloadRequest {
        LocalModelArtifactDownloadRequest(
            provider: .huggingFace,
            repository: "Fixture/model",
            commit: String(repeating: "a", count: 40),
            artifact: LocalModelArtifact(
                path: "nested/payload.bin",
                byteCount: Int64(data.count),
                sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
                kind: .auxiliaryData
            ),
            destinationURL: destination
        )
    }

    private func temporaryDestination() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "LuxelTransportTests-\(UUID().uuidString)")
            .appending(path: "payload.bin")
    }
}

private final class RequestCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequest: URLRequest?

    var request: URLRequest? { lock.withLock { storedRequest } }
    func record(_ request: URLRequest) { lock.withLock { storedRequest = request } }
}

private actor ProgressCapture {
    private(set) var values: [Int64] = []
    func append(_ value: Int64) { values.append(value) }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() -> Int {
        lock.withLock {
            count += 1
            return count
        }
    }
}

private enum ModelDownloadURLProtocolResult {
    case response(status: Int, headers: [String: String], data: Data)
    case failure(URLError)
}

private final class ModelDownloadURLProtocolStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var storedHandler: (@Sendable (URLRequest) -> ModelDownloadURLProtocolResult)?

    var handler: (@Sendable (URLRequest) -> ModelDownloadURLProtocolResult)? {
        get { lock.withLock { storedHandler } }
        set { lock.withLock { storedHandler = newValue } }
    }
}

private final class ModelDownloadURLProtocol: URLProtocol, @unchecked Sendable {
    static let storage = ModelDownloadURLProtocolStorage()

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let handler = Self.storage.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        switch handler(request) {
        case .response(let status, let headers, let data):
            let response = HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private actor RetrySleepGate {
    private var hasStarted = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func started() {
        hasStarted = true
        continuations.forEach { $0.resume() }
        continuations.removeAll()
    }

    func waitUntilStarted() async {
        if hasStarted { return }
        await withCheckedContinuation { continuations.append($0) }
    }
}
