import AppKit

#if canImport(AttentionCore)
    import AttentionCore
#endif
#if canImport(AttentionUI)
    import AttentionUI
#endif

// Entry point. With no arguments it runs the floating icon; other commands are small helpers.

let usage = """
    Attention Buddy \(AppVersion.current): a floating Claude Code icon that waves when a session needs you.

    Usage:
      attention-buddy                   Run the floating icon (only one copy runs at a time)
      attention-buddy setup             Connect Claude Code: add the hooks to ~/.claude/settings.json
      attention-buddy setup --remove    Remove those hooks again
      attention-buddy doctor            Check that everything is connected
      attention-buddy snapshot <dir>    Save PNG images of every icon state into <dir>
      attention-buddy --version         Print the version

    More: https://github.com/zahorovskyi/attention-buddy
    """

/// Keeps the app's delegate alive for the whole run (NSApplication holds it weakly).
var appController: AppController?

@MainActor
func runIcon() -> Int32 {
    let directory = SessionStore.defaultDirectory
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let lock = InstanceLock(path: InstanceLock.iconLockPath(in: directory))
    guard lock.acquire() else {
        print("Attention Buddy is already running.")
        return 0
    }
    let preferences = UserDefaults(suiteName: AttentionSettings.defaultsDomain) ?? .standard
    let controller = AppController(
        store: SessionStore(directory: directory),
        settings: AttentionSettings(defaults: preferences),
        preferences: preferences
    )
    appController = controller
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.delegate = controller
    withExtendedLifetime(lock) {
        app.run()
    }
    return 0
}

/// `~/.claude`, or `$CLAUDE_CONFIG_DIR` when set.
func claudeConfigDirectory() -> URL {
    if let custom = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !custom.isEmpty {
        return URL(fileURLWithPath: custom, isDirectory: true)
    }
    return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true)
}

func readFile(_ url: URL) -> Data? {
    try? Data(contentsOf: url)
}

func managedSettingsFiles() -> [Data] {
    let base = URL(fileURLWithPath: "/Library/Application Support/ClaudeCode", isDirectory: true)
    var files: [Data] = []
    if let main = readFile(base.appendingPathComponent("managed-settings.json")) {
        files.append(main)
    }
    let dropIns = base.appendingPathComponent("managed-settings.d", isDirectory: true)
    let names = (try? FileManager.default.contentsOfDirectory(atPath: dropIns.path)) ?? []
    for name in names.sorted() where name.hasSuffix(".json") {
        if let data = readFile(dropIns.appendingPathComponent(name)) {
            files.append(data)
        }
    }
    return files
}

/// The hook script looks for jq in the same places.
func jqAvailable() -> Bool {
    var candidates = ["/usr/bin/jq", "/opt/homebrew/bin/jq", "/usr/local/bin/jq"]
    let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
    candidates += path.split(separator: ":").map { "\($0)/jq" }
    return candidates.contains { FileManager.default.isExecutableFile(atPath: $0) }
}

func runDoctor() -> Int32 {
    let config = claudeConfigDirectory()
    let stateDirectory = SessionStore.defaultDirectory
    try? FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
    let input = DoctorInput(
        userSettings: readFile(config.appendingPathComponent("settings.json")),
        managedSettings: managedSettingsFiles(),
        installedPlugins: readFile(config.appendingPathComponent("plugins/installed_plugins.json")),
        jqAvailable: jqAvailable(),
        stateDirectoryWritable: FileManager.default.isWritableFile(atPath: stateDirectory.path),
        iconRunning: InstanceLock.isHeld(at: InstanceLock.iconLockPath(in: stateDirectory))
    )
    print("Attention Buddy \(AppVersion.current)")
    let checks = Doctor.checks(for: input)
    for check in checks {
        let mark: String
        switch check.level {
        case .ok:
            mark = "✓"
        case .warning:
            mark = "!"
        case .problem:
            mark = "✗"
        }
        print("\(mark) \(check.message)")
    }
    return checks.contains { $0.level == .problem } ? 1 : 0
}

/// The folder this binary was started from, without resolving symlinks, so a Homebrew
/// install keeps pointing at its stable `bin` folder rather than a versioned one.
func executableDirectory() -> URL? {
    let invoked = CommandLine.arguments[0]
    if invoked.contains("/") {
        return URL(fileURLWithPath: invoked).deletingLastPathComponent()
    }
    let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
    for folder in path.split(separator: ":") {
        let candidate = URL(fileURLWithPath: String(folder)).appendingPathComponent(invoked)
        if FileManager.default.isExecutableFile(atPath: candidate.path) {
            return candidate.deletingLastPathComponent()
        }
    }
    return nil
}

func runSetup(_ arguments: [String]) -> Int32 {
    guard let binDirectory = executableDirectory() else {
        fputs("Could not find where attention-buddy is installed.\n", stderr)
        return 1
    }
    let prefix = binDirectory.deletingLastPathComponent()
    let installer = prefix.appendingPathComponent("share/attention-buddy/install.sh")
    guard FileManager.default.fileExists(atPath: installer.path) else {
        fputs("The installer script was not found at \(installer.path).\n", stderr)
        return 1
    }
    let remove = arguments.contains("--remove")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = [installer.path, remove ? "--remove-hooks" : "--hooks-only", "--prefix", prefix.path]
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    } catch {
        fputs("Could not run the installer: \(error.localizedDescription)\n", stderr)
        return 1
    }
}

@MainActor
func runSnapshot(_ arguments: [String]) -> Int32 {
    guard let folder = arguments.first else {
        fputs("Usage: attention-buddy snapshot <dir> [--scale <points per pixel>]\n", stderr)
        return 2
    }
    var scale: CGFloat = 8
    if let index = arguments.firstIndex(of: "--scale"), index + 1 < arguments.count,
        let value = Double(arguments[index + 1])
    {
        scale = CGFloat(value)
    }
    let directory = URL(fileURLWithPath: folder, isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var images: [(name: String, state: IconState, pose: SnapshotRenderer.Pose)] = IconState.allCases.map {
            ("\($0)", $0, .rest)
        }
        images.append(("pose-waving", .needsYou, .waving))
        images.append(("pose-arms-up", .done, .armsUp))
        for image in images {
            guard let png = SnapshotRenderer.png(state: image.state, pose: image.pose, scale: scale) else {
                fputs("Could not render \(image.name).\n", stderr)
                return 1
            }
            try png.write(to: directory.appendingPathComponent("\(image.name).png"))
        }
        print("Saved \(images.count) images to \(directory.path)")
        return 0
    } catch {
        fputs("Could not save images: \(error.localizedDescription)\n", stderr)
        return 1
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
let status: Int32
switch arguments.first {
case nil, "run":
    status = runIcon()
case "setup":
    status = runSetup(Array(arguments.dropFirst()))
case "doctor":
    status = runDoctor()
case "snapshot":
    status = runSnapshot(Array(arguments.dropFirst()))
case "--version", "version":
    print(AppVersion.current)
    status = 0
case "--help", "-h", "help":
    print(usage)
    status = 0
default:
    fputs("Unknown command: \(arguments[0])\n\n\(usage)\n", stderr)
    status = 2
}
exit(status)
