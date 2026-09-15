import LuxelTestSupport
import Testing

@Suite("Test subprocess output")
struct TestProcessOutputTests {
    @Test("large stdout and stderr cannot block a child process before exit")
    func capturesOutputLargerThanPipeBuffers() throws {
        let result = try runTestProcess(
            executable: "/bin/sh",
            arguments: ["-c", "head -c 131072 /dev/zero; head -c 131072 /dev/zero >&2"]
        )
        #expect(result.terminationStatus == 0)
        #expect(result.output.utf8.count == 131_072)
        #expect(result.error.utf8.count == 131_072)
    }
}
