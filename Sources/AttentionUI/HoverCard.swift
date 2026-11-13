import AppKit

#if canImport(AttentionCore)
    import AttentionCore
#endif

/// The card shown while the pointer rests on the icon: a summary and one row per session.
/// It uses the system popover material, so it follows light and dark mode.
@MainActor
public final class HoverCard {
    private let panel: NSPanel
    private let background = NSVisualEffectView()
    private let stack = NSStackView()
    public private(set) var content: HoverCardContent?

    /// Widest the session text may get before it is truncated.
    static let textWidth: CGFloat = 250

    public init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false

        background.material = .popover
        background.state = .active
        background.blendingMode = .behindWindow
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        background.layer?.masksToBounds = true

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        panel.contentView = background
    }

    public var isVisible: Bool {
        panel.isVisible
    }

    /// Shows the card next to `iconFrame` (screen coordinates), or updates it if already shown.
    public func show(_ content: HoverCardContent, near iconFrame: CGRect) {
        if content != self.content {
            self.content = content
            rebuild(with: content)
        }
        let size = stack.fittingSize
        let screen =
            NSScreen.screens.first { $0.frame.intersects(iconFrame) }?.visibleFrame
            ?? NSScreen.main?.visibleFrame ?? iconFrame
        let frame = Placement.hoverCardFrame(cardSize: size, iconFrame: iconFrame, screen: screen)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    public func hide() {
        panel.orderOut(nil)
    }

    /// The rows currently laid out, for tests.
    var rowCount: Int {
        stack.arrangedSubviews.filter { $0.identifier?.rawValue == "row" }.count
    }

    private func rebuild(with content: HoverCardContent) {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let header = label(content.header, size: 11, weight: .semibold, color: .secondaryLabelColor)
        stack.addArrangedSubview(header)

        for row in content.rows {
            stack.addArrangedSubview(makeRow(row))
        }
        if let overflow = content.overflow {
            stack.addArrangedSubview(label(overflow, size: 11, weight: .regular, color: .secondaryLabelColor))
        }

        let hint = label(
            "Click to open · Right-click for options", size: 10, weight: .regular, color: .tertiaryLabelColor)
        stack.addArrangedSubview(hint)
        stack.setCustomSpacing(10, after: stack.arrangedSubviews[stack.arrangedSubviews.count - 2])
    }

    private func makeRow(_ row: HoverCardContent.Row) -> NSView {
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.layer?.backgroundColor = IconStyle.forState(row.state).color
        dot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
        ])

        let title = label(row.title, size: 13, weight: .medium, color: .labelColor)
        let detail = label(row.detail, size: 11, weight: .regular, color: .secondaryLabelColor)
        let text = NSStackView(views: [title, detail])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1

        let line = NSStackView(views: [dot, text])
        line.orientation = .horizontal
        line.alignment = .firstBaseline
        line.spacing = 8
        line.identifier = NSUserInterfaceItemIdentifier("row")
        // Keep the dot centered on the title line.
        dot.centerYAnchor.constraint(equalTo: title.centerYAnchor).isActive = true
        return line
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        field.preferredMaxLayoutWidth = Self.textWidth
        field.widthAnchor.constraint(lessThanOrEqualToConstant: Self.textWidth).isActive = true
        return field
    }
}
