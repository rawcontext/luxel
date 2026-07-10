import Foundation
import LuxelCLI
import LuxelCore
import Testing

@Suite("Luxel CLI execution")
struct LuxelCLIExecutionTests {
    @Test("app-backed result files are printed and removed after consumption")
    func appBackedResultFilesAreConsumed() throws {
        let resultURL = FileManager.default.temporaryDirectory.appending(
            path: "LuxelCLIResult-\(UUID().uuidString).txt"
        )
        try Data("precision transcript\n".utf8).write(to: resultURL)
        let receiver = StubLuxelCallbackReceiver(
            result: .resultFile(
                path: resultURL.path,
                contentType: "text/plain",
                removeAfterRead: true
            )
        )
        var output: [String] = []

        try runLuxelCommand(
            AutomationInvocation(
                command: .transcribe(
                    AutomationTranscriptionOptions(
                        inputURL: URL(fileURLWithPath: "/tmp/input.m4a")
                    )
                )
            ),
            execution: LuxelCommandExecutionArguments(wait: true, json: false),
            opener: SpyLuxelURLOpener(),
            callbackReceiverFactory: { receiver },
            consumesResultFiles: true,
            output: { output.append($0) }
        )

        #expect(output == ["precision transcript"])
        #expect(!FileManager.default.fileExists(atPath: resultURL.path))
    }
    @Test("wait mode installs local callbacks before opening URL")
    func waitModeInstallsLocalCallbacksBeforeOpeningURL() throws {
        let opener = SpyLuxelURLOpener()
        let receiver = StubLuxelCallbackReceiver(
            callbacks: AutomationCallbacks(
                success: URL(string: "http://127.0.0.1:49152/success"),
                error: URL(string: "http://127.0.0.1:49152/error")
            ),
            result: .success(filePath: "/tmp/latest.mp4", recordingID: nil)
        )
        var output: [String] = []

        try runLuxelCommand(
            AutomationInvocation(command: .latest(reveal: true)),
            execution: LuxelCommandExecutionArguments(wait: true, json: false),
            opener: opener,
            callbackReceiverFactory: { receiver },
            output: { output.append($0) }
        )

        #expect(
            opener.openedURLs.map(\.absoluteString) == [
                "luxel://latest?reveal=true&x-success=http://127.0.0.1:49152/success"
                    + "&x-error=http://127.0.0.1:49152/error"
            ])
        #expect(output == ["/tmp/latest.mp4"])
        #expect(receiver.didCancel)
    }

    @Test("json mode prints structured callback result")
    func jsonModePrintsStructuredCallbackResult() throws {
        let opener = SpyLuxelURLOpener()
        let receiver = StubLuxelCallbackReceiver(
            result: .success(filePath: nil, recordingID: "recording-1")
        )
        var output: [String] = []

        try runLuxelCommand(
            AutomationInvocation(command: .stop),
            execution: LuxelCommandExecutionArguments(wait: false, json: true),
            opener: opener,
            callbackReceiverFactory: { receiver },
            output: { output.append($0) }
        )

        #expect(output == [#"{"recordingID":"recording-1","status":"ok"}"#])
    }

    @Test("json mode prints remote errors before failing")
    func jsonModePrintsRemoteErrorsBeforeFailing() {
        let receiver = StubLuxelCallbackReceiver(
            result: .failure(errorMessage: "URL automation is disabled")
        )
        var output: [String] = []

        #expect(throws: LuxelCLIError.remoteFailure("URL automation is disabled")) {
            try runLuxelCommand(
                AutomationInvocation(command: .stop),
                execution: LuxelCommandExecutionArguments(wait: false, json: true),
                opener: SpyLuxelURLOpener(),
                callbackReceiverFactory: { receiver },
                output: { output.append($0) }
            )
        }
        #expect(output == [#"{"errorMessage":"URL automation is disabled","status":"error"}"#])
    }

    @Test("print URL mode writes automation URL without opening Luxel")
    func printURLModeWritesAutomationURLWithoutOpeningLuxel() throws {
        let opener = SpyLuxelURLOpener()
        var output: [String] = []

        try runLuxelCommand(
            AutomationInvocation(command: .latest(reveal: true)),
            execution: LuxelCommandExecutionArguments(
                wait: false,
                json: false,
                printURL: true
            ),
            opener: opener,
            output: { output.append($0) }
        )

        #expect(opener.openedURLs.isEmpty)
        #expect(output == ["luxel://latest?reveal=true"])
    }

    @Test("print URL mode rejects result waiting")
    func printURLModeRejectsResultWaiting() {
        #expect(throws: LuxelCLIError.printURLResultConflict) {
            try runLuxelCommand(
                AutomationInvocation(command: .stop),
                execution: LuxelCommandExecutionArguments(
                    wait: true,
                    json: false,
                    printURL: true
                ),
                opener: SpyLuxelURLOpener(),
                callbackReceiverFactory: { StubLuxelCallbackReceiver() }
            )
        }
    }

    @Test("wait mode rejects explicit callbacks")
    func waitModeRejectsExplicitCallbacks() {
        #expect(throws: LuxelCLIError.callbackConflict) {
            try runLuxelCommand(
                AutomationInvocation(
                    command: .stop,
                    callbacks: AutomationCallbacks(success: URL(string: "luxel-callback://done"))
                ),
                execution: LuxelCommandExecutionArguments(wait: true, json: false),
                opener: SpyLuxelURLOpener(),
                callbackReceiverFactory: { StubLuxelCallbackReceiver() }
            )
        }
    }

    @Test("wait mode rejects invalid callback timeouts before opening URL")
    func waitModeRejectsInvalidCallbackTimeoutsBeforeOpeningURL() {
        let opener = SpyLuxelURLOpener()
        var didCreateReceiver = false

        #expect(throws: LuxelCLIError.invalidCallbackTimeout) {
            try runLuxelCommand(
                AutomationInvocation(command: .stop),
                execution: LuxelCommandExecutionArguments(wait: true, json: false, timeout: 0),
                opener: opener,
                callbackReceiverFactory: {
                    didCreateReceiver = true
                    return StubLuxelCallbackReceiver()
                }
            )
        }

        #expect(opener.openedURLs.isEmpty)
        #expect(!didCreateReceiver)
    }

    @Test("local callback receiver parses success callback requests")
    func localCallbackReceiverParsesSuccessCallbackRequests() async throws {
        let receiver = try LocalLuxelCallbackReceiver()
        defer {
            receiver.cancel()
        }

        let successURL = try #require(receiver.callbacks.success)
        var components = try #require(
            URLComponents(
                url: successURL,
                resolvingAgainstBaseURL: false
            ))
        components.queryItems = [URLQueryItem(name: "filePath", value: "/tmp/Luxel Recording.mp4")]
        let callbackURL = try #require(components.url)

        _ = try await URLSession.shared.data(from: callbackURL)
        let result = try receiver.wait(timeout: 2)

        #expect(result == .success(filePath: "/tmp/Luxel Recording.mp4", recordingID: nil))
    }

    @Test("local callback receiver tolerates duplicate query items")
    func localCallbackReceiverToleratesDuplicateQueryItems() async throws {
        let receiver = try LocalLuxelCallbackReceiver()
        defer {
            receiver.cancel()
        }

        let successURL = try #require(receiver.callbacks.success)
        var components = try #require(
            URLComponents(
                url: successURL,
                resolvingAgainstBaseURL: false
            ))
        components.queryItems = [
            URLQueryItem(name: "filePath", value: "/tmp/first.mp4"),
            URLQueryItem(name: "filePath", value: "/tmp/second.mp4")
        ]
        let callbackURL = try #require(components.url)

        _ = try await URLSession.shared.data(from: callbackURL)
        let result = try receiver.wait(timeout: 2)

        #expect(result == .success(filePath: "/tmp/first.mp4", recordingID: nil))
    }
}

private final class SpyLuxelURLOpener: LuxelURLOpener {
    private(set) var openedURLs: [URL] = []

    func open(_ url: URL) throws {
        openedURLs.append(url)
    }
}

private final class StubLuxelCallbackReceiver: LuxelCallbackReceiver {
    let callbacks: AutomationCallbacks
    private let result: LuxelCallbackResult
    private(set) var didCancel = false

    init(
        callbacks: AutomationCallbacks = AutomationCallbacks(
            success: URL(string: "http://127.0.0.1:49152/success"),
            error: URL(string: "http://127.0.0.1:49152/error")
        ),
        result: LuxelCallbackResult = .success(filePath: nil, recordingID: nil)
    ) {
        self.callbacks = callbacks
        self.result = result
    }

    func wait(timeout: TimeInterval) throws -> LuxelCallbackResult {
        result
    }

    func cancel() {
        didCancel = true
    }
}
