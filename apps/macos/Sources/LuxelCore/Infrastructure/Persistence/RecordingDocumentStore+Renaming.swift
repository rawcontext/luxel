import Foundation

extension RecordingDocumentStore {
    public func applyingAutomaticTitle(
        _ proposedTitle: String, to recording: PastRecording, transcript: TurnSegmentedTranscript? = nil
    ) throws -> PastRecording {
        Self.documentLock.lock()
        defer { Self.documentLock.unlock() }
        guard let title = RecordingTitlePolicy.validatedTitle(proposedTitle),
            let bundle = try load(nextTo: recording.primaryMediaURL),
            var organization = bundle.manifest.organization,
            !organization.pathsLocked, organization.titleOrigin == .context,
            organization.exports.isEmpty, recording.exports.isEmpty
        else { return recording }
        let timeZone = TimeZone(identifier: organization.timeZoneIdentifier) ?? .current
        let target = RecordingFileLayout.mediaURL(
            in: bundle.rootURL.deletingLastPathComponent().deletingLastPathComponent(),
            date: organization.capturedAt, title: title,
            fileExtension: bundle.primaryURL.pathExtension, timeZone: timeZone
        )
        let newRoot = target.deletingLastPathComponent()
        let manager = FileManager.default
        let moves = try moveSessionFiles(bundle, to: target)
        organization.title = title
        organization.titleOrigin = .intelligence
        organization.pathsLocked = true
        organization.transcriptFileName = nil
        let manifest = try BundleManifest(
            primaryFileName: target.lastPathComponent, sidecars: bundle.manifest.sidecars,
            organization: organization
        )
        do {
            try save(manifest, in: newRoot)
        } catch {
            try? manager.moveItem(at: newRoot, to: bundle.rootURL)
            for (old, new) in moves.reversed() { try? manager.moveItem(at: new, to: old) }
            throw error
        }
        Self.recordMove(from: bundle.primaryURL, to: target)
        let markdownURL = target.deletingPathExtension().appendingPathExtension("md")
        if ownsMarkdown(markdownURL, sourceURL: bundle.primaryURL),
            let text = try? String(contentsOf: markdownURL, encoding: .utf8) {
            try? Data(renamedMarkdown(text, from: bundle.primaryURL, to: target).utf8)
                .write(to: markdownURL, options: .atomic)
            _ = try? update(nextTo: target) { $0.transcriptFileName = markdownURL.lastPathComponent }
        }
        if let transcript {
            writeRenamedMarkdown(
                transcript, mediaURL: target, previousURL: bundle.primaryURL, duration: organization.duration)
        }
        return recording.replacingFileURL(
            target, name: target.deletingPathExtension().lastPathComponent,
            bundleManifest: (try? load(nextTo: target))?.manifest ?? manifest)
    }

    private func moveSessionFiles(_ bundle: RecordingBundle, to target: URL) throws -> [(URL, URL)] {
        let newRoot = target.deletingLastPathComponent()
        let renamedInRoot = bundle.rootURL.appending(path: target.lastPathComponent)
        let markdown = bundle.primaryURL.deletingPathExtension().appendingPathExtension("md")
        let newMarkdown = renamedInRoot.deletingPathExtension().appendingPathExtension("md")
        let manager = FileManager.default
        try manager.createDirectory(at: newRoot.deletingLastPathComponent(), withIntermediateDirectories: true)
        var moves: [(URL, URL)] = []
        do {
            try manager.moveItem(at: bundle.primaryURL, to: renamedInRoot)
            moves.append((bundle.primaryURL, renamedInRoot))
            if ownsMarkdown(markdown, sourceURL: bundle.primaryURL) {
                try manager.moveItem(at: markdown, to: newMarkdown)
                moves.append((markdown, newMarkdown))
            }
            try manager.moveItem(at: bundle.rootURL, to: newRoot)
        } catch {
            for (old, new) in moves.reversed() { try? manager.moveItem(at: new, to: old) }
            throw error
        }
        return moves
    }

    private func writeRenamedMarkdown(
        _ transcript: TurnSegmentedTranscript, mediaURL: URL, previousURL: URL, duration: TimeInterval?
    ) {
        let outputURL = mediaURL.deletingPathExtension().appendingPathExtension("md")
        let exists = FileManager.default.fileExists(atPath: outputURL.path)
        guard !exists || ownsMarkdown(outputURL, sourceURL: previousURL) else { return }
        let markdownText =
            TranscriptCopyTextBuilder().text(
                transcript: transcript, visibleWords: [], hasCuts: false,
                metadata: TranscriptMarkdownMetadata(sourceURL: mediaURL, duration: duration),
                includesTimestamps: true
            ) + AdjacentMarkdownTranscriptWriter.ownershipMarker(for: mediaURL)
        do {
            try Data(markdownText.utf8).write(to: outputURL, options: exists ? .atomic : .withoutOverwriting)
            _ = try update(nextTo: mediaURL) { $0.transcriptFileName = outputURL.lastPathComponent }
        } catch { return }
    }

    private func ownsMarkdown(_ url: URL, sourceURL: URL) -> Bool {
        (try? String(contentsOf: url, encoding: .utf8))?
            .hasSuffix(AdjacentMarkdownTranscriptWriter.ownershipMarker(for: sourceURL)) == true
    }

    public func synchronizeUserRename(from oldURL: URL, to newURL: URL) throws -> BundleManifest? {
        Self.documentLock.lock()
        defer { Self.documentLock.unlock() }
        guard let bundle = try load(nextTo: oldURL), var organization = bundle.manifest.organization else {
            return nil
        }
        let oldMarkdown = oldURL.deletingPathExtension().appendingPathExtension("md")
        let newMarkdown = newURL.deletingPathExtension().appendingPathExtension("md")
        let owned = ownsMarkdown(oldMarkdown, sourceURL: oldURL)
        let originalText = owned ? try String(contentsOf: oldMarkdown, encoding: .utf8) : nil
        if owned && oldMarkdown != newMarkdown {
            guard !FileManager.default.fileExists(atPath: newMarkdown.path) else {
                throw CocoaError(.fileWriteFileExists)
            }
            try FileManager.default.moveItem(at: oldMarkdown, to: newMarkdown)
        }
        organization.title = newURL.deletingPathExtension().lastPathComponent
        organization.titleOrigin = .user
        organization.pathsLocked = true
        if owned { organization.transcriptFileName = newMarkdown.lastPathComponent }
        let manifest = try BundleManifest(
            primaryFileName: newURL.lastPathComponent, sidecars: bundle.manifest.sidecars,
            organization: organization)
        do {
            if let originalText {
                let text = renamedMarkdown(originalText, from: oldURL, to: newURL)
                try Data(text.utf8).write(to: newMarkdown, options: .atomic)
            }
            try save(manifest, in: newURL.deletingLastPathComponent())
            Self.recordMove(from: oldURL, to: newURL)
        } catch {
            if let originalText {
                try? Data(originalText.utf8).write(to: newMarkdown, options: .atomic)
                if oldMarkdown != newMarkdown { try? FileManager.default.moveItem(at: newMarkdown, to: oldMarkdown) }
            }
            throw error
        }
        return manifest
    }
    private func renamedMarkdown(_ text: String, from oldURL: URL, to newURL: URL) -> String {
        let title = newURL.deletingPathExtension().lastPathComponent
        let encodedTitle = TranscriptCopyTextBuilder().yamlString(title)
        let encodedFile = TranscriptCopyTextBuilder().yamlString(newURL.lastPathComponent)
        let titleField = "title" + ": "
        var frontMatter = false
        var hasHeading = false
        let updated = text.components(separatedBy: "\n").enumerated().map { index, line in
            if index == 0 && line == "---" {
                frontMatter = true
                return line
            }
            if frontMatter && line == "---" {
                frontMatter = false
                return line
            }
            if frontMatter && line.hasPrefix(titleField) { return titleField + encodedTitle }
            if frontMatter && line.hasPrefix("source_file: ") { return "source_file: \(encodedFile)" }
            if !frontMatter && !hasHeading && line.hasPrefix("# ") {
                hasHeading = true
                return "# \(TranscriptCopyTextBuilder().escapedMarkdown(title))"
            }
            return line
        }.joined(separator: "\n")
        return updated.replacingOccurrences(
            of: AdjacentMarkdownTranscriptWriter.ownershipMarker(for: oldURL),
            with: AdjacentMarkdownTranscriptWriter.ownershipMarker(for: newURL))
    }

}
