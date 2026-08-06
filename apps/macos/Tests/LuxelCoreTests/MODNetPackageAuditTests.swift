import Foundation
import Testing

@Suite("MODNet package audit")
struct MODNetPackageAuditTests {
    @Test("package audit expands into a new directory")
    func packageAuditExpandsIntoNewDirectory() throws {
        let packageRoot = try sharedPackageRootURL()
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: "luxel-modnet-audit-\(UUID().uuidString)")
        let binDirectory = temporaryRoot.appending(path: "bin")
        let packageURL = temporaryRoot.appending(path: "Luxel.pkg")
        let pkgutilURL = binDirectory.appending(path: "pkgutil")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        try FileManager.default.createDirectory(
            at: binDirectory,
            withIntermediateDirectories: true
        )
        try Data().write(to: packageURL)
        try pkgutilStub.write(to: pkgutilURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: pkgutilURL.path
        )

        let process = Process()
        process.executableURL = packageRoot.appending(path: "Scripts/audit-modnet-model.sh")
        process.arguments = [packageURL.path]
        process.environment = ProcessInfo.processInfo.environment.merging(
            [
                "LUXEL_TEST_MODEL_DIR": packageRoot
                    .appending(path: "Vendor/Models/modnet").path,
                "PATH": "\(binDirectory.path):\(ProcessInfo.processInfo.environment["PATH"] ?? "")",
                "TMPDIR": temporaryRoot.path
            ],
            uniquingKeysWith: { _, testValue in testValue }
        )

        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
    }

    private var pkgutilStub: String {
        """
        #!/bin/bash
        set -euo pipefail

        if [[ "$1" != "--expand-full" || -e "$3" ]]; then
            exit 91
        fi

        model_parent="$3/Applications/Luxel.app/Contents/Resources/Models"
        mkdir -p "${model_parent}"
        ln -s "${LUXEL_TEST_MODEL_DIR}" "${model_parent}/modnet"
        """
    }
}
