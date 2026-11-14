/// Words shown in the tooltip and the right-click menu.
public enum StateText {
    public static func label(for state: IconState) -> String {
        switch state {
        case .idle:
            return "Idle"
        case .working:
            return "Working"
        case .done:
            return "Done"
        case .seen:
            return "Waiting for you"
        case .error:
            return "Stopped with an error"
        case .needsYou:
            return "Needs you"
        case .asleep:
            return "Asleep"
        }
    }

    /// One line describing what a session is doing, for example "Needs your approval for Bash".
    public static func detail(for session: SessionRecord, state: IconState) -> String {
        guard state == .needsYou || state == .seen else {
            return label(for: state)
        }
        let seenSuffix = state == .seen ? " (seen)" : ""
        switch session.reason {
        case .question:
            return "Has a question for you" + seenSuffix
        case .input:
            return "Needs your input" + seenSuffix
        case .approval, .none:
            if session.tool.isEmpty {
                return "Needs your approval" + seenSuffix
            }
            return "Needs your approval for \(session.tool)" + seenSuffix
        }
    }

    /// The tooltip: one line per session, most urgent first.
    public static func tooltip(for resolved: [(session: SessionRecord, state: IconState)]) -> String {
        guard !resolved.isEmpty else {
            return "Attention Buddy: no Claude Code sessions yet"
        }
        return
            resolved
            .map { "\($0.session.displayName): \(detail(for: $0.session, state: $0.state))" }
            .joined(separator: "\n")
    }
}
