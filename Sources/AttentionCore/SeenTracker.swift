import Foundation

/// Remembers which sessions the user has already looked at.
///
/// A session that needs the user, finished its turn or stopped with an error becomes "seen"
/// when the user switches to Claude, clicks the icon or opens the session from the card.
/// A new event from the same session (a new stamp) clears the mark.
///
/// For a waiting session the mark expires after `timeout`, so a forgotten request starts asking
/// for attention again. A finished or failed turn waits for nothing, so its mark never expires.
public struct SeenTracker: Sendable {
    public var timeout: TimeInterval
    private var marks: [String: Mark] = [:]

    private struct Mark: Sendable {
        var stamp: String
        var markedAt: Date
    }

    public init(timeout: TimeInterval) {
        self.timeout = timeout
    }

    /// Whether a session with `status` can be marked as seen.
    public static func canBeSeen(_ status: SessionRecord.Status) -> Bool {
        switch status {
        case .needs, .done, .error:
            return true
        case .idle, .working:
            return false
        }
    }

    /// Marks every session that is waiting, done or stopped with an error as seen.
    /// Looking again restarts the timer.
    public mutating func markSeen(_ sessions: [SessionRecord], at now: Date) {
        for session in sessions where Self.canBeSeen(session.status) {
            marks[session.id] = Mark(stamp: session.stamp, markedAt: now)
        }
    }

    /// Whether the user has looked at `session` since its last event. For a waiting session the
    /// look counts only for `timeout`.
    public func isSeen(_ session: SessionRecord, at now: Date) -> Bool {
        guard Self.canBeSeen(session.status), let mark = marks[session.id], mark.stamp == session.stamp else {
            return false
        }
        if session.status == .needs {
            return now.timeIntervalSince(mark.markedAt) < timeout
        }
        return true
    }

    /// Drops marks for sessions that no longer exist.
    public mutating func forget(sessionsNotIn liveIDs: Set<String>) {
        marks = marks.filter { liveIDs.contains($0.key) }
    }
}
