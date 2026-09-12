import Foundation

#if canImport(BazelRunfiles)
    import BazelRunfiles
#endif

public func testSourceFileURL(from filePath: String = #filePath) -> URL {
    #if canImport(BazelRunfiles)
        if let directory = ProcessInfo.processInfo.environment["TEST_SRCDIR"] {
            do {
                let runfiles = try Runfiles.create(environment: ["RUNFILES_DIR": directory])
                let root = ProcessInfo.processInfo.environment["LUXEL_TEST_DATA"] ?? "luxel"
                return try runfiles.rlocation(root + "/" + filePath)
            } catch {
                preconditionFailure("Unable to locate declared test source \(filePath): \(error)")
            }
        }
    #endif
    return URL(fileURLWithPath: filePath)
}
