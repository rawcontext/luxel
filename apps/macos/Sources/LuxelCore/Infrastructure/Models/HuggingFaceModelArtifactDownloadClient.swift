import Foundation

public struct HuggingFaceRedirectPolicy: Equatable, Sendable {
    public let maximumRedirects: Int
    public let approvedCDNSuffixes: Set<String>

    public init(
        maximumRedirects: Int = 5,
        approvedCDNSuffixes: Set<String> = ["cdn.hf.co"]
    ) {
        self.maximumRedirects = maximumRedirects
        self.approvedCDNSuffixes = approvedCDNSuffixes
    }

    public func allows(_ url: URL, isInitial: Bool) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.user == nil,
              url.password == nil,
              url.port == nil,
              let host = url.host?.lowercased()
        else {
            return false
        }
        if isInitial {
            return host == "huggingface.co"
        }
        return host == "huggingface.co"
            || approvedCDNSuffixes.contains(where: { host == $0 || host.hasSuffix(".\($0)") })
    }
}

public final class HuggingFaceModelArtifactDownloadClient: LocalModelDownloading,
                                                           @unchecked Sendable {
    public typealias Sleep = @Sendable (Duration) async throws -> Void

    private let redirectPolicy: HuggingFaceRedirectPolicy
    private let maximumAttempts: Int
    private let sleep: Sleep
    private let userAgent: String
    private let sessionConfiguration: URLSessionConfiguration?

    public init(
        redirectPolicy: HuggingFaceRedirectPolicy = HuggingFaceRedirectPolicy(),
        maximumAttempts: Int = 3,
        userAgent: String,
        sessionConfiguration: URLSessionConfiguration? = nil,
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) }
    ) {
        self.redirectPolicy = redirectPolicy
        self.maximumAttempts = max(1, maximumAttempts)
        self.userAgent = userAgent
        self.sessionConfiguration = sessionConfiguration
        self.sleep = sleep
    }

    public func download(
        _ request: LocalModelArtifactDownloadRequest,
        progress: @escaping LocalModelDownloadProgressHandler
    ) async throws {
        guard request.provider == .huggingFace else {
            throw LocalModelFailure.invalidCatalog("Unsupported model provider")
        }
        let sourceURL = try sourceURL(for: request)
        guard redirectPolicy.allows(sourceURL, isInitial: true) else {
            throw LocalModelFailure.forbiddenRedirect
        }

        var attempt = 0
        while true {
            attempt += 1
            try Task.checkCancellation()
            try? FileManager.default.removeItem(at: request.destinationURL)
            do {
                let operation = DownloadOperation(
                    sourceURL: sourceURL,
                    destinationURL: request.destinationURL,
                    expectedBytes: request.artifact.byteCount,
                    redirectPolicy: redirectPolicy,
                    userAgent: userAgent,
                    sessionConfiguration: sessionConfiguration,
                    progress: progress
                )
                try await operation.run()
                await progress(request.artifact.byteCount)
                return
            } catch is CancellationError {
                throw LocalModelFailure.canceled
            } catch let error as HTTPDownloadError {
                guard attempt < maximumAttempts, error.isRetryable else {
                    if error.statusCode == 429 {
                        throw LocalModelFailure.rateLimited
                    }
                    throw LocalModelFailure.httpStatus(error.statusCode)
                }
                try await waitBeforeRetry(
                    error.retryAfter ?? .seconds(1 << (attempt - 1))
                )
            } catch let failure as LocalModelFailure {
                throw failure
            } catch {
                guard attempt < maximumAttempts, isRetryable(error) else {
                    throw LocalModelFailure.transport(String(reflecting: type(of: error)))
                }
                try await waitBeforeRetry(.seconds(1 << (attempt - 1)))
            }
        }
    }

    private func waitBeforeRetry(_ duration: Duration) async throws {
        do {
            try await sleep(duration)
        } catch is CancellationError {
            throw LocalModelFailure.canceled
        }
    }

    private func sourceURL(for request: LocalModelArtifactDownloadRequest) throws -> URL {
        var url = URL(string: "https://huggingface.co")!
        for component in request.repository.split(separator: "/") {
            url.append(path: String(component))
        }
        url.append(path: "resolve")
        url.append(path: request.commit)
        for component in request.artifact.path.split(separator: "/") {
            url.append(path: String(component))
        }
        return url
    }

    private func isRetryable(_ error: any Error) -> Bool {
        guard let error = error as? URLError else {
            return false
        }
        return [
            .timedOut, .cannotConnectToHost, .networkConnectionLost, .dnsLookupFailed,
            .notConnectedToInternet, .internationalRoamingOff, .callIsActive,
            .dataNotAllowed, .resourceUnavailable
        ].contains(error.code)
    }
}

private final class DownloadOperation: NSObject, URLSessionDownloadDelegate,
                                       URLSessionTaskDelegate, @unchecked Sendable {
    private let sourceURL: URL
    private let destinationURL: URL
    private let expectedBytes: Int64
    private let redirectPolicy: HuggingFaceRedirectPolicy
    private let userAgent: String
    private let sessionConfiguration: URLSessionConfiguration?
    private let progress: LocalModelDownloadProgressHandler
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, any Error>?
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var completionError: (any Error)?
    private var completedDownload = false
    private var redirectCount = 0

    init(
        sourceURL: URL,
        destinationURL: URL,
        expectedBytes: Int64,
        redirectPolicy: HuggingFaceRedirectPolicy,
        userAgent: String,
        sessionConfiguration: URLSessionConfiguration?,
        progress: @escaping LocalModelDownloadProgressHandler
    ) {
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.expectedBytes = expectedBytes
        self.redirectPolicy = redirectPolicy
        self.userAgent = userAgent
        self.sessionConfiguration = sessionConfiguration
        self.progress = progress
    }

    func run() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock {
                    self.continuation = continuation
                    let configuration = sessionConfiguration ?? URLSessionConfiguration.ephemeral
                    configuration.httpCookieStorage = nil
                    configuration.urlCredentialStorage = nil
                    configuration.urlCache = nil
                    configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                    configuration.allowsConstrainedNetworkAccess = true
                    configuration.allowsExpensiveNetworkAccess = true
                    configuration.timeoutIntervalForRequest = 120
                    configuration.timeoutIntervalForResource = 24 * 60 * 60
                    let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                    var request = URLRequest(url: sourceURL)
                    request.httpMethod = "GET"
                    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
                    request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
                    let task = session.downloadTask(with: request)
                    self.session = session
                    self.task = task
                    task.resume()
                }
            }
        } onCancel: {
            self.cancel()
        }
    }

    func cancel() {
        lock.withLock { task?.cancel() }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        redirectCount += 1
        guard redirectCount <= redirectPolicy.maximumRedirects,
              let url = request.url,
              redirectPolicy.allows(url, isInitial: false)
        else {
            completionError = LocalModelFailure.forbiddenRedirect
            completionHandler(nil)
            task.cancel()
            return
        }

        var sanitized = request
        if url.host?.lowercased() != sourceURL.host?.lowercased() {
            sanitized.setValue(nil, forHTTPHeaderField: "Authorization")
            sanitized.setValue(nil, forHTTPHeaderField: "Cookie")
            sanitized.setValue(nil, forHTTPHeaderField: "Referer")
        }
        completionHandler(sanitized)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard
            challenge.protectionSpace.authenticationMethod
                == NSURLAuthenticationMethodServerTrust
        else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.performDefaultHandling, nil)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let response = downloadTask.response as? HTTPURLResponse,
              (200...299).contains(response.statusCode)
        else {
            return
        }
        if totalBytesExpectedToWrite != NSURLSessionTransferSizeUnknown,
           totalBytesWritten > expectedBytes {
            completionError = LocalModelFailure.responseTooLarge
            downloadTask.cancel()
            return
        }
        Task { await progress(totalBytesWritten) }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let response = downloadTask.response as? HTTPURLResponse else {
            completionError = LocalModelFailure.transport("Missing HTTP response")
            return
        }
        guard (200...299).contains(response.statusCode) else {
            completionError = HTTPDownloadError(
                statusCode: response.statusCode,
                retryAfter: Self.retryAfter(from: response)
            )
            return
        }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: location.path)
            let actualBytes = (attributes[.size] as? NSNumber)?.int64Value ?? -1
            guard actualBytes == expectedBytes else {
                completionError =
                    actualBytes > expectedBytes
                    ? LocalModelFailure.responseTooLarge
                    : LocalModelFailure.unexpectedByteCount(
                        expected: expectedBytes,
                        actual: actualBytes
                    )
                return
            }
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? FileManager.default.removeItem(at: destinationURL)
            try FileManager.default.moveItem(at: location, to: destinationURL)
            completedDownload = true
        } catch {
            completionError = LocalModelFailure.storageFailure("Could not store a downloaded artifact")
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        let resultError = completionError ?? error
        finish(
            resultError.map(Result.failure)
                ?? (completedDownload
                        ? .success(())
                        : .failure(LocalModelFailure.transport("Download produced no file")))
        )
    }

    private func finish(_ result: Result<Void, any Error>) {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, any Error>? in
            let continuation = self.continuation
            self.continuation = nil
            task = nil
            session?.finishTasksAndInvalidate()
            session = nil
            return continuation
        }
        continuation?.resume(with: result)
    }

    private static func retryAfter(from response: HTTPURLResponse) -> Duration? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After"),
              let seconds = Int64(value),
              (0...60).contains(seconds)
        else {
            return nil
        }
        return .seconds(seconds)
    }
}

private struct HTTPDownloadError: Error {
    let statusCode: Int
    let retryAfter: Duration?

    var isRetryable: Bool {
        statusCode == 408 || statusCode == 429 || (500...599).contains(statusCode)
    }
}
