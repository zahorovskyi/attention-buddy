import Foundation

/// Notices when the app's own program file has been replaced by an update, so the running icon
/// can restart into the new version.
///
/// It remembers which file the path pointed to at launch (device, inode and modification time,
/// following symlinks such as Homebrew's `opt` link). An installer that moves a new file into
/// place, a plugin rebuild or `brew upgrade` all change that identity.
public struct ExecutableWatcher: Sendable {
    /// The identity of a file on disk.
    public struct Identity: Equatable, Sendable {
        var device: UInt64
        var inode: UInt64
        var modified: TimeInterval
    }

    public let path: String
    public let launched: Identity?

    public init(path: String) {
        self.path = path
        self.launched = Self.identity(of: path)
    }

    /// Whether the path now points to a different, runnable file than at launch. A missing file
    /// (for example halfway through an update) is not a replacement: there is nothing to start yet.
    public func hasBeenReplaced() -> Bool {
        guard let launched, let current = Self.identity(of: path), current != launched else {
            return false
        }
        return FileManager.default.isExecutableFile(atPath: path)
    }

    public static func identity(of path: String) -> Identity? {
        var info = stat()
        guard stat(path, &info) == 0 else {
            return nil
        }
        let modified = TimeInterval(info.st_mtimespec.tv_sec) + TimeInterval(info.st_mtimespec.tv_nsec) / 1e9
        return Identity(device: UInt64(info.st_dev), inode: UInt64(info.st_ino), modified: modified)
    }

    /// The absolute path this process was started with, without resolving symlinks, so a
    /// Homebrew install keeps watching its stable `opt` path. `nil` if it can't be found.
    public static func launchPath(
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        currentDirectory: String = FileManager.default.currentDirectoryPath
    ) -> String? {
        guard let invoked = arguments.first, !invoked.isEmpty else {
            return nil
        }
        if invoked.hasPrefix("/") {
            return invoked
        }
        if invoked.contains("/") {
            return URL(fileURLWithPath: currentDirectory).appendingPathComponent(invoked).standardizedFileURL.path
        }
        for folder in (environment["PATH"] ?? "").split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(folder)).appendingPathComponent(invoked).path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
}
