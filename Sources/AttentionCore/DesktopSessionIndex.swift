import Foundation

/// Finds the Claude desktop app's id and current title for a Claude Code session, so the card
/// can open it and show its name as the user set it.
///
/// The desktop app keeps one small JSON file per session under
/// `~/Library/Application Support/Claude/claude-code-sessions/`, with `sessionId` (`local_…`, the
/// id its links use), `cliSessionId` (the id hook events carry) and `title` (updated when the
/// user renames the session). No hook reports a rename, so the card reads the title from here.
/// These files are not a published interface, so any problem simply means "no link, no title":
/// such sessions, like terminal sessions, are shown with the title from hook events and can't be
/// opened. The files are only ever read.
public final class DesktopSessionIndex {
    /// What the index knows about one desktop session.
    public struct Entry: Equatable, Sendable {
        public var desktopID: String
        public var title: String
        var file: URL
        var modified: Date?
    }

    public let root: URL
    private var entries: [String: Entry] = [:]
    private var lastScan: Date?
    /// How often an unknown session may trigger a new scan of the folder.
    private let rescanInterval: TimeInterval
    /// Files bigger than this are skipped: a session file is normally a few kilobytes.
    static let maximumFileSize = 5_000_000
    private static let fileKeys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]

    public init(root: URL = DesktopSessionIndex.defaultRoot, rescanInterval: TimeInterval = 5) {
        self.root = root
        self.rescanInterval = rescanInterval
    }

    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions", isDirectory: true)
    }

    /// The desktop app's `local_…` id for a session, or `nil` if it isn't a desktop session.
    public func desktopID(for sessionID: String, at now: Date = Date()) -> String? {
        entry(for: sessionID, at: now)?.desktopID
    }

    /// The session's current title in the desktop app, re-reading its file if it changed since
    /// the last look (a rename). `nil` for sessions the desktop app doesn't know or hasn't titled.
    public func currentTitle(for sessionID: String, at now: Date = Date()) -> String? {
        guard var known = entry(for: sessionID, at: now) else {
            return nil
        }
        let modified = Self.modificationDate(of: known.file)
        if modified != known.modified {
            if let data = Self.readSmallFile(known.file), let fresh = Self.parse(data), fresh.sessionID == sessionID {
                known.title = fresh.title
                known.desktopID = fresh.desktopID
            }
            known.modified = modified
            entries[sessionID] = known
        }
        return known.title.isEmpty ? nil : known.title
    }

    /// The title from the last read, without touching the disk.
    public func knownTitle(for sessionID: String) -> String? {
        guard let title = entries[sessionID]?.title, !title.isEmpty else {
            return nil
        }
        return title
    }

    /// The sessions with their desktop titles, where the desktop app has one. With `refresh`,
    /// changed files are re-read; without it, only titles already read are used.
    public func applyingDesktopTitles(to sessions: [SessionRecord], refresh: Bool, at now: Date = Date())
        -> [SessionRecord]
    {
        sessions.map { session in
            let title = refresh ? currentTitle(for: session.id, at: now) : knownTitle(for: session.id)
            guard let title else {
                return session
            }
            var renamed = session
            renamed.title = title
            return renamed
        }
    }

    private func entry(for sessionID: String, at now: Date) -> Entry? {
        if let known = entries[sessionID] {
            return known
        }
        let scanIsDue = lastScan.map { now.timeIntervalSince($0) >= rescanInterval } ?? true
        if scanIsDue {
            rescan()
            lastScan = now
        }
        return entries[sessionID]
    }

    /// Reads every `local_*.json` file below the root again.
    public func rescan() {
        var found: [String: Entry] = [:]
        guard
            let files = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: Self.fileKeys, options: [.skipsHiddenFiles])
        else {
            entries = found
            return
        }
        for case let url as URL in files {
            let name = url.lastPathComponent
            guard name.hasPrefix("local_"), name.hasSuffix(".json"), let data = Self.readSmallFile(url),
                let parsed = Self.parse(data)
            else {
                continue
            }
            found[parsed.sessionID] = Entry(
                desktopID: parsed.desktopID, title: parsed.title, file: url, modified: Self.modificationDate(of: url))
        }
        entries = found
    }

    /// Reads the ids and title from one desktop session file. `nil` if the ids are missing or
    /// malformed; a missing title is an empty string.
    public static func parse(_ data: Data) -> (sessionID: String, desktopID: String, title: String)? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let desktopID = object["sessionId"] as? String,
            let sessionID = object["cliSessionId"] as? String,
            ClaudeLinks.isValidDesktopID(desktopID), !sessionID.isEmpty
        else {
            return nil
        }
        let title = (object["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (sessionID, desktopID, title)
    }

    private static func readSmallFile(_ url: URL) -> Data? {
        let values = try? url.resourceValues(forKeys: Set(fileKeys))
        guard values?.isRegularFile == true, (values?.fileSize ?? 0) <= maximumFileSize else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    private static func modificationDate(of url: URL) -> Date? {
        var fresh = url
        fresh.removeAllCachedResourceValues()
        return (try? fresh.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}

/// Links that open places in the Claude desktop app.
public enum ClaudeLinks {
    /// Claude's "Sessions waiting for you" list.
    public static let waitingSessions = URL(string: "claude://code/needs-input")

    /// Opens one session. Waiting sessions use the "needs input" route, which shows what the
    /// session is waiting for; others use "continue". `nil` for an id the app would reject.
    public static func session(_ desktopID: String, isWaiting: Bool) -> URL? {
        guard isValidDesktopID(desktopID) else {
            return nil
        }
        let route = isWaiting ? "needs-input" : "continue"
        return URL(string: "claude://code/\(route)?session=\(desktopID)")
    }

    /// The same check the desktop app applies to `?session=`.
    public static func isValidDesktopID(_ id: String) -> Bool {
        id.range(of: "^local_[A-Za-z0-9-]{1,64}$", options: .regularExpression) != nil
    }
}
