import Foundation

/// One line of `attention-buddy doctor` output.
public struct DoctorCheck: Equatable, Sendable {
    public enum Level: String, Sendable {
        case ok
        case warning
        case problem
    }

    public var level: Level
    public var message: String

    public init(_ level: Level, _ message: String) {
        self.level = level
        self.message = message
    }
}

/// Facts about the machine that `doctor` looks at. The app gathers them, so the checks stay testable.
public struct DoctorInput: Sendable {
    /// Contents of `~/.claude/settings.json`, if it exists.
    public var userSettings: Data?
    /// Contents of the organization's managed settings files, if any.
    public var managedSettings: [Data]
    /// Contents of `~/.claude/plugins/installed_plugins.json`, if it exists.
    public var installedPlugins: Data?
    /// Whether `jq` was found where the hook script looks for it.
    public var jqAvailable: Bool
    public var stateDirectoryWritable: Bool
    public var iconRunning: Bool

    public init(
        userSettings: Data?,
        managedSettings: [Data],
        installedPlugins: Data?,
        jqAvailable: Bool,
        stateDirectoryWritable: Bool,
        iconRunning: Bool
    ) {
        self.userSettings = userSettings
        self.managedSettings = managedSettings
        self.installedPlugins = installedPlugins
        self.jqAvailable = jqAvailable
        self.stateDirectoryWritable = stateDirectoryWritable
        self.iconRunning = iconRunning
    }
}

/// The checks behind `attention-buddy doctor`.
public enum Doctor {
    /// Every hook command this project installs contains this text.
    public static let hookMarker = "attention-buddy-hook"
    public static let pluginName = "attention-buddy"

    public static func checks(for input: DoctorInput) -> [DoctorCheck] {
        var results: [DoctorCheck] = []

        let viaSettings = settingsContainOurHooks(input.userSettings)
        let viaPlugin = pluginInstalled(input.installedPlugins)
        if viaSettings && viaPlugin {
            results.append(
                DoctorCheck(
                    .warning,
                    "Installed twice (plugin and settings.json). It still works, but remove one: "
                        + "`attention-buddy setup --remove` or `/plugin uninstall attention-buddy`."))
        } else if viaSettings {
            results.append(DoctorCheck(.ok, "Hooks connected through ~/.claude/settings.json."))
        } else if viaPlugin {
            results.append(DoctorCheck(.ok, "Hooks connected through the Claude Code plugin."))
        } else {
            results.append(
                DoctorCheck(
                    .problem,
                    "Hooks are not connected, so the icon gets no events. "
                        + "Run `attention-buddy setup` or install the Claude Code plugin."))
        }

        if managedFlag("disableAllHooks", in: input.managedSettings) {
            results.append(
                DoctorCheck(
                    .problem, "Your organization's managed settings disable all hooks, so the icon gets no events."))
        } else if managedFlag("allowManagedHooksOnly", in: input.managedSettings) {
            results.append(
                DoctorCheck(
                    .problem,
                    "Your organization's managed settings allow only managed hooks, so the icon gets no events."))
        }

        if input.jqAvailable {
            results.append(DoctorCheck(.ok, "jq is available."))
        } else {
            results.append(
                DoctorCheck(
                    .problem, "jq was not found. macOS 15 and later include it; otherwise run `brew install jq`."))
        }

        if input.stateDirectoryWritable {
            results.append(DoctorCheck(.ok, "State folder is writable."))
        } else {
            results.append(DoctorCheck(.problem, "The state folder (~/.claude/attention-buddy) is not writable."))
        }

        if input.iconRunning {
            results.append(DoctorCheck(.ok, "The icon is running."))
        } else {
            results.append(
                DoctorCheck(
                    .warning,
                    "The icon is not running. Start it with `attention-buddy`; it also starts at login "
                        + "or with your next Claude Code session, depending on how you installed it."))
        }
        return results
    }

    /// Whether `settings.json` has at least one hook command from this project.
    public static func settingsContainOurHooks(_ data: Data?) -> Bool {
        guard let root = jsonObject(data), let events = root["hooks"] as? [String: Any] else {
            return false
        }
        for case let groups as [[String: Any]] in events.values {
            for group in groups {
                guard let handlers = group["hooks"] as? [[String: Any]] else {
                    continue
                }
                for handler in handlers {
                    if let command = handler["command"] as? String, command.contains(hookMarker) {
                        return true
                    }
                }
            }
        }
        return false
    }

    /// Whether Claude Code's plugin registry lists this project's plugin.
    public static func pluginInstalled(_ data: Data?) -> Bool {
        guard let root = jsonObject(data) else {
            return false
        }
        let prefix = pluginName + "@"
        if let plugins = root["plugins"] as? [String: Any] {
            return plugins.keys.contains { $0.hasPrefix(prefix) }
        }
        return root.keys.contains { $0.hasPrefix(prefix) }
    }

    /// Whether any managed settings file sets `key` to `true`.
    public static func managedFlag(_ key: String, in files: [Data]) -> Bool {
        files.contains { (jsonObject($0)?[key] as? Bool) == true }
    }

    private static func jsonObject(_ data: Data?) -> [String: Any]? {
        guard let data else {
            return nil
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
