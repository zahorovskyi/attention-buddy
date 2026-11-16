import Foundation

/// Turns recorded session statuses into what the icon shows.
public enum StateResolver {
    /// The icon state for one session.
    public static func state(of session: SessionRecord, seen: SeenTracker, at now: Date) -> IconState {
        switch session.status {
        case .needs:
            if seen.isSeen(session, at: now) {
                return .seen
            }
            return .needsYou
        case .error:
            if seen.isSeen(session, at: now) {
                return .errorSeen
            }
            return .error
        case .done:
            if seen.isSeen(session, at: now) {
                return .doneSeen
            }
            return .done
        case .working:
            return .working
        case .idle:
            return .idle
        }
    }

    /// Each session paired with its icon state, most urgent first, newest first within a state.
    public static func resolve(
        _ sessions: [SessionRecord],
        seen: SeenTracker,
        at now: Date
    ) -> [(session: SessionRecord, state: IconState)] {
        let pairs = sessions.map { (session: $0, state: state(of: $0, seen: seen, at: now)) }
        return pairs.sorted { left, right in
            if left.state != right.state {
                return left.state > right.state
            }
            return left.session.updatedAt > right.session.updatedAt
        }
    }
}
