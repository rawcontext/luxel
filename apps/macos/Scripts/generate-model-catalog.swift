#!/usr/bin/env swift
import CryptoKit
import Foundation

enum CatalogToolError: Error, CustomStringConvertible {
    case usage
    case invalidCatalog(String)
    case network(String)

    var description: String {
        switch self {
        case .usage:
            "Usage: generate-model-catalog.swift verify [--catalog PATH] [--against-hub] | generate --catalog PATH --model-id ID --repository OWNER/NAME --revision FULL_COMMIT"
        case .invalidCatalog(let message), .network(let message):
            message
        }
    }
}

struct Arguments {
    let command: String
    let catalogPath: String
    let modelID: String?
    let repository: String?
    let revision: String?
    let againstHub: Bool

    init(_ values: [String]) throws {
        guard let command = values.first, command == "verify" || command == "generate" else {
            throw CatalogToolError.usage
        }
        var options: [String: String] = [:]
        var flags = Set<String>()
        var index = 1
        while index < values.count {
            let key = values[index]
            if key == "--against-hub" {
                flags.insert(key)
                index += 1
                continue
            }
            guard key.hasPrefix("--"), index + 1 < values.count else {
                throw CatalogToolError.usage
            }
            options[key] = values[index + 1]
            index += 2
        }
        self.command = command
        catalogPath =
            options["--catalog"]
            ?? "Sources/LuxelCore/Resources/Models/model-catalog.json"
        modelID = options["--model-id"]
        repository = options["--repository"]
        revision = options["--revision"]
        againstHub = flags.contains("--against-hub")
        if command == "generate",
           modelID == nil || repository == nil || revision == nil {
            throw CatalogToolError.usage
        }
    }
}

func loadCatalog(path: String) throws -> [String: Any] {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    guard let catalog = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw CatalogToolError.invalidCatalog("Catalog is not a JSON object")
    }
    return catalog
}

func validate(_ catalog: [String: Any]) throws {
    guard catalog["schemaVersion"] as? Int == 1,
          let models = catalog["models"] as? [[String: Any]],
          !models.isEmpty
    else {
        throw CatalogToolError.invalidCatalog("Catalog schema or models are invalid")
    }
    var ids = Set<String>()
    for model in models {
        guard let id = model["id"] as? String, ids.insert(id).inserted,
              let release = model["currentRelease"] as? [String: Any],
              let commit = release["commit"] as? String,
              commit.count == 40,
              commit.allSatisfy({ $0.isHexDigit && !$0.isUppercase }),
              let artifacts = release["artifacts"] as? [[String: Any]],
              release["artifactCount"] as? Int == artifacts.count,
              let expected = (release["expectedPayloadBytes"] as? NSNumber)?.int64Value
        else {
            throw CatalogToolError.invalidCatalog("Model \(model["id"] ?? "<unknown>") is invalid")
        }
        var paths = Set<String>()
        var total: Int64 = 0
        for artifact in artifacts {
            guard let path = artifact["path"] as? String,
                  !path.hasPrefix("/"),
                  !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }),
                  paths.insert(path.lowercased()).inserted,
                  let bytes = (artifact["byteCount"] as? NSNumber)?.int64Value,
                  bytes >= 0,
                  let digest = artifact["sha256"] as? String,
                  digest.count == 64,
                  digest.allSatisfy({ $0.isHexDigit && !$0.isUppercase })
            else {
                throw CatalogToolError.invalidCatalog("Artifact in \(id) is invalid")
            }
            total += bytes
        }
        guard total == expected,
              artifacts.map({ $0["path"] as? String ?? "" })
                == artifacts.compactMap({ $0["path"] as? String }).sorted()
        else {
            throw CatalogToolError.invalidCatalog("Artifact totals or ordering are invalid for \(id)")
        }
    }
}

func sha256(_ url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
        hasher.update(data: data)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

func validateDownloadedArtifact(_ url: URL) throws {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    guard attributes[.type] as? FileAttributeType == .typeRegular else {
        throw CatalogToolError.invalidCatalog("Downloaded artifact is not a regular file")
    }
    let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
    guard permissions & 0o111 == 0 else {
        throw CatalogToolError.invalidCatalog("Downloaded artifact is executable")
    }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let prefix = try handle.read(upToCount: 128) ?? Data()
    guard
        !String(decoding: prefix, as: UTF8.self)
            .hasPrefix("version https://git-lfs.github.com/spec/v1")
    else {
        throw CatalogToolError.invalidCatalog("Downloaded artifact is an LFS pointer")
    }
}

func download(_ url: URL, to destination: URL) throws {
    let semaphore = DispatchSemaphore(value: 0)
    let lock = NSLock()
    var result: Result<Void, Error>?
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.urlCache = nil
    let session = URLSession(configuration: configuration)
    let task = session.downloadTask(with: url) { temporaryURL, response, error in
        defer { semaphore.signal() }
        let resolved: Result<Void, Error>
        if let error {
            resolved = .failure(error)
        } else if let response = response as? HTTPURLResponse,
                  (200...299).contains(response.statusCode),
                  let temporaryURL {
            do {
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: temporaryURL, to: destination)
                resolved = .success(())
            } catch {
                resolved = .failure(error)
            }
        } else {
            resolved = .failure(CatalogToolError.network("Download returned an invalid response"))
        }
        lock.withLock { result = resolved }
    }
    task.resume()
    semaphore.wait()
    session.finishTasksAndInvalidate()
    guard let result = lock.withLock({ result }) else {
        throw CatalogToolError.network("Download did not complete")
    }
    try result.get()
}

func hubURL(repository: String, revision: String, path: String) -> URL {
    var url = URL(string: "https://huggingface.co")!
    repository.split(separator: "/").forEach { url.append(path: String($0)) }
    url.append(path: "resolve")
    url.append(path: revision)
    path.split(separator: "/").forEach { url.append(path: String($0)) }
    return url
}

func verifyAgainstHub(_ catalog: [String: Any], only modelID: String? = nil) throws {
    guard let models = catalog["models"] as? [[String: Any]] else {
        throw CatalogToolError.invalidCatalog("Catalog models are invalid")
    }
    for model in models where modelID == nil || model["id"] as? String == modelID {
        guard let release = model["currentRelease"] as? [String: Any],
              let repository = release["repository"] as? String,
              let revision = release["commit"] as? String,
              let artifacts = release["artifacts"] as? [[String: Any]]
        else {
            throw CatalogToolError.invalidCatalog("Catalog release is invalid")
        }
        let temporary = FileManager.default.temporaryDirectory.appending(
            path: "luxel-model-catalog-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: temporary) }
        for artifact in artifacts {
            guard let path = artifact["path"] as? String else {
                throw CatalogToolError.invalidCatalog("Catalog artifact path is invalid")
            }
            let destination = temporary.appending(path: path)
            try download(hubURL(repository: repository, revision: revision, path: path), to: destination)
            try validateDownloadedArtifact(destination)
            let bytes = try FileManager.default.attributesOfItem(atPath: destination.path)[.size]
                .flatMap { ($0 as? NSNumber)?.int64Value }
            guard bytes == (artifact["byteCount"] as? NSNumber)?.int64Value,
                  try sha256(destination) == artifact["sha256"] as? String
            else {
                throw CatalogToolError.invalidCatalog("Hub bytes do not match \(path)")
            }
        }
    }
}

func generate(_ arguments: Arguments, catalog: [String: Any]) throws {
    guard let repository = arguments.repository,
          repository.split(separator: "/").count == 2,
          let revision = arguments.revision,
          revision != "main",
          revision.count == 40,
          revision.allSatisfy({ $0.isHexDigit && !$0.isUppercase }),
          let modelID = arguments.modelID
    else {
        throw CatalogToolError.invalidCatalog(
            "Generate requires owner/name and a full lowercase commit; main, tags, branches, and short SHAs are refused"
        )
    }

    var updated = catalog
    guard var models = updated["models"] as? [[String: Any]] else {
        throw CatalogToolError.invalidCatalog("Catalog models are invalid")
    }
    guard let modelIndex = models.firstIndex(where: { $0["id"] as? String == modelID }) else {
        throw CatalogToolError.invalidCatalog("Unknown model ID \(modelID)")
    }
    var model = models[modelIndex]
    guard var release = model["currentRelease"] as? [String: Any],
          var artifacts = release["artifacts"] as? [[String: Any]]
    else {
        throw CatalogToolError.invalidCatalog("Catalog release is invalid")
    }
    let temporary = FileManager.default.temporaryDirectory.appending(
        path: "luxel-model-catalog-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    defer { try? FileManager.default.removeItem(at: temporary) }
    var total: Int64 = 0
    for index in artifacts.indices {
        guard let path = artifacts[index]["path"] as? String else {
            throw CatalogToolError.invalidCatalog("Catalog artifact path is invalid")
        }
        let destination = temporary.appending(path: path)
        try download(hubURL(repository: repository, revision: revision, path: path), to: destination)
        try validateDownloadedArtifact(destination)
        guard
            let bytes = try FileManager.default.attributesOfItem(atPath: destination.path)[.size]
                .flatMap({ ($0 as? NSNumber)?.int64Value })
        else {
            throw CatalogToolError.invalidCatalog("Downloaded artifact size is unavailable")
        }
        artifacts[index]["byteCount"] = bytes
        artifacts[index]["sha256"] = try sha256(destination)
        total += bytes
    }
    artifacts.sort { ($0["path"] as? String ?? "") < ($1["path"] as? String ?? "") }
    release["repository"] = repository
    release["commit"] = revision
    release["artifacts"] = artifacts
    release["artifactCount"] = artifacts.count
    release["expectedPayloadBytes"] = total
    model["currentRelease"] = release
    models[modelIndex] = model
    updated["models"] = models.sorted {
        ($0["id"] as? String ?? "") < ($1["id"] as? String ?? "")
    }
    try validate(updated)
    let data =
        try JSONSerialization.data(
            withJSONObject: updated,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ) + Data("\n".utf8)
    try data.write(to: URL(fileURLWithPath: arguments.catalogPath), options: .atomic)
    print("\(repository) \(revision) \(artifacts.count) files \(total) bytes")
}

do {
    let arguments = try Arguments(Array(CommandLine.arguments.dropFirst()))
    let catalog = try loadCatalog(path: arguments.catalogPath)
    try validate(catalog)
    if arguments.command == "generate" {
        try generate(arguments, catalog: catalog)
    } else {
        if arguments.againstHub {
            try verifyAgainstHub(catalog)
        }
        print("Verified \(arguments.catalogPath)")
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
