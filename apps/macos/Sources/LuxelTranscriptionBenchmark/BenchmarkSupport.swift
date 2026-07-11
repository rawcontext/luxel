import Foundation

enum BenchmarkSupport {
    static func resolve(_ path: String, relativeTo directory: URL) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded).standardizedFileURL
        }
        return directory.appending(path: expanded).standardizedFileURL
    }

    static func normalizedText(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let scalars = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "'" ? Character(scalar) : " "
        }
        return String(scalars).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func normalizedWords(_ text: String) -> [String] {
        normalizedText(text).split(separator: " ").map(String.init)
    }

    static func errorRate<Element: Equatable>(
        reference: [Element],
        hypothesis: [Element]
    ) -> Double {
        guard !reference.isEmpty else { return hypothesis.isEmpty ? 0 : 1 }
        var previous = Array(0...hypothesis.count)
        for (referenceIndex, referenceElement) in reference.enumerated() {
            var current = [referenceIndex + 1] + Array(repeating: 0, count: hypothesis.count)
            for (hypothesisIndex, hypothesisElement) in hypothesis.enumerated() {
                current[hypothesisIndex + 1] = min(
                    current[hypothesisIndex] + 1,
                    previous[hypothesisIndex + 1] + 1,
                    previous[hypothesisIndex]
                        + (referenceElement == hypothesisElement ? 0 : 1)
                )
            }
            previous = current
        }
        return Double(previous[hypothesis.count]) / Double(reference.count)
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }

    static func measure(_ operation: () async throws -> Void) async throws -> Double {
        let start = ContinuousClock.now
        try await operation()
        return seconds(since: start)
    }

    static func seconds(since start: ContinuousClock.Instant) -> Double {
        let duration = start.duration(to: .now)
        return Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    static func machineName() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var value = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &value, &size, nil, 0)
        let bytes = value.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
        return String(bytes: bytes, encoding: .utf8) ?? "Unknown Apple silicon"
    }
}

enum BenchmarkReportPrinter {
    static func print(_ report: BenchmarkReport) {
        Swift.print("Luxel transcription benchmark")
        Swift.print("Machine: \(report.machine)")
        Swift.print("OS: \(report.operatingSystem)\n")
        Swift.print("Engine / fixture                 Load     Clip   Median    RTFx      WER      CER")
        for engine in report.results {
            for fixture in engine.fixtures {
                print(fixture, engine: engine)
            }
        }
        Swift.print("\nPrecision user-path estimate = load time + inference time per request.")
        for engine in report.results where engine.loadSeconds > 0 {
            for fixture in engine.fixtures {
                let total = engine.loadSeconds + fixture.medianSeconds
                Swift.print(
                    String(
                        format: "  %@ / %@: %.2fs (%.2fx real time)",
                        engine.engine,
                        fixture.fixture,
                        total,
                        fixture.audioSeconds / total
                    )
                )
            }
        }
    }

    private static func print(_ fixture: FixtureResult, engine: EngineResult) {
        let label = "\(engine.engine) / \(fixture.fixture)"
        let wer = fixture.wordErrorRate.map { String(format: "%6.2f%%", $0 * 100) } ?? "   n/a "
        let cer = fixture.characterErrorRate.map { String(format: "%6.2f%%", $0 * 100) } ?? "   n/a "
        Swift.print(
            label.padding(toLength: 32, withPad: " ", startingAt: 0)
                + String(
                    format: "%7.2fs %7.2fs %7.2fs %7.2fx %@ %@",
                    engine.loadSeconds,
                    fixture.audioSeconds,
                    fixture.medianSeconds,
                    fixture.realTimeFactor,
                    wer,
                    cer
                )
        )
    }
}
