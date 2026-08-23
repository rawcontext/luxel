import Foundation
import LuxelCore
import LuxelTestSupport
import Testing

@Suite("Caption file export service")
struct CaptionFileExportServiceTests {
    @Test("caption formats expose sidecar file extensions")
    func captionFormatsExposeSidecarFileExtensions() {
        #expect(CaptionFileFormat.srt.fileExtension == "srt")
        #expect(CaptionFileFormat.vtt.fileExtension == "vtt")
        #expect(CaptionFileFormat.plainText.fileExtension == "txt")
    }

    @Test("service writes SRT captions")
    func serviceWritesSRTCaptions() throws {
        let fileSystem = SpyFileSystem()
        let service = CaptionFileExportService(fileSystem: fileSystem)
        let fileURL = URL(fileURLWithPath: "/tmp/captions.srt")

        let exported = try service.export(
            CaptionFileExportRequest(
                track: sampleCaptionTrack(),
                format: .srt,
                outputFileURL: fileURL
            ))

        #expect(exported == ExportedCaptionFile(fileURL: fileURL, format: .srt))
        #expect(
            fileSystem.utf8Writes == [
                WrittenData(
                    text: """
                        1
                        00:00:01,200 --> 00:00:03,400
                        Hello
                        world

                        2
                        01:01:01,005 --> 01:01:02,500
                        Done

                        """,
                    fileURL: fileURL
                )
            ])
    }

    @Test("service writes VTT captions")
    func serviceWritesVTTCaptions() throws {
        let fileSystem = SpyFileSystem()
        let service = CaptionFileExportService(fileSystem: fileSystem)
        let fileURL = URL(fileURLWithPath: "/tmp/captions.vtt")

        _ = try service.export(
            CaptionFileExportRequest(
                track: sampleCaptionTrack(),
                format: .vtt,
                outputFileURL: fileURL
            ))

        #expect(
            fileSystem.utf8Writes == [
                WrittenData(
                    text: """
                        WEBVTT

                        00:00:01.200 --> 00:00:03.400
                        Hello
                        world

                        01:01:01.005 --> 01:01:02.500
                        Done

                        """,
                    fileURL: fileURL
                )
            ])
    }

    @Test("service writes plain text captions")
    func serviceWritesPlainTextCaptions() throws {
        let fileSystem = SpyFileSystem()
        let service = CaptionFileExportService(fileSystem: fileSystem)
        let fileURL = URL(fileURLWithPath: "/tmp/captions.txt")

        _ = try service.export(
            CaptionFileExportRequest(
                track: sampleCaptionTrack(),
                format: .plainText,
                outputFileURL: fileURL
            ))

        #expect(
            fileSystem.utf8Writes == [
                WrittenData(
                    text: """
                        Hello
                        world

                        Done

                        """,
                    fileURL: fileURL
                )
            ])
    }

    @Test("service maps captions for trimmed speed-adjusted export")
    func serviceMapsCaptionsForTrimmedSpeedAdjustedExport() throws {
        let fileSystem = SpyFileSystem()
        let service = CaptionFileExportService(fileSystem: fileSystem)
        let fileURL = URL(fileURLWithPath: "/tmp/captions.srt")

        _ = try service.export(
            CaptionFileExportRequest(
                track: sampleCaptionTrack(),
                format: .srt,
                outputFileURL: fileURL,
                timeMapper: CaptionExportTimeMapper(
                    trimRange: TimeRange(start: 2.2, end: 4.2),
                    speed: PlaybackSpeed(2)
                )
            ))

        #expect(
            fileSystem.utf8Writes == [
                WrittenData(
                    text: """
                        1
                        00:00:00,000 --> 00:00:00,600
                        Hello
                        world

                        """,
                    fileURL: fileURL
                )
            ])
    }

    @Test("service writes empty caption tracks")
    func serviceWritesEmptyCaptionTracks() throws {
        let track = try CaptionTrack(cues: [], language: Locale.LanguageCode("en"))
        let fileSystem = SpyFileSystem()
        let service = CaptionFileExportService(fileSystem: fileSystem)

        _ = try service.export(
            CaptionFileExportRequest(
                track: track,
                format: .srt,
                outputFileURL: URL(fileURLWithPath: "/tmp/empty.srt")
            ))
        _ = try service.export(
            CaptionFileExportRequest(
                track: track,
                format: .vtt,
                outputFileURL: URL(fileURLWithPath: "/tmp/empty.vtt")
            ))
        _ = try service.export(
            CaptionFileExportRequest(
                track: track,
                format: .plainText,
                outputFileURL: URL(fileURLWithPath: "/tmp/empty.txt")
            ))

        #expect(
            fileSystem.utf8Writes == [
                WrittenData(text: "", fileURL: URL(fileURLWithPath: "/tmp/empty.srt")),
                WrittenData(text: "WEBVTT\n", fileURL: URL(fileURLWithPath: "/tmp/empty.vtt")),
                WrittenData(text: "", fileURL: URL(fileURLWithPath: "/tmp/empty.txt"))
            ])
    }

}

private typealias SpyFileSystem = TestWritingFileSystem
private typealias WrittenData = TestUTF8WrittenFile
