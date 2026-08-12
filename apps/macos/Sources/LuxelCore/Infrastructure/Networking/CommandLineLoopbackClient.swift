import Foundation

public struct CommandLineLoopbackClient: Sendable {
    private let maximumBodySize = 4 * 1_024 * 1_024

    public init() {}

    public func fetchRequest(from endpoint: URL) async throws -> Data {
        try CommandLineAutomationBootstrapParser.validateLoopback(endpoint)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 15
        let (data, response) = try await session().data(for: request)
        try validate(response: response, bodySize: data.count, allowedStatus: 200)
        return data
    }

    public func post<T: Encodable & Sendable>(_ value: T, to endpoint: URL) async throws {
        try CommandLineAutomationBootstrapParser.validateLoopback(endpoint)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(value)
        let (data, response) = try await session().data(for: request)
        try validate(response: response, bodySize: data.count, allowedStatus: 204)
    }

    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(
            configuration: configuration,
            delegate: CommandLineNoRedirectDelegate(),
            delegateQueue: nil
        )
    }

    private func validate(
        response: URLResponse,
        bodySize: Int,
        allowedStatus: Int
    ) throws {
        guard bodySize <= maximumBodySize else {
            throw CommandLineLoopbackClientError.bodyTooLarge
        }
        guard let response = response as? HTTPURLResponse,
              response.statusCode == allowedStatus
        else {
            throw CommandLineLoopbackClientError.invalidResponse
        }
    }
}

private final class CommandLineNoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

public enum CommandLineLoopbackClientError: Error, Equatable, Sendable {
    case invalidResponse
    case bodyTooLarge
}
