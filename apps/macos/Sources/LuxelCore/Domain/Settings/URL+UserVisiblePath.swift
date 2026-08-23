import Foundation

extension URL {
    /// Inside the App Sandbox, system folders resolve through container symlinks
    /// (~/Library/Containers/<bundle-id>/Data/Movies -> ~/Movies), so displaying
    /// the raw path shows a container location the user never sees in Finder.
    public var userVisiblePath: String {
        resolvingSymlinksAllowingMissingLeaves().path
    }

    /// resolvingSymlinksInPath() leaves the whole path untouched when the leaf
    /// does not exist yet (e.g. ~/Movies/Luxel before the first recording), so
    /// resolve the deepest existing ancestor and re-append the missing parts.
    private func resolvingSymlinksAllowingMissingLeaves() -> URL {
        let standardized = standardizedFileURL
        if standardized.pathComponents.count <= 1
            || FileManager.default.fileExists(atPath: standardized.path)
        {
            return standardized.resolvingSymlinksInPath()
        }
        return standardized.deletingLastPathComponent()
            .resolvingSymlinksAllowingMissingLeaves()
            .appending(path: standardized.lastPathComponent)
    }
}
