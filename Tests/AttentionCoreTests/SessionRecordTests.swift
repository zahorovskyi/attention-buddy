import Foundation
import Testing

@testable import AttentionCore

@Suite("Reading state files")
struct SessionRecordTests {
    @Test("A complete state file decodes every field")
    func decodesCompleteFile() throws {
        let json = """
            {"version":1,"session_id":"abc-123","status":"needs","reason":"approval","tool":"Bash",
             "title":"Fix login","cwd":"/work/app","pid":4242,"stamp":"1700000000-77","updated_at":1700000000}
            """
        let record = try #require(SessionRecord(stateFileData: Data(json.utf8), fallbackID: "file-name"))
        #expect(record.id == "abc-123")
        #expect(record.status == .needs)
        #expect(record.reason == .approval)
        #expect(record.tool == "Bash")
        #expect(record.title == "Fix login")
        #expect(record.cwd == "/work/app")
        #expect(record.pid == 4242)
        #expect(record.stamp == "1700000000-77")
        #expect(record.updatedAt == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test("Missing fields fall back to safe defaults and the file name becomes the id")
    func fillsDefaults() throws {
        let record = try #require(SessionRecord(stateFileData: Data("{}".utf8), fallbackID: "from-file"))
        #expect(record.id == "from-file")
        #expect(record.status == .idle)
        #expect(record.reason == SessionRecord.Reason.none)
        #expect(record.pid == 0)
    }

    @Test("Unknown values from a newer hook script do not break decoding")
    func toleratesUnknownValues() throws {
        let json = #"{"status":"thinking-hard","reason":"telepathy","extra":[1,2,3]}"#
        let record = try #require(SessionRecord(stateFileData: Data(json.utf8), fallbackID: "x"))
        #expect(record.status == .idle)
        #expect(record.reason == SessionRecord.Reason.none)
    }

    @Test("Broken or partial files are skipped", arguments: ["", "not json", #"{"status":"#, "[1,2]"])
    func rejectsInvalidData(text: String) {
        #expect(SessionRecord(stateFileData: Data(text.utf8), fallbackID: "x") == nil)
    }

    @Test(
        "The display name prefers the title, then the folder, then a short id",
        arguments: [
            ("My task", "/work/app", "My task"),
            ("   ", "/work/app", "app"),
            ("", "", "Session 12345678"),
            ("", "/", "Session 12345678"),
        ])
    func displayName(title: String, cwd: String, expected: String) {
        let record = SessionRecord(id: "1234567890", status: .working, title: title, cwd: cwd)
        #expect(record.displayName == expected)
    }
}
