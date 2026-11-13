import Foundation
import Testing

@testable import AttentionCore

private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("attention-buddy-desktop-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite("Desktop session index")
struct DesktopSessionIndexTests {
    private func writeSession(_ json: String, named name: String, in folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: folder.appendingPathComponent(name))
    }

    @Test("Finds the desktop id for a session in nested folders")
    func findsNested() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeSession(
            #"{"sessionId":"local_abc-123","cliSessionId":"cli-1","title":"Fix login"}"#,
            named: "local_abc-123.json", in: root.appendingPathComponent("account/org"))
        let index = DesktopSessionIndex(root: root)
        #expect(index.desktopID(for: "cli-1") == "local_abc-123")
        #expect(index.desktopID(for: "unknown") == nil)
    }

    @Test(
        "Malformed files and ids the app would reject are ignored",
        arguments: [
            #"{"sessionId":"local_ok","cliSessionId":""}"#,
            #"{"sessionId":"bad id","cliSessionId":"cli-1"}"#,
            #"{"sessionId":"local_../escape","cliSessionId":"cli-1"}"#,
            #"{"cliSessionId":"cli-1"}"#,
            "not json",
        ])
    func rejectsBadFiles(json: String) {
        #expect(DesktopSessionIndex.parse(Data(json.utf8)) == nil)
    }

    @Test("A new desktop session is found on the next scan, but scans are rate-limited")
    func rescansWhenUnknown() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let index = DesktopSessionIndex(root: root, rescanInterval: 5)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(index.desktopID(for: "cli-2", at: start) == nil)

        try writeSession(
            #"{"sessionId":"local_new","cliSessionId":"cli-2"}"#, named: "local_new.json", in: root)
        #expect(index.desktopID(for: "cli-2", at: start.addingTimeInterval(1)) == nil)
        #expect(index.desktopID(for: "cli-2", at: start.addingTimeInterval(6)) == "local_new")
    }

    @Test("A missing folder means no desktop sessions")
    func missingRoot() {
        let index = DesktopSessionIndex(root: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)"))
        #expect(index.desktopID(for: "anything") == nil)
    }
}

@Suite("Claude links")
struct ClaudeLinksTests {
    @Test("Waiting sessions open on what they wait for, others simply open")
    func routes() {
        #expect(
            ClaudeLinks.session("local_abc-123", isWaiting: true)?.absoluteString
                == "claude://code/needs-input?session=local_abc-123")
        #expect(
            ClaudeLinks.session("local_abc-123", isWaiting: false)?.absoluteString
                == "claude://code/continue?session=local_abc-123")
    }

    @Test(
        "Ids the desktop app would reject produce no link",
        arguments: ["", "abc", "local_", "local_a b", "local_a&x=1"])
    func rejectsInvalid(id: String) {
        #expect(ClaudeLinks.session(id, isWaiting: false) == nil)
    }
}

@Suite("Opening and closing the card")
struct CardPresenterTests {
    @Test("Hover opens the card after the delay")
    func hoverOpens() {
        var card = CardPresenter()
        #expect(card.pointerEnteredIcon() == .scheduleShow)
        #expect(card.showDelayEnded() == .show)
        #expect(card.isShown && !card.isPinned)
    }

    @Test("Leaving before the delay ends cancels the hover")
    func hoverCancelled() {
        var card = CardPresenter()
        _ = card.pointerEnteredIcon()
        #expect(card.pointerExitedIcon() == .cancelPending)
        #expect(card.showDelayEnded() == .none)
        #expect(!card.isShown)
    }

    @Test("Moving from the icon onto the card keeps it open")
    func moveOntoCard() {
        var card = CardPresenter()
        _ = card.pointerEnteredIcon()
        _ = card.showDelayEnded()
        #expect(card.pointerExitedIcon() == .scheduleHide)
        #expect(card.pointerEnteredCard() == .cancelPending)
        #expect(card.hideDelayEnded() == .none)
        #expect(card.isShown)
    }

    @Test("Leaving both the icon and the card closes it after the grace period")
    func leaveBoth() {
        var card = CardPresenter()
        _ = card.pointerEnteredIcon()
        _ = card.showDelayEnded()
        _ = card.pointerEnteredCard()
        _ = card.pointerExitedIcon()
        #expect(card.pointerExitedCard() == .scheduleHide)
        #expect(card.hideDelayEnded() == .hide)
        #expect(!card.isShown)
    }

    @Test("A click opens the card at once and pins it, so leaving does not close it")
    func clickPins() {
        var card = CardPresenter()
        #expect(card.iconClicked() == .show)
        #expect(card.isPinned)
        #expect(card.pointerExitedIcon() == .none)
        #expect(card.pointerExitedCard() == .none)
        #expect(card.hideDelayEnded() == .none)
        #expect(card.isShown)
    }

    @Test("Clicking a hover card pins it; clicking again closes it")
    func clickToggles() {
        var card = CardPresenter()
        _ = card.pointerEnteredIcon()
        _ = card.showDelayEnded()
        #expect(card.iconClicked() == .show)
        #expect(card.isPinned)
        #expect(card.iconClicked() == .hide)
        #expect(!card.isShown && !card.isPinned)
    }

    @Test("A click elsewhere, a chosen session, a drag or the menu closes a pinned card")
    func dismiss() {
        var card = CardPresenter()
        _ = card.iconClicked()
        #expect(card.dismiss() == .hide)
        #expect(!card.isShown && !card.isPinned)
        #expect(card.dismiss() == .cancelPending)
    }
}

@Suite("Card rows")
struct CardRowTests {
    @Test("Desktop sessions can be opened; others are marked as terminal sessions")
    func openableRows() {
        let desktop = SessionRecord(id: "d1", status: .needs, reason: .approval, tool: "Bash", title: "Desktop task")
        let terminal = SessionRecord(id: "t1", status: .working, title: "api-server")
        let content = HoverCardContent.make(from: [(desktop, .needsYou), (terminal, .working)]) { $0.id == "d1" }
        #expect(content.rows[0].canOpen)
        #expect(content.rows[0].sessionID == "d1")
        #expect(content.rows[0].detail == "Needs your approval for Bash")
        #expect(!content.rows[1].canOpen)
        #expect(content.rows[1].detail == "Working · in a terminal")
    }
}
