import CryptoKit
import Foundation
import Testing

@Suite("Bundled model auditors")
struct BundledModelAuditTests {
    @Test("independent pins reject artifact and manifest substitution")
    func independentPinsRejectArtifactAndManifestSubstitution() throws {
        for specification in specifications {
            let directory = try temporaryModelCopy(specification)
            defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }

            let artifactDirectory = directory.appending(path: specification.artifactDirectory)
            let weight = artifactDirectory.appending(path: "weights/weight.bin")
            var data = try Data(contentsOf: weight)
            data.append(Data("tamper".utf8))
            try data.write(to: weight)
            try rewriteManifestChecksums(
                specification: specification,
                directory: directory,
                artifactDirectory: artifactDirectory
            )

            #expect(try runAuditor(specification, directory: directory) != 0)
        }
    }

    @Test("literal artifact roots reject absolute paths outside the audited model")
    func literalArtifactRootsRejectAbsolutePaths() throws {
        let packageRoot = try sharedPackageRootURL()
        for specification in specifications {
            let directory = try temporaryModelCopy(specification)
            defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }

            let externalArtifact = packageRoot
                .appending(path: "Vendor/Models/\(specification.modelDirectory)")
                .appending(path: specification.artifactDirectory)
            try rewriteArtifactDirectory(
                externalArtifact.path,
                manifest: directory.appending(path: specification.manifest)
            )
            try FileManager.default.removeItem(
                at: directory.appending(path: specification.artifactDirectory)
            )

            #expect(try runAuditor(specification, directory: directory) != 0)
        }
    }

    @Test("model auditors reject symlinked artifact roots")
    func modelAuditorsRejectSymlinkedArtifactRoots() throws {
        let packageRoot = try sharedPackageRootURL()
        for specification in specifications {
            let directory = try temporaryModelCopy(specification)
            defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }

            let artifact = directory.appending(path: specification.artifactDirectory)
            try FileManager.default.removeItem(at: artifact)
            try FileManager.default.createSymbolicLink(
                at: artifact,
                withDestinationURL: packageRoot
                    .appending(path: "Vendor/Models/\(specification.modelDirectory)")
                    .appending(path: specification.artifactDirectory)
            )

            #expect(try runAuditor(specification, directory: directory) != 0)
        }
    }

    @Test("model auditors pin legal resources")
    func modelAuditorsPinLegalResources() throws {
        for specification in specifications {
            let directory = try temporaryModelCopy(specification)
            defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }

            try Data("not a license\n".utf8).write(
                to: directory.appending(path: "LICENSE.txt")
            )

            #expect(try runAuditor(specification, directory: directory) != 0)
        }
    }

    private var specifications: [ModelAuditSpecification] {
        [
            ModelAuditSpecification(
                modelDirectory: "modnet",
                artifactDirectory: "MODNetPortraitMatting.mlmodelc",
                manifest: "model-manifest.json",
                auditor: "audit-modnet-model.sh"
            ),
            ModelAuditSpecification(
                modelDirectory: "voice-activity-detection",
                artifactDirectory: "silero-vad-unified-256ms-v6.2.1.mlmodelc",
                manifest: "model-manifest.json",
                auditor: "audit-voice-activity-detection-model.sh"
            )
        ]
    }

    private func temporaryModelCopy(_ specification: ModelAuditSpecification) throws -> URL {
        let packageRoot = try sharedPackageRootURL()
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: "luxel-model-audit-\(UUID().uuidString)")
        let destination = temporaryRoot.appending(path: specification.modelDirectory)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: packageRoot.appending(path: "Vendor/Models/\(specification.modelDirectory)"),
            to: destination
        )
        return destination
    }

    private func runAuditor(
        _ specification: ModelAuditSpecification,
        directory: URL
    ) throws -> Int32 {
        let packageRoot = try sharedPackageRootURL()
        let process = Process()
        process.executableURL = packageRoot.appending(path: "Scripts/\(specification.auditor)")
        process.arguments = [directory.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private func rewriteArtifactDirectory(_ value: String, manifest: URL) throws {
        var object = try jsonObject(at: manifest)
        var artifact = try #require(object["artifact"] as? [String: Any])
        artifact["directory"] = value
        object["artifact"] = artifact
        try writeJSONObject(object, to: manifest)
    }

    private func rewriteManifestChecksums(
        specification: ModelAuditSpecification,
        directory: URL,
        artifactDirectory: URL
    ) throws {
        var object = try jsonObject(at: directory.appending(path: specification.manifest))
        var artifact = try #require(object["artifact"] as? [String: Any])
        let inventory = try artifactInventory(at: artifactDirectory)
        artifact["byteSize"] = inventory.byteCount
        artifact["sha256"] = inventory.treeSHA256
        if var files = artifact["files"] as? [String: String] {
            files["weights/weight.bin"] = try sha256(
                of: artifactDirectory.appending(path: "weights/weight.bin")
            )
            artifact["files"] = files
        }
        object["artifact"] = artifact
        try writeJSONObject(object, to: directory.appending(path: specification.manifest))
    }

    private func artifactInventory(at directory: URL) throws -> (byteCount: Int, treeSHA256: String) {
        let enumerator = try #require(
            FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        )
        let files = enumerator.compactMap { $0 as? URL }.filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }.sorted { $0.path < $1.path }

        var treeHasher = SHA256()
        var byteCount = 0
        for file in files {
            let data = try Data(contentsOf: file)
            let relativePath = String(file.path.dropFirst(directory.path.count + 1))
            treeHasher.update(data: Data(relativePath.utf8))
            treeHasher.update(data: Data([0]))
            treeHasher.update(data: Data(SHA256.hash(data: data)))
            byteCount += data.count
        }
        return (byteCount, treeHasher.finalize().hexString)
    }

    private func sha256(of file: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: file)).hexString
    }

    private func jsonObject(at url: URL) throws -> [String: Any] {
        try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
    }

    private func writeJSONObject(_ object: [String: Any], to url: URL) throws {
        try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        ).write(to: url)
    }
}

private struct ModelAuditSpecification {
    let modelDirectory: String
    let artifactDirectory: String
    let manifest: String
    let auditor: String
}

private extension SHA256.Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
