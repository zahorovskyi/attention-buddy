import AppKit

#if canImport(AttentionCore)
    import AttentionCore
#endif

/// The small Settings window opened from the right-click menu. For now it has one setting:
/// the icon size, from the original size (1×) up to four times bigger (4×).
@MainActor
public final class SettingsWindow: NSObject, NSWindowDelegate {
    /// Called while the slider moves, with the new scale (points per icon pixel).
    public var onScaleChange: ((Double) -> Void)?

    let window: NSWindow
    let slider: NSSlider
    let sizeLabel: NSTextField

    public init(scale: Double) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 120),
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

    /// Moves the slider to `scale` without reporting a change, for example after a reset.
    public func update(scale: Double) {
        slider.doubleValue = AttentionSettings.clampedScale(scale)
        sizeLabel.stringValue = AttentionSettings.sizeLabel(forScale: slider.doubleValue)
    }

    @objc func sliderMoved() {
        let scale = AttentionSettings.clampedScale(slider.doubleValue)
        sizeLabel.stringValue = AttentionSettings.sizeLabel(forScale: scale)
        onScaleChange?(scale)
    }

    private func makeContent() -> NSView {
        let title = NSTextField(labelWithString: "Icon size")
        title.font = .systemFont(ofSize: 13, weight: .semibold)

        sizeLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        sizeLabel.textColor = .secondaryLabelColor
        sizeLabel.alignment = .right
        sizeLabel.setContentHuggingPriority(.required, for: .horizontal)

        let small = NSTextField(labelWithString: "1×")
        let big = NSTextField(labelWithString: "4×")
        for edge in [small, big] {
            edge.font = .systemFont(ofSize: 11)
            edge.textColor = .tertiaryLabelColor
        }

        let header = NSStackView(views: [title, NSView(), sizeLabel])
        header.orientation = .horizontal
        let sliderRow = NSStackView(views: [small, slider, big])
        sliderRow.orientation = .horizontal
        sliderRow.spacing = 8
        let hint = NSTextField(labelWithString: "Changes apply right away and are remembered.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [header, sliderRow, hint])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            sliderRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            content.widthAnchor.constraint(equalToConstant: 380),
        ])
        return content
    }
}
