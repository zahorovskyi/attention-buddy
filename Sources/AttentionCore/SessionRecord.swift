import Foundation

/// One Claude Code session, as recorded by the hook script in the state directory.
public struct SessionRecord: Equatable, Sendable {
    /// What the hook script last saw the session doing.
    public enum Status: String, Sendable, CaseIterable {
        case idle
        case working
        case needs
        case done
        case error
    }

    /// Why a session needs the user. `.none` unless the status is `.needs`.
    public enum Reason: String, Sendable, CaseIterable {
        case approval
        case question
        case input
        case none = ""
    }

    public var id: String
    public var status: Status
    public var reason: Reason
    /// The tool waiting for approval, for example `Bash`. Empty when not relevant.
    public var tool: String
    /// The session title Claude Code reported, if any.
    public var title: String
    /// The session's working directory.
    public var cwd: String
    /// Process id of the Claude Code process that owns the session, or 0 if unknown.
    public var pid: Int32
    /// Changes on every write, so a new request can be told apart from an older one.
    public var stamp: String
    public var updatedAt: Date

    public init(
        id: String,
        status: Status,
        reason: Reason = .none,
        tool: String = "",
        title: String = "",
        cwd: String = "",
        pid: Int32 = 0,
        stamp: String = "",
        updatedAt: Date = Date(timeIntervalSince1970: 0)
    ) {
        self.id = id
        self.status = status
        self.reason = reason
        self.tool = tool
        self.title = title
        self.cwd = cwd
        self.pid = pid
        self.stamp = stamp
        self.updatedAt = updatedAt
    }

    /// A short name for menus and tooltips: the session title, else the folder name, else a short id.
    public var displayName: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }
        let folder = URL(fileURLWithPath: cwd).lastPathComponent
        if !cwd.isEmpty && !folder.isEmpty && folder != "/" {
            return folder
        }
        return "Session \(id.prefix(8))"
    }
}

extension SessionRecord {
    /// Decodes a state file written by `attention-buddy-hook.sh`.
    ///
    /// Returns `nil` only when the data is not a JSON object. Missing or unknown values fall
    /// back to safe defaults, so a newer hook script never breaks an older icon.
    public init?(stateFileData data: Data, fallbackID: String) {
        guard let file = try? JSONDecoder().decode(StateFile.self, from: data) else {
            return nil
        }
        var sessionID = fallbackID
        if let decodedID = file.sessionID, !decodedID.isEmpty {
            sessionID = decodedID
        }
        self.init(
            id: sessionID,
            status: Status(rawValue: file.status ?? "") ?? .idle,
            reason: Reason(rawValue: file.reason ?? "") ?? .none,
            tool: file.tool ?? "",
            title: file.title ?? "",
            cwd: file.cwd ?? "",
            pid: file.pid ?? 0,
            stamp: file.stamp ?? "",
            updatedAt: Date(timeIntervalSince1970: file.updatedAt ?? 0)
        )
    }
}

/// The on-disk shape of a state file. Every field is optional on purpose.
struct StateFile: Decodable {
    var sessionID: String?
    var status: String?
    var reason: String?
    var tool: String?
    var title: String?
    var cwd: String?
    var pid: Int32?
    var stamp: String?
    var updatedAt: Double?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case status
        case reason
        case tool
        case title
        case cwd
        case pid
        case stamp
        case updatedAt = "updated_at"
    }
}
