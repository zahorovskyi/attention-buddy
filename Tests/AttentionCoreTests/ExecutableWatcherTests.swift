import Foundation
import Testing

@testable import AttentionCore

@Suite("Noticing an update")
struct ExecutableWatcherTests {
    private func makeExecutable(in directory: URL, named name: String = "attention-buddy", content: String = "v1")
        throws -> URL
    {
        let file = directory.appendingPathComponent(name)
        try Data("#!/bin/sh\necho \(content)\n".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return file
    }

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("attention-buddy-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("An untouched program file is not an update")
    func unchanged() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try makeExecutable(in: directory)
        #expect(!ExecutableWatcher(path: file.path).hasBeenReplaced())
    }

    @Test("A new file moved into place, as installers and plugin builds do, is an update")
    func movedIntoPlace() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try makeExecutable(in: directory)
        let watcher = ExecutableWatcher(path: file.path)
        let newVersion = try makeExecutable(in: directory, named: "new", content: "v2")
        _ = try FileManager.default.replaceItemAt(file, withItemAt: newVersion)
        #expect(watcher.hasBeenReplaced())
    }

    @Test("A switched symlink, as with Homebrew's opt link after an upgrade, is an update")
    func symlinkSwitched() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let old = try makeExecutable(in: directory, named: "v1", content: "v1")
        let new = try makeExecutable(in: directory, named: "v2", content: "v2")
        let link = directory.appendingPathComponent("opt-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: old)
        let watcher = ExecutableWatcher(path: link.path)
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: new)
        #expect(watcher.hasBeenReplaced())
    }

    @Test("A missing file halfway through an update is not a reason to restart yet")
    func missingFile() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try makeExecutable(in: directory)
        let watcher = ExecutableWatcher(path: file.path)
        try FileManager.default.removeItem(at: file)
        #expect(!watcher.hasBeenReplaced())
    }

    @Test("The launch path is found for absolute, relative and PATH-based starts")
    func launchPath() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try makeExecutable(in: directory)
        #expect(ExecutableWatcher.launchPath(arguments: [file.path]) == file.path)
        #expect(
            ExecutableWatcher.launchPath(arguments: ["./attention-buddy"], currentDirectory: directory.path)
                == file.path)
        #expect(
            ExecutableWatcher.launchPath(arguments: ["attention-buddy"], environment: ["PATH": directory.path])
                == file.path)
        #expect(
            ExecutableWatcher.launchPath(arguments: ["attention-buddy"], environment: ["PATH": "/nonexistent"]) == nil)
    }
}
