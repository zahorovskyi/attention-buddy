import AppKit

#if canImport(AttentionCore)
    import AttentionCore
#endif

/// A small borderless window that floats above other apps, on every desktop and over
/// full-screen apps, without ever taking focus away from what the user is doing.
@MainActor
public final class FloatingPanel: NSPanel {
    public init(contentView: NSView) {
        super.init(
            contentRect: NSRect(origin: .zero, size: contentView.frame.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.contentView = contentView
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        allowsToolTipsWhenApplicationIsInactive = true
    }

    /// Swaps in a view of a different size and resizes the window to fit it, keeping the edges
    /// nearest the screen corner in place (see `Placement.resizedOrigin`).
    ///
    /// The new size is read before the swap: assigning `contentView` resizes the view to the
    /// window's current size, which would otherwise clip a bigger view.
    public func replaceContent(with view: NSView, screens: [CGRect]) {
        let newSize = view.frame.size
        let origin = Placement.resizedOrigin(from: frame, to: newSize, screens: screens)
        setFrame(NSRect(origin: origin, size: newSize), display: false)
        contentView = view
        view.frame = NSRect(origin: .zero, size: newSize)
        display()
    }

    public override var canBecomeKey: Bool {
        false
    }

    public override var canBecomeMain: Bool {
        false
    }
}
