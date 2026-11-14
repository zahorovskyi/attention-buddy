/// What the session card shows: a one-line summary and one row per session.
public struct HoverCardContent: Equatable, Sendable {
    public struct Row: Equatable, Sendable {
        public var title: String
        public var detail: String
        public var state: IconState
        /// The Claude Code session id, used to open the session when the row is clicked.
        public var sessionID: String
        /// Whether clicking the row can open the session (only desktop app sessions can).
        public var canOpen: Bool

        public init(title: String, detail: String, state: IconState, sessionID: String = "", canOpen: Bool = false) {
            self.title = title
            self.detail = detail
            self.state = state
            self.sessionID = sessionID
            self.canOpen = canOpen
        }
    }

    public var header: String
    public var rows: [Row]
    /// For example "+3 more sessions", when there are more sessions than rows.
    public var overflow: String?

    public init(header: String, rows: [Row], overflow: String?) {
        self.header = header
        self.rows = rows
        self.overflow = overflow
    }

    /// Builds the card from sessions that are already sorted most urgent first.
    /// `canOpen` says which sessions the Claude desktop app can open; the others are marked
    /// "in a terminal" and can't be clicked.
    public static func make(
        from resolved: [(session: SessionRecord, state: IconState)],
        limit: Int = 6,
        canOpen: (SessionRecord) -> Bool = { _ in false }
    ) -> HoverCardContent {
        let rows = resolved.prefix(limit).map { entry in
            let openable = canOpen(entry.session)
            var detail = StateText.detail(for: entry.session, state: entry.state)
            if !openable {
                detail += " · in a terminal"
            }
            return Row(
                title: entry.session.displayName,
                detail: detail,
                state: entry.state,
                sessionID: entry.session.id,
                canOpen: openable)
        }
        var overflow: String?
        let hidden = resolved.count - rows.count
        if hidden > 0 {
            overflow = hidden == 1 ? "+1 more session" : "+\(hidden) more sessions"
        }
        return HoverCardContent(header: header(for: resolved.map(\.state)), rows: rows, overflow: overflow)
    }

    /// A one-line summary of all sessions, for example "2 sessions need you".
    public static func header(for states: [IconState]) -> String {
        guard !states.isEmpty else {
            return "No Claude Code sessions yet"
        }
        let waiting = states.filter { $0 == .needsYou }.count
        if waiting == 1 {
            return "1 session needs you"
        }
        if waiting > 1 {
            return "\(waiting) sessions need you"
        }
        switch IconState.aggregate(states) {
        case .error:
            return "A session stopped with an error"
        case .seen:
            return "Waiting for your answer"
        case .done:
            return "All done"
        case .working:
            return "Claude is working"
        case .idle, .needsYou, .asleep:
            return "All quiet"
        }
    }
}
