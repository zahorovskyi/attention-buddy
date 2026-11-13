import Foundation

/// Reads the per-session state files and cleans up after sessions whose process has exited.
public struct SessionStore: Sendable {
    public let directory: URL
    private let isProcessAlive: @Sendable (Int32) -> Bool

    public init(
        directory: URL = SessionStore.defaultDirectory,
        isProcessAlive: @escaping @Sendable (Int32) -> Bool = ProcessProbe.isAlive
    ) {
        self.directory = directory
        self.isProcessAlive = isProcessAlive
    }

    /// `$ATTENTION_BUDDY_DIR`, or `~/.claude/attention-buddy`.
    public static var defaultDirectory: URL {
        if let custom = ProcessInfo.processInfo.environment["ATTENTION_BUDDY_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/attention-buddy", isDirectory: true)
    }

    /// Loads every readable session, newest first. Deletes files of sessions whose process is gone.
    public func load() -> [SessionRecord] {
        var sessions: [SessionRecord] = []
        for url in stateFiles() {
            guard let data = try? Data(contentsOf: url) else {
                continue
            }
            let fallbackID = url.deletingPathExtension().lastPathComponent
            guard let session = SessionRecord(stateFileData: data, fallbackID: fallbackID) else {
                continue
            }
            if session.pid > 0 && !isProcessAlive(session.pid) {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            sessions.append(session)
        }
        return sessions.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Deletes every session file. Running sessions write a new one on their next event.
    public func removeAll() {
        for url in stateFiles() {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Visible `*.json` files only; skips the hook's temporary and lock files.
    private func stateFiles() -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return
            names
            .filter { $0.hasSuffix(".json") && !$0.hasPrefix(".") }
            .map { directory.appendingPathComponent($0) }
    }
}

/// Checks whether a process is still running.
public enum ProcessProbe {
    @Sendable
    public static func isAlive(_ pid: Int32) -> Bool {
        if kill(pid, 0) == 0 {
            return true
        }
        // EPERM means the process exists but belongs to someone else.
        return errno == EPERM
    }
}
