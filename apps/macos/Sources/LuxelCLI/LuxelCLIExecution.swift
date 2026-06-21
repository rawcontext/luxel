import ArgumentParser
import Foundation
import LuxelCore
import Network

public struct LuxelCommandExecutionArguments: ParsableArguments {
    @Flag(help: "Wait for Luxel to call back with the command result.")
    public var wait = false

    @Flag(help: "Wait for the result and print JSON.")
    public var json = false

    @Option(help: "Seconds to wait for a callback before failing.")
    public var timeout: Double = 120

    public init() {}

    public init(wait: Bool, json: Bool, timeout: Double = 120) {
        self.wait = wait
        self.json = json
        self.timeout = timeout
    }

    var requiresCallbackResult: Bool {
        wait || json
    }
}

public enum LuxelCallbackResult: Equatable {
    case success(filePath: String?, recordingID: String?)
    case failure(errorMessage: String)
}

public protocol LuxelCallbackReceiver: AnyObject {
    var callbacks: AutomationCallbacks { get }
    func wait(timeout: TimeInterval) throws -> LuxelCallbackResult
    func cancel()
}

public func runLuxelCommand(
    _ invocation: AutomationInvocation,
    execution: LuxelCommandExecutionArguments,
    opener: any LuxelURLOpener = SystemLuxelURLOpener(),
    callbackReceiverFactory: () throws -> any LuxelCallbackReceiver = {
        try LocalLuxelCallbackReceiver()
    },
    output: (String) -> Void = { print($0) }
) throws {
    guard execution.requiresCallbackResult else {
        try opener.open(AutomationInvocationURLBuilder.url(for: invocation))
        return
    }

    guard execution.timeout.isFinite, execution.timeout > 0 else {
        throw LuxelCLIError.invalidCallbackTimeout
    }

    guard invocation.callbacks.success == nil,
          invocation.callbacks.error == nil
    else {
        throw LuxelCLIError.callbackConflict
    }

    let receiver = try callbackReceiverFactory()
    defer {
        receiver.cancel()
    }

    let waitingInvocation = AutomationInvocation(
        command: invocation.command,
        callbacks: receiver.callbacks
    )
    try opener.open(AutomationInvocationURLBuilder.url(for: waitingInvocation))

    let result = try receiver.wait(timeout: execution.timeout)
    if execution.json {
        output(try LuxelCommandResultFormatter.jsonString(for: result))
    } else if let line = LuxelCommandResultFormatter.plainString(for: result) {
        output(line)
    }

    if case .failure(let message) = result {
        throw LuxelCLIError.remoteFailure(message)
    }
}

public enum LuxelCommandResultFormatter {
    public static func plainString(for result: LuxelCallbackResult) -> String? {
        switch result {
        case .success(let filePath, let recordingID):
            filePath ?? recordingID
        case .failure:
            nil
        }
    }

    public static func jsonString(for result: LuxelCallbackResult) throws -> String {
        let object: [String: String]
        switch result {
        case .success(let filePath, let recordingID):
            object = [
                "status": "ok",
                "filePath": filePath,
                "recordingID": recordingID
            ].compactMapValues(\.self)
        case .failure(let errorMessage):
            object = [
                "status": "error",
                "errorMessage": errorMessage
            ]
        }

        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )
        guard let json = String(data: data, encoding: .utf8) else {
            throw LuxelCLIError.invalidCallbackRequest
        }

        return json
    }
}

public final class LocalLuxelCallbackReceiver: LuxelCallbackReceiver, @unchecked Sendable {
    public private(set) var callbacks = AutomationCallbacks()

    private let listener: NWListener
    private let queue = DispatchQueue(label: "media.luxel.cli.callback")
    private let resultSemaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var result: Result<LuxelCallbackResult, any Error>?

    public init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(
            host: .ipv4(IPv4Address("127.0.0.1")!),
            port: .any
        )
        let listener = try NWListener(using: parameters, on: .any)
        let readySemaphore = DispatchSemaphore(value: 0)
        let readyResult = CallbackReadyState()

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if let port = listener.port {
                    readyResult.set(.success(port))
                } else {
                    readyResult.set(.failure(LuxelCLIError.callbackListenFailed))
                }
                readySemaphore.signal()
            case .failed(let error):
                readyResult.set(.failure(error))
                readySemaphore.signal()
            default:
                break
            }
        }

        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            self?.receive(connection)
        }
        listener.start(queue: queue)

        guard readySemaphore.wait(timeout: .now() + 5) == .success else {
            listener.cancel()
            throw LuxelCLIError.callbackListenFailed
        }

        let port: NWEndpoint.Port
        switch readyResult.value ?? .failure(LuxelCLIError.callbackListenFailed) {
        case .success(let readyPort):
            port = readyPort
        case .failure(let error):
            listener.cancel()
            throw error
        }

        callbacks = AutomationCallbacks(
            success: URL(string: "http://127.0.0.1:\(port.rawValue)/success"),
            error: URL(string: "http://127.0.0.1:\(port.rawValue)/error")
        )
    }

    public func wait(timeout: TimeInterval) throws -> LuxelCallbackResult {
        guard resultSemaphore.wait(timeout: .now() + timeout) == .success else {
            throw LuxelCLIError.callbackTimedOut
        }

        switch lock.withLock({ result }) ?? .failure(LuxelCLIError.callbackTimedOut) {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        }
    }

    public func cancel() {
        listener.cancel()
    }

    private func receive(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) {
            [weak self] data, _, _, error in
            guard let self else {
                connection.cancel()
                return
            }

            let callbackResult: Result<LuxelCallbackResult, any Error>
            if let error {
                callbackResult = .failure(error)
            } else if let data,
                      let request = String(data: data, encoding: .utf8) {
                callbackResult = Self.parseRequest(request)
            } else {
                callbackResult = .failure(LuxelCLIError.invalidCallbackRequest)
            }

            self.store(callbackResult)
            self.respond(on: connection)
        }
    }

    private func respond(on connection: NWConnection) {
        let response = """
      HTTP/1.1 204 No Content\r
      Connection: close\r
      Content-Length: 0\r
      \r

      """
        connection.send(
            content: Data(response.utf8),
            completion: .contentProcessed { _ in
                connection.cancel()
            }
        )
    }

    private func store(_ callbackResult: Result<LuxelCallbackResult, any Error>) {
        lock.withLock {
            guard result == nil else {
                return
            }

            result = callbackResult
            resultSemaphore.signal()
        }
    }

    private static func parseRequest(_ request: String) -> Result<LuxelCallbackResult, any Error> {
        guard let requestLine = request.split(separator: "\r\n").first else {
            return .failure(LuxelCLIError.invalidCallbackRequest)
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2,
              let components = URLComponents(string: "http://localhost\(parts[1])")
        else {
            return .failure(LuxelCLIError.invalidCallbackRequest)
        }

        let queryItems = components.queryItems ?? []
        var query: [String: String] = [:]
        for item in queryItems where query[item.name] == nil {
            query[item.name] = item.value ?? ""
        }

        if components.path == "/error" || query["errorMessage"] != nil {
            return .success(.failure(errorMessage: query["errorMessage"] ?? "Luxel command failed"))
        }

        return .success(
            .success(
                filePath: query["filePath"],
                recordingID: query["recordingID"]
            ))
    }
}

private final class CallbackReadyState: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Result<NWEndpoint.Port, any Error>?

    var value: Result<NWEndpoint.Port, any Error>? {
        lock.withLock {
            storedValue
        }
    }

    func set(_ value: Result<NWEndpoint.Port, any Error>) {
        lock.withLock {
            guard storedValue == nil else {
                return
            }

            storedValue = value
        }
    }
}
