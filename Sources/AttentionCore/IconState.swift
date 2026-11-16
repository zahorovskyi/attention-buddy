/// What the floating icon shows.
///
/// Cases are ordered by priority. When sessions are in different states, the icon shows the
/// highest one: needs you > error > seen > done > working > done (looked at) > error (looked at)
/// > idle. A finished or failed turn ranks above working only until the user looks at it, so an
/// old result never hides sessions that are still running. `asleep` is never a session's state:
/// it is what the icon shows while the user put it to sleep, above everything.
public enum IconState: Int, Comparable, Sendable, CaseIterable {
    /// No session is doing anything yet.
    case idle
    /// A turn failed with an error, and the user has already looked at it.
    case errorSeen
    /// A session finished its turn, and the user has already looked at it.
    case doneSeen
    /// At least one session is working.
    case working
    /// A session finished its turn and the user hasn't looked at it yet.
    case done
    /// A session needs the user, and the user has already looked at Claude.
    case seen
    /// A session's turn failed with an error, and the user hasn't looked at it yet.
    case error
    /// A session needs the user: an approval, a question or other input.
    case needsYou
    /// The user put the icon to sleep for a while: grey and silent, whatever the sessions do.
    case asleep

    public static func < (lhs: IconState, rhs: IconState) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// The state the icon shows for a set of sessions: the highest priority, or idle when empty.
    public static func aggregate<States: Sequence>(_ states: States) -> IconState
    where States.Element == IconState {
        states.max() ?? .idle
    }
}
