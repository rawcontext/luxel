import Darwin
import Foundation

public enum CurrentProcessExecutable {
    public static var url: URL? {
        var size: UInt32 = 0
        _ = _NSGetExecutablePath(nil, &size)

        var buffer = [CChar](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&buffer, &size) == 0 else {
            return nil
        }

        return URL(fileURLWithFileSystemRepresentation: buffer, isDirectory: false, relativeTo: nil)
            .resolvingSymlinksInPath()
    }
}
