import Foundation

/// Remembers that the user chose Quit, so a new Claude Code session doesn't bring the icon back.
///
/// The note is a file named `.quit` in the state folder holding the time of the Quit in Unix
/// seconds. It counts only until the next login: the login item and Homebrew clear it by starting
/// the icon, and a note older than the last Mac restart is ignored (the plugin has no login item).
/// Starting the icon by any route clears it. "Hide until next session" writes no note.
///
/// The hook script and the plugin start script read the same file, with the same rule.
public struct QuitNote: Sendable {
    public let file: URL
    private let bootTime: @Sendable () -> Date?

    public init(directory: URL, bootTime: @escaping @Sendable () -> Date? = QuitNote.systemBootTime) {
        self.file = directory.appendingPathComponent(".quit")
        self.bootTime = bootTime
    }

    /// Records a Quit at `now`.
    public func write(at now: Date = Date()) {
        let seconds = Int(now.timeIntervalSince1970)
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data("\(seconds)\n".utf8).write(to: file, options: .atomic)
    }

    public func clear() {
        try? FileManager.default.removeItem(at: file)
    }

    /// Whether the user quit since the Mac last started, so session starts must leave the icon closed.
    public var isActive: Bool {
        guard let quitAt = recordedQuit else {
            return false
        }
        guard let boot = bootTime() else {
            return true
        }
        return quitAt >= boot
    }

    /// When the note says the user quit, or `nil` without a readable note.
    public var recordedQuit: Date? {
        guard let text = try? String(contentsOf: file, encoding: .utf8),
            let seconds = Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            return nil
        }
        return Date(timeIntervalSince1970: seconds)
    }

    /// When the Mac last started, from `sysctl kern.boottime`.
    @Sendable
    public static func systemBootTime() -> Date? {
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.size
        var name: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&name, 2, &bootTime, &size, nil, 0) == 0, bootTime.tv_sec > 0 else {
            return nil
        }
        return Date(timeIntervalSince1970: TimeInterval(bootTime.tv_sec))
    }
}
