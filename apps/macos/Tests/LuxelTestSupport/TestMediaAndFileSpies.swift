import Foundation
import LuxelCore

public struct TestWrittenFile: Equatable, Sendable {
    public let data: Data
    public let url: URL

    public init(data: Data, url: URL) {
        self.data = data
        self.url = url
    }
}

public struct TestUTF8WrittenFile: Equatable, Sendable {
    public let text: String
    public let fileURL: URL

    public init(text: String, fileURL: URL) {
        self.text = text
        self.fileURL = fileURL
    }
}

public final class TestWritingFileSystem: FileSystem, @unchecked Sendable {
    public private(set) var writes: [TestWrittenFile] = []

    public init() {}

    public var utf8Writes: [TestUTF8WrittenFile] {
        writes.map {
            TestUTF8WrittenFile(
                text: String(bytes: $0.data, encoding: .utf8) ?? "",
                fileURL: $0.url
            )
        }
    }

    public func fileExists(at url: URL) -> Bool { true }
    public func createDirectory(at url: URL) throws {}
    public func copyFile(from sourceURL: URL, to destinationURL: URL) throws {}

    public func writeData(_ data: Data, to url: URL) throws {
        writes.append(TestWrittenFile(data: data, url: url))
    }

    public func removeFile(at url: URL) throws {}
    public func trashItem(at url: URL) throws {}
}

public actor TestAudioPeakAnalyzerSpy: AudioPeakAnalyzer {
    private var capturedRequests: [AudioPeakAnalysisRequest] = []
    private let peaks: [AudioTrackKind: Double]

    public init(peaks: [AudioTrackKind: Double] = [:]) {
        self.peaks = peaks
    }

    public func measurePeaks(
        _ request: AudioPeakAnalysisRequest
    ) async throws -> [AudioTrackKind: Double] {
        capturedRequests.append(request)
        return peaks
    }

    public func requests() -> [AudioPeakAnalysisRequest] {
        capturedRequests
    }
}

public final class TestFrameGrabberSpy: FrameGrabber, @unchecked Sendable {
    public let imageData: FrameGrabImageData
    public private(set) var requests: [FrameGrabRequest] = []

    public init(imageData: FrameGrabImageData) {
        self.imageData = imageData
    }

    public func grab(_ request: FrameGrabRequest) async throws -> FrameGrabImageData {
        requests.append(request)
        return imageData
    }
}

public final class TestFrameGrabFileWriterSpy: FrameGrabFileWriter, @unchecked Sendable {
    public struct Write: Equatable, Sendable {
        public let imageData: FrameGrabImageData
        public let fileURL: URL

        public init(imageData: FrameGrabImageData, fileURL: URL) {
            self.imageData = imageData
            self.fileURL = fileURL
        }
    }

    public private(set) var writes: [Write] = []

    public init() {}

    public func write(_ imageData: FrameGrabImageData, to fileURL: URL) throws {
        writes.append(Write(imageData: imageData, fileURL: fileURL))
    }
}
