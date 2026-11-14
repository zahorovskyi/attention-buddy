import AppKit

#if canImport(AttentionCore)
    import AttentionCore
#endif

/// The small Settings window opened from the right-click menu: the icon size (1× to 4×), the
/// size of the session card and its sleep slider (1× to 2×), and whether the card shows the
/// sleep slider.
@MainActor
public final class SettingsWindow: NSObject, NSWindowDelegate {
    /// Called while the slider moves, with the new scale (points per icon pixel).
    public var onScaleChange: ((Double) -> Void)?
    /// Called while the card size slider moves, with the new card scale (1 to 2).
    public var onCardScaleChange: ((Double) -> Void)?
    /// Called when the "Show sleep slider" checkbox changes.
    public var onSleepSliderChange: ((Bool) -> Void)?

    let window: NSWindow
    let slider: NSSlider
    let sizeLabel: NSTextField
    let cardSlider: NSSlider
    let cardSizeLabel: NSTextField
    let sleepSliderCheckbox: NSButton

    public init(scale: Double, cardScale: Double = 1, showsSleepSlider: Bool = true) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        slider = NSSlider(
            value: AttentionSettings.clampedScale(scale),
            minValue: AttentionSettings.scaleRange.lowerBound,
            maxValue: AttentionSettings.scaleRange.upperBound,
            target: nil,
            action: nil
        )
        sizeLabel = NSTextField(labelWithString: AttentionSettings.sizeLabel(forScale: scale))
        cardSlider = NSSlider(
            value: AttentionSettings.clampedCardScale(cardScale),
            minValue: AttentionSettings.cardScaleRange.lowerBound,
            maxValue: AttentionSettings.cardScaleRange.upperBound,
            target: nil,
            action: nil
        )
        cardSizeLabel = NSTextField(labelWithString: AttentionSettings.cardSizeLabel(forScale: cardScale))
        sleepSliderCheckbox = NSButton(
            checkboxWithTitle: "Show sleep slider in the session card", target: nil, action: nil)
        sleepSliderCheckbox.state = showsSleepSlider ? .on : .off
        super.init()

        window.title = "Attention Buddy Settings"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = makeContent()

        slider.target = self
        slider.action = #selector(sliderMoved)
        slider.isContinuous = true
        slider.numberOfTickMarks = 4
        slider.allowsTickMarkValuesOnly = false
        slider.setAccessibilityLabel("Icon size")

        cardSlider.target = self
        cardSlider.action = #selector(cardSliderMoved)
        cardSlider.isContinuous = true
        cardSlider.numberOfTickMarks = 5
        cardSlider.allowsTickMarkValuesOnly = false
        cardSlider.setAccessibilityLabel("Card size")

        sleepSliderCheckbox.target = self
        sleepSliderCheckbox.action = #selector(sleepSliderToggled)
    }

    public var isVisible: Bool {
        window.isVisible
    }

    /// Shows the window in front of other apps. The icon itself never takes focus, so the
    /// app activates just for this window.
    public func show() {
        if !window.isVisible {
            window.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    public func close() {
        window.close()
    }

    /// Shows the current settings without reporting a change.
    public func update(scale: Double, cardScale: Double, showsSleepSlider: Bool) {
        slider.doubleValue = AttentionSettings.clampedScale(scale)
        sizeLabel.stringValue = AttentionSettings.sizeLabel(forScale: slider.doubleValue)
        cardSlider.doubleValue = AttentionSettings.clampedCardScale(cardScale)
        cardSizeLabel.stringValue = AttentionSettings.cardSizeLabel(forScale: cardSlider.doubleValue)
        sleepSliderCheckbox.state = showsSleepSlider ? .on : .off
    }

    @objc func sliderMoved() {
        let scale = AttentionSettings.clampedScale(slider.doubleValue)
        sizeLabel.stringValue = AttentionSettings.sizeLabel(forScale: scale)
        onScaleChange?(scale)
    }

    @objc func cardSliderMoved() {
        let scale = AttentionSettings.clampedCardScale(cardSlider.doubleValue)
        cardSizeLabel.stringValue = AttentionSettings.cardSizeLabel(forScale: scale)
        onCardScaleChange?(scale)
    }

    @objc func sleepSliderToggled() {
        onSleepSliderChange?(sleepSliderCheckbox.state == .on)
    }

    private func makeContent() -> NSView {
        let iconHeader = header("Icon size", value: sizeLabel)
        let iconRow = sliderRow(slider, low: "1×", high: "4×")
        let cardHeader = header("Card size", value: cardSizeLabel)
        let cardRow = sliderRow(cardSlider, low: "1×", high: "2×")
        sleepSliderCheckbox.font = .systemFont(ofSize: 13)
        let hint = NSTextField(labelWithString: "Changes apply right away and are remembered.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [iconHeader, iconRow, cardHeader, cardRow, sleepSliderCheckbox, hint])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(18, after: iconRow)
        stack.setCustomSpacing(14, after: cardRow)
        stack.setCustomSpacing(14, after: sleepSliderCheckbox)
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        var constraints = [
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            content.widthAnchor.constraint(equalToConstant: 380),
        ]
        for row in [iconHeader, iconRow, cardHeader, cardRow] {
            constraints.append(row.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40))
        }
        NSLayoutConstraint.activate(constraints)
        return content
    }

    private func header(_ title: String, value: NSTextField) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        value.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        value.textColor = .secondaryLabelColor
        value.alignment = .right
        value.setContentHuggingPriority(.required, for: .horizontal)
        let row = NSStackView(views: [label, NSView(), value])
        row.orientation = .horizontal
        return row
    }

    private func sliderRow(_ slider: NSSlider, low: String, high: String) -> NSStackView {
        let small = NSTextField(labelWithString: low)
        let big = NSTextField(labelWithString: high)
        for edge in [small, big] {
            edge.font = .systemFont(ofSize: 11)
            edge.textColor = .tertiaryLabelColor
        }
        let row = NSStackView(views: [small, slider, big])
        row.orientation = .horizontal
        row.spacing = 8
        return row
    }
}
