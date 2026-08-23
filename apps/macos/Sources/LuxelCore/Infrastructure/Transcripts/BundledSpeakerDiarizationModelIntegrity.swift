import CryptoKit
import Foundation

private struct BundledSpeakerArtifact: Decodable {
    let path: String
    let byteCount: Int64
    let sha256: String
}

private struct BundledSpeakerManifest: Decodable {
    let schemaVersion: Int
    let repository: String
    let revision: String
    let license: String
    let artifactByteCount: Int64
    let artifactTreeSHA256: String
    let files: [BundledSpeakerArtifact]
}

struct SpeakerModelIntegrityValidator {

    private static let expectedArtifactByteCount: Int64 = 21_776_918
    private static let expectedArtifactTreeSHA256 =
        "c343ed0130553e6fd7a81146bbcdd888a6d2042df85299763fc604085a568543"

    let fileManager: FileManager

    func isValid(directory: URL, repository: String, revision: String) -> Bool {
        guard
            let rootValues = try? directory.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            ),
            rootValues.isDirectory == true,
            rootValues.isSymbolicLink != true,
            let manifest = loadManifest(from: directory),
            manifest.schemaVersion == 1,
            manifest.repository == repository,
            manifest.revision == revision,
            manifest.license == "CC-BY-4.0",
            manifest.artifactByteCount == Self.expectedArtifactByteCount,
            manifest.artifactTreeSHA256 == Self.expectedArtifactTreeSHA256,
            manifest.files.count == 23,
            manifest.files.map(\.path) == manifest.files.map(\.path).sorted(),
            Set(manifest.files.map(\.path)).count == manifest.files.count
        else {
            return false
        }
        return fileSetIsValid(manifest: manifest, directory: directory)
            && artifactsAreValid(manifest.files, directory: directory)
    }

    private func loadManifest(from directory: URL) -> BundledSpeakerManifest? {
        guard
            let data = try? Data(contentsOf: directory.appending(path: "model-manifest.json"))
        else {
            return nil
        }
        return try? JSONDecoder().decode(BundledSpeakerManifest.self, from: data)
    }

    private func fileSetIsValid(manifest: BundledSpeakerManifest, directory: URL) -> Bool {
        var expectedFiles = Set(manifest.files.map(\.path))
        expectedFiles.formUnion(["LICENSE.txt", "NOTICE.md", "model-manifest.json"])
        var actualFiles = Set<String>()
        guard
            let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
        else {
            return false
        }
        for case let fileURL as URL in enumerator {
            guard
                let values = try? fileURL.resourceValues(
                    forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
                ),
                values.isSymbolicLink != true
            else {
                return false
            }
            if values.isRegularFile == true {
                actualFiles.insert(relativePath(of: fileURL, from: directory))
            }
        }
        return actualFiles == expectedFiles
    }

    private func artifactsAreValid(
        _ artifacts: [BundledSpeakerArtifact],
        directory: URL
    ) -> Bool {
        var treeHasher = SHA256()
        var totalByteCount: Int64 = 0
        for artifact in artifacts {
            guard
                isSafeRelativePath(artifact.path),
                let fileData = try? Data(contentsOf: directory.appending(path: artifact.path))
            else {
                return false
            }
            let fileDigest = SHA256.hash(data: fileData)
            guard
                Int64(fileData.count) == artifact.byteCount,
                hexString(fileDigest) == artifact.sha256
            else {
                return false
            }
            treeHasher.update(data: Data(artifact.path.utf8))
            treeHasher.update(data: Data([0]))
            treeHasher.update(data: Data(fileDigest))
            totalByteCount += Int64(fileData.count)
        }

        return totalByteCount == Self.expectedArtifactByteCount
            && hexString(treeHasher.finalize()) == Self.expectedArtifactTreeSHA256
    }

    private func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/") else {
            return false
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    private func relativePath(of file: URL, from directory: URL) -> String {
        let rootPath = directory.resolvingSymlinksInPath().path
        let filePath = file.resolvingSymlinksInPath().path
        return String(filePath.dropFirst(rootPath.count + 1))
    }

    private func hexString<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
