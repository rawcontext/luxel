import CryptoKit
import Foundation

public struct SHA256ArtifactVerifier: LocalModelArtifactVerifying, Sendable {
    public init() {}

    public func verify(fileAt url: URL, artifact: LocalModelArtifact) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw LocalModelFailure.invalidFileType
        }
        let actualBytes = (attributes[.size] as? NSNumber)?.int64Value ?? -1
        guard actualBytes == artifact.byteCount else {
            throw LocalModelFailure.unexpectedByteCount(
                expected: artifact.byteCount,
                actual: actualBytes
            )
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: data)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == artifact.sha256 else {
            throw LocalModelFailure.checksumMismatch
        }
    }
}
