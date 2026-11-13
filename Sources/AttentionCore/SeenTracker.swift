import Foundation

/// Remembers which waiting sessions the user has already looked at.
///
/// A session that needs the user becomes "seen" when the user switches to Claude or clicks
/// the icon. The mark expires after `timeout`, so a forgotten request starts asking for
/// attention again. A new request from the same session (a new stamp) clears the mark.
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

    /// Marks every session that currently needs the user as seen. Looking again restarts the timer.
    public mutating func markSeen(_ sessions: [SessionRecord], at now: Date) {
        for session in sessions where session.status == .needs {
            marks[session.id] = Mark(stamp: session.stamp, markedAt: now)
        }
    }

    /// Whether `session` is waiting and was seen less than `timeout` ago, for the same request.
    public func isSeen(_ session: SessionRecord, at now: Date) -> Bool {
        guard session.status == .needs, let mark = marks[session.id], mark.stamp == session.stamp else {
            return false
        }
        return now.timeIntervalSince(mark.markedAt) < timeout
    }

    /// Drops marks for sessions that no longer exist.
    public mutating func forget(sessionsNotIn liveIDs: Set<String>) {
        marks = marks.filter { liveIDs.contains($0.key) }
    }
}
