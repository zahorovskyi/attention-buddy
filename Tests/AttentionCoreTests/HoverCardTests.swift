import Foundation
import Testing

@testable import AttentionCore

@Suite("Hover card content")
struct HoverCardContentTests {
    private func entry(_ id: String, _ state: IconState, title: String = "") -> (
        session: SessionRecord, state: IconState
    ) {
        let status: SessionRecord.Status = state == .needsYou || state == .seen ? .needs : .working
        return (SessionRecord(id: id, status: status, reason: .approval, tool: "Bash", title: title), state)
    }

    @Test(
        "The header summarizes all sessions",
        arguments: [
            ([IconState](), "No Claude Code sessions yet"),
            ([.needsYou, .working], "1 session needs you"),
            ([.needsYou, .needsYou, .done], "2 sessions need you"),
            ([.error, .done], "A session stopped with an error"),
            ([.seen, .working], "Waiting for your answer"),
            ([.done, .working], "All done"),
            ([.working, .idle], "Claude is working"),
            ([.idle], "All quiet"),
        ])
    func header(states: [IconState], expected: String) {
        #expect(HoverCardContent.header(for: states) == expected)
    }

    @Test("Each session becomes a row with its name and what it needs")
    func rows() {
        let content = HoverCardContent.make(from: [entry("a", .needsYou, title: "Fix login")])
        #expect(content.rows == [.init(title: "Fix login", detail: "Needs your approval for Bash", state: .needsYou)])
        #expect(content.overflow == nil)
    }

    @Test("Extra sessions collapse into an overflow line")
    func overflow() {
        let many = (1...9).map { entry("s\($0)", .working) }
        let content = HoverCardContent.make(from: many, limit: 6)
        #expect(content.rows.count == 6)
        #expect(content.overflow == "+3 more sessions")
        #expect(HoverCardContent.make(from: Array(many.prefix(7)), limit: 6).overflow == "+1 more session")
    }
}

@Suite("Hover card placement")
struct HoverCardPlacementTests {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let card = CGSize(width: 200, height: 120)

    @Test("The card sits centered below the icon")
    func below() {
        let icon = CGRect(x: 700, y: 800, width: 40, height: 30)
        let frame = Placement.hoverCardFrame(cardSize: card, iconFrame: icon, screen: screen)
        #expect(frame == CGRect(x: 620, y: 674, width: 200, height: 120))
    }

    @Test("Near the bottom of the screen it goes above the icon")
    func above() {
        let icon = CGRect(x: 700, y: 20, width: 40, height: 30)
        let frame = Placement.hoverCardFrame(cardSize: card, iconFrame: icon, screen: screen)
        #expect(frame.minY == 56)
    }

    @Test("It never leaves the screen at the sides")
    func clampsSideways() {
        let icon = CGRect(x: 1420, y: 800, width: 40, height: 30)
        let frame = Placement.hoverCardFrame(cardSize: card, iconFrame: icon, screen: screen)
        #expect(frame.maxX == 1440)
    }
}
