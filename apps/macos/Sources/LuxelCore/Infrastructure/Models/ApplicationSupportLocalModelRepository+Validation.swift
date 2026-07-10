import Foundation

extension ApplicationSupportLocalModelRepository {
    func validateExactFiles(
        at root: URL,
        expectedPaths: Set<String>,
        expectedSizes: [String: Int64] = [:]
    ) throws {
        var actualPaths = Set<String>()
        guard
            let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey],
                options: []
            )
        else {
            throw LocalModelFailure.unexpectedFileSet
        }

        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [
                .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey
            ])
            guard values.isSymbolicLink != true else {
                throw LocalModelFailure.invalidFileType
            }
            if values.isDirectory == true {
                continue
            }
            guard values.isRegularFile == true else {
                throw LocalModelFailure.invalidFileType
            }
            try prohibitExecutableFile(at: url)
            let relative = relativePath(of: url, under: root)
            actualPaths.insert(relative)
            if let expectedSize = expectedSizes[relative] {
                let attributes = try fileManager.attributesOfItem(atPath: url.path)
                let actualSize = (attributes[.size] as? NSNumber)?.int64Value ?? -1
                guard actualSize == expectedSize else {
                    throw LocalModelFailure.unexpectedByteCount(
                        expected: expectedSize,
                        actual: actualSize
                    )
                }
            }
        }
        guard actualPaths == expectedPaths else {
            throw LocalModelFailure.unexpectedFileSet
        }
    }

    func prohibitExecutableContent(at root: URL) throws {
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: nil)
        else {
            throw LocalModelFailure.invalidFileType
        }
        for case let url as URL in enumerator {
            var isDirectory = ObjCBool(false)
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                continue
            }
            if !isDirectory.boolValue {
                try prohibitExecutableFile(at: url)
            }
        }
    }

    func prohibitExecutableFile(at url: URL) throws {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
        guard permissions & 0o111 == 0 else {
            throw LocalModelFailure.invalidFileType
        }
        let links = (attributes[.referenceCount] as? NSNumber)?.intValue ?? 1
        guard links <= 1 else {
            throw LocalModelFailure.invalidFileType
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let prefix = try handle.read(upToCount: 4) ?? Data()
        let forbiddenMagic: Set<[UInt8]> = [
            [0xfe, 0xed, 0xfa, 0xce], [0xce, 0xfa, 0xed, 0xfe],
            [0xfe, 0xed, 0xfa, 0xcf], [0xcf, 0xfa, 0xed, 0xfe],
            [0xca, 0xfe, 0xba, 0xbe]
        ]
        guard !forbiddenMagic.contains(Array(prefix)),
              !prefix.starts(with: Data([0x23, 0x21]))
        else {
            throw LocalModelFailure.invalidFileType
        }
    }

    func ensureRoot() throws {
        try createPrivateDirectory(at: root)
        try markExcludedFromBackup(root)
    }

    func createPrivateDirectory(at directory: URL) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var current = directory.standardizedFileURL.resolvingSymlinksInPath()
        while current.path == root.path || current.path.hasPrefix(root.path + "/") {
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o700))],
                ofItemAtPath: current.path
            )
            if current.path == root.path { break }
            current = current.deletingLastPathComponent()
        }
    }

    func markExcludedFromBackup(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
        guard
            try mutableURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
                .isExcludedFromBackup == true
        else {
            throw LocalModelFailure.storageFailure("Could not exclude model storage from backup")
        }
    }

    func removeStaleStaging(for id: LocalModelID) throws {
        let stagingRoot = try modelRoot(for: id)
            .appending(path: "staging", directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: stagingRoot.path) else {
            return
        }
        try fileManager.removeItem(at: stagingRoot)
    }

    func modelRoot(for id: LocalModelID) throws -> URL {
        let url = root.appending(path: id.rawValue, directoryHint: .isDirectory)
        try requireDescendant(url, of: root)
        return url
    }

    func releaseRoot(for id: LocalModelID, commit: String) throws -> URL {
        let url = try modelRoot(for: id)
            .appending(path: "releases", directoryHint: .isDirectory)
            .appending(path: commit, directoryHint: .isDirectory)
        try requireDescendant(url, of: root)
        return url
    }

    func requireDescendant(_ candidate: URL, of parent: URL) throws {
        let parentPath = parent.standardizedFileURL.resolvingSymlinksInPath().path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let candidatePath = candidate.standardizedFileURL.resolvingSymlinksInPath().path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard candidatePath == parentPath || candidatePath.hasPrefix(parentPath + "/") else {
            throw LocalModelFailure.storagePermission
        }
    }

    func removeIfEmpty(_ directory: URL) {
        guard
            let contents = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ), contents.isEmpty
        else {
            return
        }
        try? fileManager.removeItem(at: directory)
    }

    func relativePath(of url: URL, under root: URL) -> String {
        String(url.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1))
    }

    func allocatedBytes(at root: URL) throws -> Int64 {
        var total: Int64 = 0
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey
        ]
        guard
            let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys)
            )
        else {
            return 0
        }
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: keys)
            guard values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }

    func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: url, options: [.atomic])
    }
}
