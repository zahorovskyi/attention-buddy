import AppKit
import QuartzCore

#if canImport(AttentionCore)
    import AttentionCore
#endif

/// Draws the mascot with one Core Animation layer per moving part, and handles
/// dragging, clicking and the right-click menu.
///
/// Layer tree (all in a flipped, y-down space):
/// canvas → motion (jump, squash, shake) → figure (bob, pulse, base opacity) → body, arms, legs.
@MainActor
public final class IconView: NSView {
    /// Called on a click that was not a drag.
    public var onClick: (() -> Void)?
    /// Called after the user finished dragging the icon.
    public var onMoved: (() -> Void)?
    /// Called on a right-click or Control-click.
    public var onMenu: ((NSEvent) -> Void)?
    /// Called with `true` when the pointer enters the icon and `false` when it leaves or a press starts.
    public var onHover: ((Bool) -> Void)?
    /// Called once when a press turns into a drag.
    public var onDragBegan: (() -> Void)?

    public let scale: CGFloat
    public private(set) var shownState: IconState = .idle

    let canvasLayer = CALayer()
    let motionLayer = CALayer()
    let figureLayer = CALayer()
    let bodyLayer = CAShapeLayer()
    let leftArmLayer = CAShapeLayer()
    let rightArmLayer = CAShapeLayer()
    private(set) var legLayersA: [CAShapeLayer] = []
    private(set) var legLayersB: [CAShapeLayer] = []

    var shapeLayers: [CAShapeLayer] {
        [bodyLayer, leftArmLayer, rightArmLayer] + legLayersA + legLayersB
    }

    private var dragStartMouse: NSPoint?
    private var dragStartOrigin: NSPoint?
    private var isDragging = false
    /// Mouse movement in points before a press counts as a drag rather than a click.
    private let dragThreshold: CGFloat = 3

    public init(scale: CGFloat) {
        self.scale = scale
        super.init(frame: NSRect(origin: .zero, size: IconGeometry.size(scale: scale)))
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        buildLayers()
        show(.idle, animated: false, reduceMotion: true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("IconView is created in code only")
    }

    // MARK: Building the figure

    private func buildLayers() {
        guard let root = layer else {
            return
        }
        // Fully transparent pixels let clicks through to the window below, so the whole box gets
        // an almost invisible fill. That keeps the gaps between legs and eyes grabbable.
        root.backgroundColor = CGColor(gray: 0, alpha: 0.01)

        canvasLayer.frame = root.bounds
        canvasLayer.isGeometryFlipped = true
        root.addSublayer(canvasLayer)

        let canvasBounds = CGRect(origin: .zero, size: IconGeometry.size(scale: scale))
        let feet = IconGeometry.canvasPoint(IconGeometry.feet, scale: scale)
        for container in [motionLayer, figureLayer] {
            container.bounds = canvasBounds
            container.anchorPoint = CGPoint(x: feet.x / canvasBounds.width, y: feet.y / canvasBounds.height)
            container.position = feet
        }
        canvasLayer.addSublayer(motionLayer)
        motionLayer.addSublayer(figureLayer)
        figureLayer.allowsGroupOpacity = true

        place(bodyLayer, IconGeometry.body)
        bodyLayer.path = IconGeometry.bodyPath(scale: scale)
        bodyLayer.fillRule = .evenOdd

        place(leftArmLayer, IconGeometry.leftArm, pivot: IconGeometry.leftShoulder)
        place(rightArmLayer, IconGeometry.rightArm, pivot: IconGeometry.rightShoulder)

        legLayersA = IconGeometry.legsA.map { rect in
            let leg = CAShapeLayer()
            place(leg, rect)
            return leg
        }
        legLayersB = IconGeometry.legsB.map { rect in
            let leg = CAShapeLayer()
            place(leg, rect)
            return leg
        }
    }

    /// Adds a part to the figure at its artwork position, rotating around `pivot` if given.
    private func place(_ part: CAShapeLayer, _ artworkRect: CGRect, pivot: CGPoint? = nil) {
        let frame = IconGeometry.canvasRect(artworkRect, scale: scale)
        var anchor = CGPoint(x: 0.5, y: 0.5)
        if let pivot {
            let point = IconGeometry.canvasPoint(pivot, scale: scale)
            anchor = CGPoint(x: (point.x - frame.minX) / frame.width, y: (point.y - frame.minY) / frame.height)
        }
        part.bounds = CGRect(origin: .zero, size: frame.size)
        part.anchorPoint = anchor
        part.position = CGPoint(x: frame.minX + anchor.x * frame.width, y: frame.minY + anchor.y * frame.height)
        if part !== bodyLayer {
            part.path = CGPath(rect: part.bounds, transform: nil)
        }
        figureLayer.addSublayer(part)
    }

    // MARK: States and animations

    /// Switches colors and looping animations to `state`.
    public func show(_ state: IconState, animated: Bool, reduceMotion: Bool) {
        shownState = state
        let style = IconStyle.forState(state)

        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(0.3)
        for part in shapeLayers {
            part.fillColor = style.color
        }
        figureLayer.opacity = style.opacity
        CATransaction.commit()

        figureLayer.removeAnimation(forKey: "pulse")
        figureLayer.removeAnimation(forKey: "bob")
        bodyLayer.removeAnimation(forKey: "blink")
        for leg in legLayersA + legLayersB {
            leg.removeAnimation(forKey: "step")
        }

        if style.pulses {
            figureLayer.add(IconAnimations.pulse(), forKey: "pulse")
        }
        guard !reduceMotion else {
            return
        }
        if style.walks {
            figureLayer.add(IconAnimations.bob(scale: scale), forKey: "bob")
            for leg in legLayersA {
                leg.add(IconAnimations.step(phase: 0, scale: scale), forKey: "step")
            }
            for leg in legLayersB {
                leg.add(IconAnimations.step(phase: 1, scale: scale), forKey: "step")
            }
        }
        if style.blinks {
            let open = IconGeometry.bodyPath(scale: scale)
            let closed = IconGeometry.bodyPath(scale: scale, eyeOpenness: 0.1)
            bodyLayer.add(IconAnimations.blink(open: open, closed: closed), forKey: "blink")
        }
    }

    /// Plays a one-shot animation on top of the current state.
    public func play(_ animation: IconAnimation) {
        switch animation {
        case .jumpAndWave:
            motionLayer.add(IconAnimations.jump(scale: scale), forKey: "jump")
            let wave = IconAnimations.wave()
            wave.beginTime = CACurrentMediaTime() + 0.3
            rightArmLayer.add(wave, forKey: "wave")
        case .celebrate:
            motionLayer.add(IconAnimations.hop(scale: scale), forKey: "hop")
            leftArmLayer.add(IconAnimations.armUp(left: true), forKey: "armUp")
            rightArmLayer.add(IconAnimations.armUp(left: false), forKey: "armUp")
        case .shake:
            motionLayer.add(IconAnimations.shake(scale: scale), forKey: "shake")
        }
    }

    // MARK: Mouse

    /// Tracks the pointer even though this app is never active.
    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(
            NSTrackingArea(
                rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self,
                userInfo: nil))
    }

    public override func mouseEntered(with event: NSEvent) {
        onHover?(true)
    }

    public override func mouseExited(with event: NSEvent) {
        onHover?(false)
    }

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    public override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            onMenu?(event)
            return
        }
        dragStartMouse = NSEvent.mouseLocation
        dragStartOrigin = window?.frame.origin
        isDragging = false
    }

    public override func mouseDragged(with event: NSEvent) {
        guard let startMouse = dragStartMouse, let startOrigin = dragStartOrigin, let window else {
            return
        }
        let mouse = NSEvent.mouseLocation
        let deltaX = mouse.x - startMouse.x
        let deltaY = mouse.y - startMouse.y
        if !isDragging && hypot(deltaX, deltaY) < dragThreshold {
            return
        }
        if !isDragging {
            onDragBegan?()
        }
        isDragging = true
        window.setFrameOrigin(NSPoint(x: startOrigin.x + deltaX, y: startOrigin.y + deltaY))
    }

    public override func mouseUp(with event: NSEvent) {
        guard dragStartMouse != nil else {
            return
        }
        if isDragging {
            onMoved?()
        } else {
            onClick?()
        }
        dragStartMouse = nil
        dragStartOrigin = nil
        isDragging = false
    }

    public override func rightMouseDown(with event: NSEvent) {
        onMenu?(event)
    }
}
