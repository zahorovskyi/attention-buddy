import AppKit

#if canImport(AttentionCore)
    import AttentionCore
#endif

/// The session card: a summary and one row per session. It opens on hover or click (see
/// `CardPresenter`), uses the system popover material so it follows light and dark mode, and
/// lets the user click a session to open it in the Claude desktop app.
@MainActor
public final class HoverCard {
    /// Called with `true` when the pointer enters the card and `false` when it leaves.
    public var onPointerInside: ((Bool) -> Void)?
    /// Called with the session id of a clicked row. Only rows that can be opened call it.
    public var onSelectSession: ((String) -> Void)?

    private let panel: NSPanel
    private let background = CardBackgroundView()
    private let stack = NSStackView()
    public private(set) var content: HoverCardContent?
    private(set) var rowViews: [SessionRowView] = []

    /// Widest the session text may get before it is truncated.
    static let textWidth: CGFloat = 250
    static let hint = "Click a session to open it"

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
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false

        background.material = .popover
        background.state = .active
        background.blendingMode = .behindWindow
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        background.layer?.masksToBounds = true
        background.onPointerInside = { [weak self] inside in self?.onPointerInside?(inside) }

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 6, bottom: 9, right: 6)
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

    /// The card's frame on screen, used to tell clicks on the card from clicks elsewhere.
    public var frame: CGRect {
        panel.frame
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
        for row in rowViews {
            row.isHighlighted = false
        }
    }

    /// The rows currently laid out, for tests.
    var rowCount: Int {
        rowViews.count
    }

    /// Reduce Motion keeps only the red blink, like the icon. Injectable for tests.
    var reduceMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private func rebuild(with content: HoverCardContent) {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        rowViews = []

        addFullWidth(padded(label(content.header, size: 11, weight: .semibold, color: .secondaryLabelColor)))
        stack.setCustomSpacing(4, after: stack.arrangedSubviews[0])

        for row in content.rows {
            let view = SessionRowView(row: row, reduceMotion: reduceMotion(), makeLabel: label)
            view.onSelect = { [weak self] sessionID in self?.onSelectSession?(sessionID) }
            rowViews.append(view)
            addFullWidth(view)
        }
        if let overflow = content.overflow {
            addFullWidth(padded(label(overflow, size: 11, weight: .regular, color: .secondaryLabelColor)))
        }
        if rowViews.contains(where: \.row.canOpen) {
            let hint = padded(label(Self.hint, size: 10, weight: .regular, color: .tertiaryLabelColor))
            stack.setCustomSpacing(8, after: stack.arrangedSubviews[stack.arrangedSubviews.count - 1])
            addFullWidth(hint)
        }
    }

    /// Adds a view that spans the card's width inside the side insets.
    private func addFullWidth(_ view: NSView) {
        stack.addArrangedSubview(view)
        let insets = stack.edgeInsets.left + stack.edgeInsets.right
        view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -insets).isActive = true
    }

    /// Lines the header, overflow and hint up with the text inside the rows.
    private func padded(_ view: NSView) -> NSView {
        let wrapper = NSStackView(views: [view])
        wrapper.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        wrapper.alignment = .leading
        return wrapper
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

/// The card's background: reports when the pointer enters or leaves it.
@MainActor
final class CardBackgroundView: NSVisualEffectView {
    var onPointerInside: ((Bool) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(
            NSTrackingArea(
                rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self,
                userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        onPointerInside?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onPointerInside?(false)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

/// One session in the card. Rows that can be opened highlight under the pointer, show a chevron
/// and report clicks; terminal sessions are dimmed and inert.
@MainActor
final class SessionRowView: NSView {
    let row: HoverCardContent.Row
    /// The colored dot; it blinks for sessions that need you and breathes while working.
    let dot = NSView()
    var onSelect: ((String) -> Void)?
    var isHighlighted = false {
        didSet { needsDisplay = true }
    }

    init(
        row: HoverCardContent.Row,
        reduceMotion: Bool = false,
        makeLabel: (String, CGFloat, NSFont.Weight, NSColor) -> NSTextField
    ) {
        self.row = row
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("row")
        setAccessibilityElement(true)
        setAccessibilityRole(row.canOpen ? .button : .staticText)
        setAccessibilityLabel("\(row.title): \(row.detail)")

        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.layer?.backgroundColor = IconStyle.forState(row.state).color
        dot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
        ])
        // Same rhythm as the icon: "needs you" blinks (kept with Reduce Motion, as the main
        // signal); "working" breathes slowly; seen, done, error and idle stay steady.
        switch row.state {
        case .needsYou:
            dot.layer?.add(IconAnimations.pulse(), forKey: "pulse")
        case .working where !reduceMotion:
            dot.layer?.add(IconAnimations.breathe(), forKey: "breathe")
        default:
            break
        }

        let titleColor: NSColor = row.canOpen ? .labelColor : .secondaryLabelColor
        let title = makeLabel(row.title, 13, .medium, titleColor)
        let detail = makeLabel(row.detail, 11, .regular, .secondaryLabelColor)
        let text = NSStackView(views: [title, detail])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1

        var views: [NSView] = [dot, text, NSView()]
        if row.canOpen {
            let chevron = NSTextField(labelWithString: "›")
            chevron.font = .systemFont(ofSize: 15, weight: .regular)
            chevron.textColor = .tertiaryLabelColor
            views.append(chevron)
        }
        let line = NSStackView(views: views)
        line.orientation = .horizontal
        line.alignment = .centerY
        line.spacing = 8
        line.edgeInsets = NSEdgeInsets(top: 5, left: 8, bottom: 5, right: 8)
        line.translatesAutoresizingMaskIntoConstraints = false
        addSubview(line)
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: leadingAnchor),
            line.trailingAnchor.constraint(equalTo: trailingAnchor),
            line.topAnchor.constraint(equalTo: topAnchor),
            line.bottomAnchor.constraint(equalTo: bottomAnchor),
            dot.centerYAnchor.constraint(equalTo: title.centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SessionRowView is created in code only")
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isHighlighted else {
            return
        }
        NSColor.labelColor.withAlphaComponent(0.1).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        guard row.canOpen else {
            return
        }
        addTrackingArea(
            NSTrackingArea(
                rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self,
                userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        isHighlighted = true
    }

    override func mouseExited(with event: NSEvent) {
        isHighlighted = false
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        // Handled on mouse up, like a menu item.
    }

    override func mouseUp(with event: NSEvent) {
        guard row.canOpen, bounds.contains(convert(event.locationInWindow, from: nil)) else {
            return
        }
        select()
    }

    /// Opens the row's session, as a click does.
    func select() {
        guard row.canOpen else {
            return
        }
        onSelect?(row.sessionID)
    }
}
