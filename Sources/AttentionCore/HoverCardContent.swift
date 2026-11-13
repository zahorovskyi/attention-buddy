/// What the hover card shows: a one-line summary and one row per session.
public struct HoverCardContent: Equatable, Sendable {
    public struct Row: Equatable, Sendable {
        public var title: String
        public var detail: String
        public var state: IconState

        public init(title: String, detail: String, state: IconState) {
            self.title = title
            self.detail = detail
            self.state = state
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
    public static func make(
        from resolved: [(session: SessionRecord, state: IconState)],
        limit: Int = 6
    ) -> HoverCardContent {
        let rows = resolved.prefix(limit).map { entry in
            Row(
                title: entry.session.displayName,
                detail: StateText.detail(for: entry.session, state: entry.state),
                state: entry.state)
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
        case .idle, .needsYou:
            return "All quiet"
        }
    }
}
