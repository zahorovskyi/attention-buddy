import Foundation

/// Finds the Claude desktop app's id for a Claude Code session, so clicking it can open it.
///
/// The desktop app keeps one small JSON file per session under
/// `~/Library/Application Support/Claude/claude-code-sessions/`, with `sessionId` (`local_…`, the
/// id its links use) and `cliSessionId` (the id hook events carry). These files are not a
/// published interface, so any problem simply means "no link": sessions that can't be mapped,
/// such as terminal sessions, are shown but can't be opened.
public final class DesktopSessionIndex {
    public let root: URL
    private var desktopIDs: [String: String] = [:]
    private var lastScan: Date?
    /// How often an unknown session may trigger a new scan of the folder.
    private let rescanInterval: TimeInterval
    /// Files bigger than this are skipped: a session file is normally a few kilobytes.
    static let maximumFileSize = 5_000_000

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
        if let known = desktopIDs[sessionID] {
            return known
        }
        let scanIsDue = lastScan.map { now.timeIntervalSince($0) >= rescanInterval } ?? true
        if scanIsDue {
            rescan()
            lastScan = now
        }
        return desktopIDs[sessionID]
    }

    /// Reads every `local_*.json` file below the root again.
    public func rescan() {
        var found: [String: String] = [:]
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard
            let files = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        else {
            desktopIDs = found
            return
        }
        for case let url as URL in files {
            let name = url.lastPathComponent
            guard name.hasPrefix("local_"), name.hasSuffix(".json") else {
                continue
            }
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true, (values?.fileSize ?? 0) <= Self.maximumFileSize,
                let data = try? Data(contentsOf: url), let link = Self.parse(data)
            else {
                continue
            }
            found[link.sessionID] = link.desktopID
        }
        desktopIDs = found
    }

    /// Reads the two ids from one desktop session file. `nil` if they are missing or malformed.
    public static func parse(_ data: Data) -> (sessionID: String, desktopID: String)? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let desktopID = object["sessionId"] as? String,
            let sessionID = object["cliSessionId"] as? String,
            ClaudeLinks.isValidDesktopID(desktopID), !sessionID.isEmpty
        else {
            return nil
        }
        return (sessionID, desktopID)
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
