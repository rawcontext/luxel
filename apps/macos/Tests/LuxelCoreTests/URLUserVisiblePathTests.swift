import Foundation
import LuxelCore
import Testing

@Suite("URL user-visible path")
struct URLUserVisiblePathTests {
    private func makeFakeContainerHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory
            .appending(path: "user-visible-path-\(UUID().uuidString)")
        let containerData = home.appending(
            path: "Library/Containers/com.rawcontext.luxel/Data")
        try FileManager.default.createDirectory(
            at: containerData, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: home.appending(path: "Movies"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: containerData.appending(path: "Movies").path,
            withDestinationPath: "../../../../Movies"
        )
        return home
    }

    private func realPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    @Test("container Movies symlink resolves to the real Movies folder")
    func containerMoviesSymlinkResolvesToRealMoviesFolder() throws {
        let home = try makeFakeContainerHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let containerMovies = home.appending(
            path: "Library/Containers/com.rawcontext.luxel/Data/Movies")

        #expect(containerMovies.userVisiblePath == realPath(home.appending(path: "Movies")))
    }

    @Test("missing leaf folder still resolves through the symlinked parent")
    func missingLeafFolderStillResolvesThroughSymlinkedParent() throws {
        let home = try makeFakeContainerHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let missingLuxel = home.appending(
            path: "Library/Containers/com.rawcontext.luxel/Data/Movies/Luxel")

        #expect(
            missingLuxel.userVisiblePath
                == realPath(home.appending(path: "Movies")) + "/Luxel")
    }

    @Test("path without symlinks is unchanged")
    func pathWithoutSymlinksIsUnchanged() throws {
        let home = try makeFakeContainerHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let movies = home.appending(path: "Movies")

        #expect(movies.userVisiblePath == realPath(movies))
    }
}
