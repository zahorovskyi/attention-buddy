import Foundation

/// Calls `onChange` as soon as a file is added, replaced or removed in a folder,
/// so the icon reacts instantly instead of waiting for the next poll.
@MainActor
public final class StateFolderWatcher {
    private var source: DispatchSourceFileSystemObject?

    public init() {}

    /// Starts watching. Returns `false` if the folder can't be opened (the poll still works).
    @discardableResult
    public func start(watching directory: URL, onChange: @escaping @MainActor () -> Void) -> Bool {
        stop()
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else {
            return false
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )
        source.setEventHandler {
            MainActor.assumeIsolated {
                onChange()
            }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        self.source = source
        return true
    }

    public func stop() {
        source?.cancel()
        source = nil
    }
}
