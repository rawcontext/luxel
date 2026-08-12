import Foundation
import Testing

@testable import LuxelCore

struct CommandLineAutomationProtocolTests {
    @Test("Version one convert fixture decodes and validates")
    func convertFixture() throws {
        let request = try JSONDecoder().decode(
            CommandLineAutomationRequest.self,
            from: fixtureData("convert-request.json")
        )

        try request.validate()

        #expect(request.protocolVersion == 1)
        #expect(request.command == .convert)
        #expect(request.arguments.convert?.inputPath == "/Users/example/Movies/Luxel/input.mp4")
        #expect(request.arguments.convert?.outputPath == "/Users/example/Movies/Luxel/output.webm")
        #expect(request.arguments.convert?.width == 1280)
        #expect(request.arguments.convert?.height == 720)
        #expect(request.arguments.convert?.mute == true)
        #expect(request.output.json)
    }

    @Test("Version one result fixture decodes")
    func resultFixture() throws {
        let event = try JSONDecoder().decode(
            CommandLineAutomationEvent.self,
            from: fixtureData("export-result.json")
        )

        #expect(event.protocolVersion == 1)
        #expect(event.kind == .result)
        #expect(event.sequence == 2)
        #expect(event.result?.filePath == "/Users/example/Movies/Luxel/output.webm")
        #expect(event.result?.export?.format == "webm")
        #expect(event.result?.export?.width == 1280)
        #expect(event.result?.export?.height == 720)
    }

    @Test("Validation rejects a mismatched payload")
    func mismatchedPayload() {
        let request = CommandLineAutomationRequest(
            requestID: UUID(),
            command: .stop,
            arguments: CommandLineAutomationArguments(
                clip: CommandLineClipArguments(seconds: 10)
            )
        )

        #expect(throws: CommandLineAutomationValidationError.unexpectedArguments(.stop)) {
            try request.validate()
        }
    }

    @Test("Validation rejects unsupported protocol versions")
    func unsupportedVersion() {
        let request = CommandLineAutomationRequest(
            protocolVersion: 2,
            requestID: UUID(),
            command: .doctor
        )

        #expect(throws: CommandLineAutomationValidationError.unsupportedProtocolVersion(2)) {
            try request.validate()
        }
    }

    private func fixtureData(_ name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(
                forResource: name,
                withExtension: nil
            )
        )
        return try Data(contentsOf: url)
    }
}
