import AppKit

#if canImport(AttentionCore)
    import AttentionCore
#endif

/// The session card: a summary, one row per session and, at the bottom, the sleep slider. It
/// opens on hover or click (see `CardPresenter`), uses the system popover material so it follows
/// light and dark mode, and lets the user click a session to open it in the Claude desktop app.
/// Everything in it grows with `scale`, the card size from Settings.
@MainActor
public final class HoverCard {
    /// Called with `true` when the pointer enters the card and `false` when it leaves.
    public var onPointerInside: ((Bool) -> Void)?
    /// Called with the session id of a clicked row. Only rows that can be opened call it.
    public var onSelectSession: ((String) -> Void)?
    /// Called when the user chooses how long to sleep on the slider.
    public var onChooseSleep: ((SleepOption) -> Void)?
    /// Called when the user presses Wake up.
    public var onWake: (() -> Void)?

    /// The card size: 1 is normal, 2 is twice as big. Changing it rebuilds the card.
    public var scale: CGFloat = 1 {
        didSet {
            if scale != oldValue {
                rebuildFrame()
            }
        }
    }

    /// Whether the sleep slider shows at the bottom of the card.
    public var showsSleepSlider = true {
        didSet {
            if showsSleepSlider != oldValue {
                rebuildFrame()
            }
        }
    }

    private let panel: NSPanel
    private let background = CardBackgroundView()
    private let stack = NSStackView()
    public private(set) var content: HoverCardContent?
    private(set) var rowViews: [SessionRowView] = []
    /// The slider and the line above it; they stay in place when the rows are rebuilt, so a
    /// drag is never interrupted by a refresh.
    private(set) var sleepSlider: SleepSliderView?
    private var footerViews: [NSView] = []
    private var sleepState: (asleep: Bool, option: SleepOption?, remaining: String) = (false, nil, "")
    /// The pointer left the card during a drag; the card closes once the drag ends.
    private var exitedWhileDragging = false

    /// Widest the session text may get before it is truncated, at the normal size.
    static let textWidth: CGFloat = 250
    /// The card's fixed width at the normal size: the widest row (insets, dot, text, chevron) fits,
    /// and the card never changes width when a summary or the sleep text gets longer.
    static let width: CGFloat = 316
    private var widthConstraint: NSLayoutConstraint?
    static let cornerRadius: CGFloat = 10

    /// A small rounded rectangle that stretches to any size while keeping its corners.
    static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    /// The shape of the card, for tests.
    var backgroundMask: NSImage? {
        background.maskImage
    }
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
        background.onPointerInside = { [weak self] inside in self?.pointerInsideChanged(inside) }

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        panel.contentView = background
        rebuildFrame()
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
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
            panel.invalidateShadow()
        }
        panel.orderFrontRegardless()
    }

    public func hide() {
        panel.orderOut(nil)
        for row in rowViews {
            row.isHighlighted = false
        }
    }

    /// Shows the current sleep on the slider: asleep or not, the chosen stop and the time left.
    public func updateSleep(asleep: Bool, option: SleepOption?, remaining: String) {
        sleepState = (asleep, option, remaining)
        sleepSlider?.update(asleep: asleep, option: option, remaining: remaining)
    }

    /// The rows currently laid out, for tests.
    var rowCount: Int {
        rowViews.count
    }

    /// The size of the header text, for tests.
    var headerFontSize: CGFloat? {
        stack.arrangedSubviews.first.flatMap { wrapper in
            (wrapper.subviews.first as? NSTextField)?.font?.pointSize
        }
    }

    /// Reduce Motion keeps only the red blink, like the icon. Injectable for tests.
    var reduceMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    // MARK: Building

    /// Rebuilds everything that depends on the size or on the slider setting.
    private func rebuildFrame() {
        background.maskImage = Self.roundedMask(radius: Self.cornerRadius * scale)
        widthConstraint?.isActive = false
        widthConstraint = stack.widthAnchor.constraint(equalToConstant: Self.width * scale)
        widthConstraint?.isActive = true
        stack.spacing = 2 * scale
        stack.edgeInsets = NSEdgeInsets(top: 10 * scale, left: 6 * scale, bottom: 9 * scale, right: 6 * scale)
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        rowViews = []
        footerViews = []
        sleepSlider = nil

        if showsSleepSlider {
            let separator = NSBox()
            separator.boxType = .separator
            let line = padded(separator)
            let slider = SleepSliderView(scale: scale)
            slider.onChoose = { [weak self] option in self?.onChooseSleep?(option) }
            slider.onWake = { [weak self] in self?.onWake?() }
            slider.onTrackingEnded = { [weak self] in self?.dragEnded() }
            slider.update(asleep: sleepState.asleep, option: sleepState.option, remaining: sleepState.remaining)
            addFullWidth(line)
            stack.setCustomSpacing(6 * scale, after: line)
            addFullWidth(slider)
            footerViews = [line, slider]
            sleepSlider = slider
        }
        if let content {
            rebuild(with: content)
        }
    }

    /// Rebuilds the summary and the rows above the slider.
    private func rebuild(with content: HoverCardContent) {
        for view in stack.arrangedSubviews where !footerViews.contains(view) {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        rowViews = []
        var position = 0
        func add(_ view: NSView) {
            insertFullWidth(view, at: position)
            position += 1
        }

        let header = padded(label(content.header, size: 11, weight: .semibold, color: .secondaryLabelColor))
        add(header)
        stack.setCustomSpacing(4 * scale, after: header)

        for row in content.rows {
            let view = SessionRowView(row: row, scale: scale, reduceMotion: reduceMotion(), makeLabel: label)
            view.onSelect = { [weak self] sessionID in self?.onSelectSession?(sessionID) }
            rowViews.append(view)
            add(view)
        }
        if let overflow = content.overflow {
            add(padded(label(overflow, size: 11, weight: .regular, color: .secondaryLabelColor)))
        }
        if rowViews.contains(where: \.row.canOpen) {
            if let last = stack.arrangedSubviews.prefix(position).last {
                stack.setCustomSpacing(8 * scale, after: last)
            }
            add(padded(label(Self.hint, size: 10, weight: .regular, color: .tertiaryLabelColor)))
        }
        if let last = stack.arrangedSubviews.prefix(position).last, !footerViews.isEmpty {
            stack.setCustomSpacing(8 * scale, after: last)
        }
    }

    /// Adds a view that spans the card's width inside the side insets (plus `inset` on each side).
    private func addFullWidth(_ view: NSView, inset: CGFloat = 0) {
        insertFullWidth(view, at: stack.arrangedSubviews.count, inset: inset)
    }

    private func insertFullWidth(_ view: NSView, at index: Int, inset: CGFloat = 0) {
        stack.insertArrangedSubview(view, at: index)
        let insets = stack.edgeInsets.left + stack.edgeInsets.right + inset * 2
        view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -insets).isActive = true
    }

    /// Lines the header, overflow and hint up with the text inside the rows.
    private func padded(_ view: NSView) -> NSView {
        let wrapper = NSStackView(views: [view])
        wrapper.edgeInsets = NSEdgeInsets(top: 0, left: 8 * scale, bottom: 0, right: 8 * scale)
        wrapper.alignment = .leading
        if view is NSBox {
            wrapper.alignment = .centerY
            view.widthAnchor.constraint(equalTo: wrapper.widthAnchor, constant: -16 * scale).isActive = true
        }
        return wrapper
    }

    /// A one-line label; `size` is at the normal card size and grows with `scale`.
    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size * scale, weight: weight)
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        field.preferredMaxLayoutWidth = Self.textWidth * scale
        field.widthAnchor.constraint(lessThanOrEqualToConstant: Self.textWidth * scale).isActive = true
        return field
    }

    // MARK: Pointer

    /// Leaving the card mid-drag doesn't close it; the card closes when the drag ends instead.
    private func pointerInsideChanged(_ inside: Bool) {
        if !inside && sleepSlider?.isTracking == true {
            exitedWhileDragging = true
            return
        }
        exitedWhileDragging = false
        onPointerInside?(inside)
    }

    private func dragEnded() {
        guard exitedWhileDragging else {
            return
        }
        exitedWhileDragging = false
        if !panel.frame.contains(NSEvent.mouseLocation) {
            onPointerInside?(false)
        }
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

    let scale: CGFloat

    init(
        row: HoverCardContent.Row,
        scale: CGFloat = 1,
        reduceMotion: Bool = false,
        makeLabel: (String, CGFloat, NSFont.Weight, NSColor) -> NSTextField
    ) {
        self.row = row
        self.scale = scale
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("row")
        setAccessibilityElement(true)
        setAccessibilityRole(row.canOpen ? .button : .staticText)
        setAccessibilityLabel("\(row.title): \(row.detail)")

        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4 * scale
        dot.layer?.backgroundColor = IconStyle.forState(row.state).color
        dot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 8 * scale),
            dot.heightAnchor.constraint(equalToConstant: 8 * scale),
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
        text.spacing = 1 * scale

        var views: [NSView] = [dot, text, NSView()]
        if row.canOpen {
            let chevron = NSTextField(labelWithString: "›")
            chevron.font = .systemFont(ofSize: 15 * scale, weight: .regular)
            chevron.textColor = .tertiaryLabelColor
            views.append(chevron)
        }
        let line = NSStackView(views: views)
        line.orientation = .horizontal
        line.alignment = .centerY
        line.spacing = 8 * scale
        line.edgeInsets = NSEdgeInsets(top: 5 * scale, left: 8 * scale, bottom: 5 * scale, right: 8 * scale)
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
        NSBezierPath(roundedRect: bounds, xRadius: 6 * scale, yRadius: 6 * scale).fill()
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
