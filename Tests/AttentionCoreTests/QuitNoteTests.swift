import Foundation
import Testing

@testable import AttentionCore

@Suite("Quit note")
struct QuitNoteTests {
    private let boot = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("attention-buddy-quit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Without a note nothing is quit")
    func noNote() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let note = QuitNote(directory: directory, bootTime: { [boot] in boot })
        #expect(!note.isActive)
    }

    @Test("A Quit since the Mac started keeps the icon closed")
    func activeAfterQuit() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let note = QuitNote(directory: directory, bootTime: { [boot] in boot })
        note.write(at: boot.addingTimeInterval(3600))
        #expect(note.isActive)
        #expect(note.recordedQuit == boot.addingTimeInterval(3600))
    }

    @Test("A Quit from before the last restart no longer counts")
    func expiredByRestart() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let note = QuitNote(directory: directory, bootTime: { [boot] in boot })
        note.write(at: boot.addingTimeInterval(-60))
        #expect(!note.isActive)
    }

    @Test("Starting the icon clears the note")
    func clear() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let note = QuitNote(directory: directory, bootTime: { [boot] in boot })
        note.write(at: boot.addingTimeInterval(10))
        note.clear()
        #expect(!note.isActive)
        #expect(!FileManager.default.fileExists(atPath: note.file.path))
    }

    @Test("A broken note is ignored; an unknown boot time keeps a valid note active")
    func edgeCases() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let note = QuitNote(directory: directory, bootTime: { nil })
        try Data("not a number".utf8).write(to: note.file)
        #expect(!note.isActive)
        note.write(at: boot)
        #expect(note.isActive)
    }

    @Test("The Mac's real start time is readable and in the past")
    func systemBootTime() throws {
        let start = try #require(QuitNote.systemBootTime())
        #expect(start < Date())
    }

    @Test("The note file is the one the shell scripts read")
    func fileName() {
        let note = QuitNote(directory: URL(fileURLWithPath: "/state"))
        #expect(note.file.path == "/state/.quit")
    }
}

@Suite("Doctor after Quit")
struct DoctorQuitTests {
    @Test("Doctor explains a Quit and how to start the icon")
    func quitMessage() {
        let settings = Data(#"{"hooks":{"Stop":[{"hooks":[{"command":"attention-buddy-hook.sh"}]}]}}"#.utf8)
        let input = DoctorInput(
            userSettings: settings, managedSettings: [], installedPlugins: nil, jqAvailable: true,
            stateDirectoryWritable: true, iconRunning: false, quitByUser: true)
        let last = Doctor.checks(for: input).last
        #expect(last?.level == .warning)
        #expect(last?.message.contains("you chose Quit") == true)
        #expect(last?.message.contains("/attention-buddy:start") == true)
    }

    @Test("Without a Quit, doctor says the next session starts it")
    func notRunningMessage() {
        let input = DoctorInput(
            userSettings: nil, managedSettings: [], installedPlugins: nil, jqAvailable: true,
            stateDirectoryWritable: true, iconRunning: false)
        #expect(Doctor.checks(for: input).last?.message.contains("next Claude Code session") == true)
    }
}
