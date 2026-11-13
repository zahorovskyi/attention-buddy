import Foundation

/// Makes sure only one icon runs, however many launchers start it
/// (login item, plugin, Homebrew service).
///
/// Uses `flock`, so the lock frees itself when the process exits or crashes.
public final class InstanceLock {
    public let path: String
    private var descriptor: Int32 = -1

    public init(path: String) {
        self.path = path
    }

    /// The lock file used by the icon for a state directory.
    public static func iconLockPath(in directory: URL) -> String {
        directory.appendingPathComponent(".icon.lock").path
    }

    /// Takes the lock. Returns `false` if another process already holds it.
    public func acquire() -> Bool {
        let fd = open(path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else {
            return false
        }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            return false
        }
        descriptor = fd
        return true
    }

    /// Whether some process holds the lock right now, without keeping it.
    public static func isHeld(at path: String) -> Bool {
        let fd = open(path, O_RDWR)
        guard fd >= 0 else {
            return false
        }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            return true
        }
        flock(fd, LOCK_UN)
        return false
    }

    deinit {
        if descriptor >= 0 {
            close(descriptor)
        }
    }
}
