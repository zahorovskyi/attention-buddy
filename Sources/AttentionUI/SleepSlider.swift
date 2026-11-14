import AppKit
import QuartzCore

#if canImport(AttentionCore)
    import AttentionCore
#endif

/// The sleep slider at the bottom of the session card: seven stops from 15 minutes to the end
/// of the day. Drag the knob (or click a stop) and let go to put the icon to sleep; while asleep
/// a Wake up button ends it.
///
/// The knob follows the pointer while dragging, the nearest stop lights up (with a light click on
/// a Force Touch trackpad), and on release the knob springs onto that stop. All sizes are
/// multiplied by `scale`, the card size from Settings.
@MainActor
final class SleepSliderView: NSView {
    /// Called when the user lets go of the knob, clicks a stop or steps the slider with VoiceOver.
    var onChoose: ((SleepOption) -> Void)?
    /// Called when the user presses Wake up.
    var onWake: (() -> Void)?
    /// Called when a drag ends, so the card can close if the pointer left it meanwhile.
    var onTrackingEnded: (() -> Void)?
    /// The text after a stop's name while dragging, for example "until 12:47".
    var untilText: (SleepOption) -> String = { option in
        SleepSchedule.untilText(option.wakeTime(from: Date()))
    }

    let scale: CGFloat
    private(set) var isTracking = false
    /// The stop the knob is on or nearest to while dragging.
    private(set) var selectedOption: SleepOption?
    private(set) var isAsleep = false
    private var remaining = ""
    /// Knob position from 0 (first stop) to 1 (last stop).
    private(set) var position: CGFloat = 0

    let statusLeft = NSTextField(labelWithString: "")
    let statusRight = NSTextField(labelWithString: "")
    let wakeButton: WakeButtonView
    private(set) var stopLabels: [NSTextField] = []
    private let trackLayer = CAShapeLayer()
    private let fillLayer = CAShapeLayer()
    private let knobLayer = CAShapeLayer()
    private var tickLayers: [CAShapeLayer] = []

    private static let options = SleepOption.allCases
    private static let baseHeight: CGFloat = 66
    /// Narrowest the slider gets, so seven labels always fit.
    static let baseMinimumWidth: CGFloat = 236

    init(scale: CGFloat) {
        self.scale = scale
        wakeButton = WakeButtonView(scale: scale)
        super.init(frame: NSRect(x: 0, y: 0, width: Self.baseMinimumWidth * scale, height: Self.baseHeight * scale))
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
        setAccessibilityLabel("Sleep")

        for field in [statusLeft, statusRight] {
            field.font = .systemFont(ofSize: 11 * scale, weight: field === statusLeft ? .medium : .regular)
            field.lineBreakMode = .byTruncatingTail
            addSubview(field)
        }
        statusRight.alignment = .right
        wakeButton.onPress = { [weak self] in self?.onWake?() }
        addSubview(wakeButton)

        for layer in [trackLayer, fillLayer] {
            layer.fillColor = nil
            layer.lineWidth = 6 * scale
            layer.lineCap = .round
            self.layer?.addSublayer(layer)
        }
        trackLayer.strokeColor = CGColor(srgbRed: 0x88 / 255, green: 0x87 / 255, blue: 0x80 / 255, alpha: 0.3)
        fillLayer.strokeColor = Palette.night
        fillLayer.strokeEnd = 0
        for option in Self.options {
            let tick = CAShapeLayer()
            self.layer?.addSublayer(tick)
            tickLayers.append(tick)
            let label = NSTextField(labelWithString: option.shortLabel)
            label.font = .systemFont(ofSize: 11 * scale)
            label.alignment = .center
            addSubview(label)
            stopLabels.append(label)
        }
        knobLayer.lineWidth = 2.5 * scale
        knobLayer.strokeColor = Palette.night
        self.layer?.addSublayer(knobLayer)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.baseHeight * scale),
            widthAnchor.constraint(greaterThanOrEqualToConstant: Self.baseMinimumWidth * scale),
        ])
        refreshTexts()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SleepSliderView is created in code only")
    }

    override var isFlipped: Bool {
        true
    }

    // MARK: Geometry

    private var trackY: CGFloat { 36 * scale }
    /// Half a label's width: the track ends this far in, so "15m" and "Today" fit inside.
    private var labelWidth: CGFloat { 44 * scale }
    private var trackStart: CGFloat { labelWidth / 2 }
    private var trackEnd: CGFloat { bounds.width - labelWidth / 2 }

    /// The x position of a point on the track, from 0 (first stop) to 1 (last stop).
    func x(at position: CGFloat) -> CGFloat {
        trackStart + (trackEnd - trackStart) * position
    }

    /// The track position under an x coordinate, kept between the first and last stop.
    func position(atX x: CGFloat) -> CGFloat {
        guard trackEnd > trackStart else {
            return 0
        }
        return min(max((x - trackStart) / (trackEnd - trackStart), 0), 1)
    }

    static func position(of option: SleepOption) -> CGFloat {
        CGFloat(option.rawValue) / CGFloat(options.count - 1)
    }

    static func nearestOption(to position: CGFloat) -> SleepOption {
        let index = Int((position * CGFloat(options.count - 1)).rounded())
        return options[min(max(index, 0), options.count - 1)]
    }

    override func layout() {
        super.layout()
        let rowHeight = 16 * scale
        let buttonSize = wakeButton.intrinsicContentSize
        wakeButton.frame = NSRect(
            x: bounds.width - 8 * scale - buttonSize.width, y: 0, width: buttonSize.width, height: buttonSize.height)
        statusLeft.frame = NSRect(x: 8 * scale, y: 2 * scale, width: bounds.width * 0.62, height: rowHeight)
        statusRight.frame = NSRect(
            x: bounds.width * 0.5, y: 2 * scale, width: bounds.width * 0.5 - 8 * scale, height: rowHeight)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let line = CGMutablePath()
        line.move(to: CGPoint(x: trackStart, y: trackY))
        line.addLine(to: CGPoint(x: trackEnd, y: trackY))
        trackLayer.path = line
        fillLayer.path = line
        let tickRadius = 2 * scale
        for (index, tick) in tickLayers.enumerated() {
            let center = CGPoint(x: x(at: Self.position(of: Self.options[index])), y: trackY)
            tick.path = CGPath(
                ellipseIn: CGRect(
                    x: center.x - tickRadius, y: center.y - tickRadius, width: tickRadius * 2,
                    height: tickRadius * 2), transform: nil)
        }
        let knobRadius = 8 * scale
        knobLayer.bounds = CGRect(x: 0, y: 0, width: knobRadius * 2, height: knobRadius * 2)
        knobLayer.path = CGPath(ellipseIn: knobLayer.bounds.insetBy(dx: 1, dy: 1), transform: nil)
        knobLayer.position = CGPoint(x: x(at: position), y: trackY)
        CATransaction.commit()

        for (index, label) in stopLabels.enumerated() {
            let centerX = x(at: Self.position(of: Self.options[index]))
            label.frame = NSRect(
                x: centerX - labelWidth / 2, y: trackY + 10 * scale, width: labelWidth, height: rowHeight)
        }
        refreshColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }

    // MARK: State from the app

    /// Shows the current sleep. Ignored while the user drags, so the knob stays under the pointer.
    func update(asleep: Bool, option: SleepOption?, remaining: String) {
        let changed = asleep != isAsleep || (asleep && option != selectedOption)
        isAsleep = asleep
        self.remaining = remaining
        guard !isTracking else {
            return
        }
        if asleep {
            selectedOption = option
        } else {
            selectedOption = nil
        }
        if changed {
            let target = selectedOption.map(Self.position(of:)) ?? 0
            move(to: target, animation: .ease)
        }
        refreshTexts()
    }

    // MARK: Dragging

    /// Starts a drag (or a click on a stop) at `x`, in the view's coordinates.
    func beginDrag(atX x: CGFloat) {
        isTracking = true
        selectedOption = Self.nearestOption(to: position(atX: x))
        move(to: position(atX: x), animation: .none)
        refreshTexts()
    }

    func drag(toX x: CGFloat) {
        guard isTracking else {
            return
        }
        let newPosition = position(atX: x)
        let nearest = Self.nearestOption(to: newPosition)
        if nearest != selectedOption {
            selectedOption = nearest
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            refreshTexts()
        }
        move(to: newPosition, animation: .none)
    }

    /// Ends a drag: the knob springs onto the nearest stop and that sleep starts.
    func endDrag() {
        guard isTracking else {
            return
        }
        isTracking = false
        let option = Self.nearestOption(to: position)
        selectedOption = option
        move(to: Self.position(of: option), animation: .spring)
        refreshTexts()
        onChoose?(option)
        onTrackingEnded?()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let nearTrack = point.y > trackY - 14 * scale && point.y < bounds.height
        let alongTrack = point.x > trackStart - 12 * scale && point.x < trackEnd + 12 * scale
        guard nearTrack && alongTrack else {
            return
        }
        beginDrag(atX: point.x)
    }

    override func mouseDragged(with event: NSEvent) {
        drag(toX: convert(event.locationInWindow, from: nil).x)
    }

    override func mouseUp(with event: NSEvent) {
        endDrag()
    }

    // MARK: VoiceOver

    override func accessibilityValue() -> Any? {
        guard isAsleep else {
            return "Awake"
        }
        if let selectedOption {
            return "Asleep, \(selectedOption.title), \(remaining) left"
        }
        return "Asleep, \(remaining) left"
    }

    override func accessibilityPerformIncrement() -> Bool {
        step(by: 1)
    }

    override func accessibilityPerformDecrement() -> Bool {
        step(by: -1)
    }

    /// Chooses the next or previous stop, as a drag to it would.
    private func step(by offset: Int) -> Bool {
        let current = isAsleep ? (selectedOption?.rawValue ?? -1) : -1
        let next = min(max(current + offset, 0), Self.options.count - 1)
        guard next != current, let option = SleepOption(rawValue: next) else {
            return false
        }
        selectedOption = option
        move(to: Self.position(of: option), animation: .spring)
        onChoose?(option)
        return true
    }

    // MARK: Drawing

    private enum Motion {
        case none
        case ease
        case spring
    }

    private func move(to newPosition: CGFloat, animation: Motion) {
        let oldKnob = knobLayer.presentation()?.position ?? knobLayer.position
        let oldEnd = fillLayer.presentation()?.strokeEnd ?? fillLayer.strokeEnd
        position = newPosition
        let newKnob = CGPoint(x: x(at: newPosition), y: trackY)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        knobLayer.position = newKnob
        fillLayer.strokeEnd = newPosition
        CATransaction.commit()

        switch animation {
        case .none:
            knobLayer.removeAllAnimations()
            fillLayer.removeAllAnimations()
        case .ease, .spring:
            knobLayer.add(
                motion(
                    for: "position", from: NSValue(point: oldKnob), to: NSValue(point: newKnob),
                    spring: animation == .spring), forKey: "move")
            fillLayer.add(
                motion(for: "strokeEnd", from: oldEnd, to: newPosition, spring: animation == .spring),
                forKey: "move")
        }
        refreshColors()
    }

    private func motion(for keyPath: String, from: Any, to: Any, spring: Bool) -> CABasicAnimation {
        let animation: CABasicAnimation
        if spring {
            let bounce = CASpringAnimation(keyPath: keyPath)
            bounce.mass = 1
            bounce.stiffness = 320
            bounce.damping = 22
            bounce.duration = bounce.settlingDuration
            animation = bounce
        } else {
            animation = CABasicAnimation(keyPath: keyPath)
            animation.duration = 0.35
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        }
        animation.fromValue = from
        animation.toValue = to
        return animation
    }

    /// Text in the status row: what to do, the stop under the knob, or how long the sleep lasts.
    private func refreshTexts() {
        if isTracking, let selectedOption {
            statusLeft.stringValue = selectedOption.title
            statusLeft.textColor = .labelColor
            statusRight.stringValue = untilText(selectedOption)
            statusRight.textColor = .secondaryLabelColor
        } else if isAsleep {
            statusLeft.stringValue = remaining.isEmpty ? "Asleep" : "Asleep · \(remaining)"
            statusLeft.textColor = .labelColor
            statusRight.stringValue = ""
        } else {
            statusLeft.stringValue = "Sleep"
            statusLeft.textColor = .secondaryLabelColor
            statusRight.stringValue = "Drag to choose"
            statusRight.textColor = .tertiaryLabelColor
        }
        wakeButton.isHidden = !(isAsleep && !isTracking)
        statusRight.isHidden = !wakeButton.isHidden
        refreshColors()
    }

    /// Colors that depend on light or dark mode and on which stops the knob has passed.
    private func refreshColors() {
        let highlighted = isTracking || isAsleep ? selectedOption : nil
        for (index, label) in stopLabels.enumerated() {
            let isSelected = highlighted?.rawValue == index
            label.textColor = isSelected ? NSColor(cgColor: Palette.night) : .secondaryLabelColor
            label.font = .systemFont(ofSize: 11 * scale, weight: isSelected ? .medium : .regular)
        }
        let showsProgress = isTracking || isAsleep
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, tick) in tickLayers.enumerated() {
            let passed = showsProgress && Self.position(of: Self.options[index]) <= position + 0.001
            if passed {
                tick.fillColor = CGColor(gray: 1, alpha: 1)
            } else {
                tick.fillColor = CGColor(srgbRed: 0x88 / 255, green: 0x87 / 255, blue: 0x80 / 255, alpha: 1)
            }
        }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            knobLayer.fillColor = NSColor.controlBackgroundColor.cgColor
        }
        CATransaction.commit()
    }
}

/// The small "Wake up" pill in the sleep slider's status row.
@MainActor
final class WakeButtonView: NSView {
    var onPress: (() -> Void)?
    let scale: CGFloat
    private var isPressed = false {
        didSet { needsDisplay = true }
    }

    static let title = "Wake up"

    init(scale: CGFloat) {
        self.scale = scale
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(Self.title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("WakeButtonView is created in code only")
    }

    private var attributedTitle: NSAttributedString {
        NSAttributedString(
            string: Self.title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11 * scale, weight: .medium),
                .foregroundColor: NSColor.labelColor,
            ])
    }

    override var intrinsicContentSize: NSSize {
        let text = attributedTitle.size()
        return NSSize(width: (text.width + 20 * scale).rounded(.up), height: (20 * scale).rounded(.up))
    }

    override func draw(_ dirtyRect: NSRect) {
        let pill = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        // A soft fill without an outline: an outline looks dirty where the translucent card sits
        // over a dark window.
        let fill = isPressed ? NSColor.labelColor.withAlphaComponent(0.2) : NSColor.labelColor.withAlphaComponent(0.1)
        fill.setFill()
        pill.fill()
        let text = attributedTitle
        let size = text.size()
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            press()
        }
    }

    /// Wakes the icon, as a click does.
    func press() {
        onPress?()
    }

    override func accessibilityPerformPress() -> Bool {
        press()
        return true
    }
}
