import Foundation
import Testing

@testable import AttentionCore

/// A fresh temporary folder per test.
private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("attention-buddy-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func write(_ text: String, to name: String, in directory: URL) throws {
    try Data(text.utf8).write(to: directory.appendingPathComponent(name))
}

@Suite("Session store")
struct SessionStoreTests {
    @Test("Loads valid files, newest first, and skips temp, lock and broken files")
    func loadsValidFiles() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try write(#"{"status":"working","updated_at":10}"#, to: "old.json", in: directory)
        try write(#"{"status":"needs","updated_at":20}"#, to: "new.json", in: directory)
        try write(#"{"status":"done"}"#, to: "new.json.tmp.123", in: directory)
        try write(#"{"status":"done"}"#, to: ".hidden.json", in: directory)
        try write("{broken", to: "broken.json", in: directory)

        let sessions = SessionStore(directory: directory, isProcessAlive: { _ in true }).load()
        #expect(sessions.map(\.id) == ["new", "old"])
    }

    @Test("Sessions whose process has exited are removed from disk")
    func removesDeadSessions() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try write(#"{"status":"needs","pid":111}"#, to: "dead.json", in: directory)
        try write(#"{"status":"needs","pid":222}"#, to: "alive.json", in: directory)
        try write(#"{"status":"needs"}"#, to: "unknown-pid.json", in: directory)

        let store = SessionStore(directory: directory, isProcessAlive: { $0 == 222 })
        #expect(Set(store.load().map(\.id)) == ["alive", "unknown-pid"])
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("dead.json").path))
    }

    @Test("A missing folder means no sessions")
    func missingDirectory() {
        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        #expect(SessionStore(directory: missing).load().isEmpty)
    }

    @Test("Remove all deletes only session files")
    func removeAll() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try write("{}", to: "a.json", in: directory)
        try write("lock", to: ".icon.lock", in: directory)
        SessionStore(directory: directory).removeAll()
        let left = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(left == [".icon.lock"])
    }

    @Test("The current process counts as alive, a free pid does not")
    func processProbe() {
        #expect(ProcessProbe.isAlive(getpid()))
        #expect(!ProcessProbe.isAlive(Int32.max))
    }
}

@Suite("Single instance")
struct InstanceLockTests {
    @Test("A second lock on the same file fails until the first is released")
    func exclusive() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = InstanceLock.iconLockPath(in: directory)

        var first: InstanceLock? = InstanceLock(path: path)
        #expect(first?.acquire() == true)
        #expect(InstanceLock.isHeld(at: path))
        #expect(InstanceLock(path: path).acquire() == false)

        first = nil
        #expect(!InstanceLock.isHeld(at: path))
        #expect(InstanceLock(path: path).acquire() == true)
    }
}

@Suite("Placement")
struct PlacementTests {
    let size = CGSize(width: 40, height: 30)
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)

    @Test("The default spot is near the top-right corner")
    func defaultOrigin() {
        #expect(Placement.defaultOrigin(size: size, visibleFrame: screen) == CGPoint(x: 1376, y: 821))
    }

    @Test("A position on screen is kept")
    func keepsVisible() {
        let origin = CGPoint(x: 100, y: 100)
        #expect(Placement.clamp(origin: origin, size: size, screens: [screen]) == origin)
    }

    @Test("A position on an unplugged monitor moves back to the default spot")
    func movesOffscreen() {
        let origin = CGPoint(x: 3000, y: 100)
        #expect(Placement.clamp(origin: origin, size: size, screens: [screen]) == CGPoint(x: 1376, y: 821))
    }
}

@Suite("Text")
struct StateTextTests {
    @Test("Waiting sessions say what they need")
    func details() {
        let approval = SessionRecord(id: "a", status: .needs, reason: .approval, tool: "Bash")
        let question = SessionRecord(id: "b", status: .needs, reason: .question, tool: "AskUserQuestion")
        let input = SessionRecord(id: "c", status: .needs, reason: .input)
        #expect(StateText.detail(for: approval, state: .needsYou) == "Needs your approval for Bash")
        #expect(StateText.detail(for: question, state: .seen) == "Has a question for you (seen)")
        #expect(StateText.detail(for: input, state: .needsYou) == "Needs your input")
        #expect(StateText.detail(for: SessionRecord(id: "d", status: .done), state: .done) == "Done")
    }

    @Test("The tooltip lists sessions, or says there are none")
    func tooltip() {
        #expect(StateText.tooltip(for: []) == "Attention Buddy: no Claude Code sessions yet")
        let record = SessionRecord(id: "a", status: .working, title: "Refactor")
        #expect(StateText.tooltip(for: [(record, .working)]) == "Refactor: Working")
    }
}

@Suite("Doctor")
struct DoctorTests {
    private let settingsWithHook = Data(
        #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"\"/x/attention-buddy-hook.sh\""}]}]}}"#.utf8)
    private let plugins = Data(#"{"version":2,"plugins":{"attention-buddy@attention-buddy":[{}]}}"#.utf8)

    private func input(
        settings: Data? = nil,
        managed: [Data] = [],
        plugins: Data? = nil,
        jq: Bool = true,
        running: Bool = true
    ) -> DoctorInput {
        DoctorInput(
            userSettings: settings, managedSettings: managed, installedPlugins: plugins,
            jqAvailable: jq, stateDirectoryWritable: true, iconRunning: running)
    }

    @Test("Finds hooks in settings.json and the plugin in the registry")
    func detection() {
        #expect(Doctor.settingsContainOurHooks(settingsWithHook))
        #expect(!Doctor.settingsContainOurHooks(Data(#"{"hooks":{"Stop":[{"hooks":[{"command":"other"}]}]}}"#.utf8)))
        #expect(!Doctor.settingsContainOurHooks(Data("not json".utf8)))
        #expect(Doctor.pluginInstalled(plugins))
        #expect(!Doctor.pluginInstalled(Data(#"{"plugins":{"other@x":[]}}"#.utf8)))
    }

    @Test("A healthy setup has no problems")
    func healthy() {
        let checks = Doctor.checks(for: input(settings: settingsWithHook))
        #expect(checks.allSatisfy { $0.level == .ok })
    }

    @Test("Missing hooks, missing jq and a stopped icon are reported")
    func reportsProblems() {
        let levels = Doctor.checks(for: input(jq: false, running: false)).map(\.level)
        #expect(levels.filter { $0 == .problem }.count == 2)
        #expect(levels.contains(.warning))
    }

    @Test("Installing twice is a warning")
    func installedTwice() {
        let checks = Doctor.checks(for: input(settings: settingsWithHook, plugins: plugins))
        #expect(checks.first?.level == .warning)
    }

    @Test(
        "Organization settings that block hooks are reported",
        arguments: [#"{"allowManagedHooksOnly":true}"#, #"{"disableAllHooks":true}"#])
    func managedSettings(json: String) {
        let checks = Doctor.checks(for: input(settings: settingsWithHook, managed: [Data(json.utf8)]))
        #expect(checks.contains { $0.level == .problem && $0.message.contains("organization") })
    }
}
