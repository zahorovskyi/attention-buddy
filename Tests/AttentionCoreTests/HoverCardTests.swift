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
            ([.done, .working], "1 session finished"),
            ([.done, .done, .doneSeen], "2 sessions finished"),
            ([.doneSeen, .doneSeen, .working], "Claude is working"),
            ([.errorSeen, .working], "Claude is working"),
            ([.working, .idle], "Claude is working"),
            ([.doneSeen, .doneSeen], "All done"),
            ([.doneSeen, .idle], "All quiet"),
            ([.errorSeen], "All quiet"),
            ([.idle], "All quiet"),
        ])
    func header(states: [IconState], expected: String) {
        #expect(HoverCardContent.header(for: states) == expected)
    }

    @Test("Each session becomes a row with its name and what it needs")
    func rows() {
        let content = HoverCardContent.make(from: [entry("a", .needsYou, title: "Fix login")]) { _ in true }
        #expect(
            content.rows == [
                .init(
                    title: "Fix login", detail: "Needs your approval for Bash", state: .needsYou, sessionID: "a",
                    canOpen: true)
            ])
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

@Suite("Resizing the icon")
struct ResizePlacementTests {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let big = CGSize(width: 160, height: 120)

    @Test("In the bottom-right corner the right and bottom edges stay put")
    func bottomRight() {
        let frame = CGRect(x: 1376, y: 24, width: 40, height: 30)
        let origin = Placement.resizedOrigin(from: frame, to: big, screens: [screen])
        #expect(origin == CGPoint(x: 1256, y: 24))
    }

    @Test("In the top-left corner the left and top edges stay put")
    func topLeft() {
        let frame = CGRect(x: 24, y: 846, width: 40, height: 30)
        let origin = Placement.resizedOrigin(from: frame, to: big, screens: [screen])
        #expect(origin == CGPoint(x: 24, y: 756))
    }

    @Test("Growing and shrinking back returns to exactly the same place, without drifting")
    func reversible() {
        var frame = CGRect(x: 1100, y: 89, width: 39, height: 32)
        let original = frame
        for step in 1...20 {
            let size = CGSize(width: 39 + CGFloat(step) * 5, height: 32 + CGFloat(step) * 4)
            frame = CGRect(origin: Placement.resizedOrigin(from: frame, to: size, screens: [screen]), size: size)
        }
        for step in (0...19).reversed() {
            let size = CGSize(width: 39 + CGFloat(step) * 5, height: 32 + CGFloat(step) * 4)
            frame = CGRect(origin: Placement.resizedOrigin(from: frame, to: size, screens: [screen]), size: size)
        }
        #expect(frame == original)
    }

    @Test("A size that would leave the screen is pushed back on")
    func staysOnScreen() {
        let frame = CGRect(x: 1430, y: 0, width: 10, height: 10)
        let origin = Placement.resizedOrigin(from: frame, to: big, screens: [screen])
        #expect(origin.x + big.width <= screen.maxX)
        #expect(origin.y >= screen.minY)
    }
}
