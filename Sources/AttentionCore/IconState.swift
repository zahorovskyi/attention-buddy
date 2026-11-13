/// What the floating icon shows.
///
/// Cases are ordered by priority. When sessions are in different states, the icon shows
/// the highest one: needs you > error > seen > done > working > idle.
public enum IconState: Int, Comparable, Sendable, CaseIterable {
    /// No session is doing anything yet.
    case idle
    /// At least one session is working.
    case working
    /// A session finished its turn and is waiting for the next prompt.
    case done
    /// A session needs the user, and the user has already looked at Claude.
    case seen
    /// A session's turn failed with an error.
    case error
    /// A session needs the user: an approval, a question or other input.
    case needsYou

    public static func < (lhs: IconState, rhs: IconState) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// The state the icon shows for a set of sessions: the highest priority, or idle when empty.
    public static func aggregate<States: Sequence>(_ states: States) -> IconState
    where States.Element == IconState {
        states.max() ?? .idle
    }
}
