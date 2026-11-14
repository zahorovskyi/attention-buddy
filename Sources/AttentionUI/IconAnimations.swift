import QuartzCore

/// Builds the Core Animation objects for the icon.
///
/// Layers live in a flipped (y-down) coordinate space, so a negative y translation moves up
/// and a negative rotation turns counterclockwise. Distances are in points (icon pixels × scale).
public enum IconAnimations {
    // MARK: Looping

    /// Fades the figure in and out once a second ("needs you").
    public static func pulse() -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = [1, 0.3, 1]
        animation.keyTimes = [0, 0.5, 1]
        animation.duration = 1
        animation.repeatCount = .infinity
        animation.timingFunctions = [easeInOut, easeInOut]
        return animation
    }

    /// A slow, gentle fade for a working session's dot in the card.
    public static func breathe() -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = [1, 0.45, 1]
        animation.keyTimes = [0, 0.5, 1]
        animation.duration = 2.4
        animation.repeatCount = .infinity
        animation.timingFunctions = [easeInOut, easeInOut]
        return animation
    }

    /// Slow sleepy breathing: the figure sinks a little and rises again ("asleep").
    public static func sleepBreath() -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: "transform.scale.y")
        animation.fromValue = 1
        animation.toValue = 0.95
        animation.duration = 1.8
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = easeInOut
        return animation
    }

    /// A "z" that rises, grows and fades away; two of them float half a cycle apart ("asleep").
    public static func floatingZ(scale: CGFloat, delay: CFTimeInterval) -> CAAnimationGroup {
        let rise = CAKeyframeAnimation(keyPath: "transform.translation.y")
        rise.values = [0, -4 * scale]
        let drift = CAKeyframeAnimation(keyPath: "transform.translation.x")
        drift.values = [0, 1.5 * scale]
        let grow = CAKeyframeAnimation(keyPath: "transform.scale")
        grow.values = [0.6, 1.1]
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 0]
        fade.keyTimes = [0, 0.4, 1]
        let group = CAAnimationGroup()
        group.animations = [rise, drift, grow, fade]
        group.duration = 3
        group.repeatCount = .infinity
        group.beginTime = CACurrentMediaTime() + delay
        group.fillMode = .backwards
        return group
    }

    /// Moves one pair of legs up and down; the two pairs use opposite phases ("working").
    public static func step(phase: Int, scale: CGFloat) -> CAKeyframeAnimation {
        let lift = -1 * scale
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.y")
        animation.values = phase == 0 ? [0, lift] : [lift, 0]
        animation.keyTimes = [0, 0.5]
        animation.calculationMode = .discrete
        animation.duration = 0.8
        animation.repeatCount = .infinity
        return animation
    }

    /// A small up-and-down bob of the whole figure while walking.
    public static func bob(scale: CGFloat) -> CAKeyframeAnimation {
        let lift = -0.4 * scale
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.y")
        animation.values = [0, lift, 0, lift, 0]
        animation.keyTimes = [0, 0.25, 0.5, 0.75, 1]
        animation.duration = 0.8
        animation.repeatCount = .infinity
        return animation
    }

    /// Closes the eyes briefly every `period` seconds.
    public static func blink(open: CGPath, closed: CGPath, period: CFTimeInterval = 4) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "path")
        animation.values = [open, open, closed, open, open]
        animation.keyTimes = [0, 0.9, 0.93, 0.96, 1]
        animation.duration = period
        animation.repeatCount = .infinity
        return animation
    }

    // MARK: One-shots

    /// Squash, jump about four pixels, stretch and land ("needs you").
    public static func jump(scale: CGFloat) -> CAAnimationGroup {
        let rise = CAKeyframeAnimation(keyPath: "transform.translation.y")
        rise.values = [0, 0, -4 * scale, 0, 0]
        rise.keyTimes = [0, 0.19, 0.5, 0.81, 1]
        let squash = CAKeyframeAnimation(keyPath: "transform.scale.y")
        squash.values = [1, 0.82, 1.08, 0.88, 1]
        squash.keyTimes = [0, 0.19, 0.5, 0.81, 1]
        return group([rise, squash], duration: 1)
    }

    /// Waves the right arm three times above the head ("needs you").
    public static func wave() -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        animation.values = [0, -115, -65, -115, -65, -115, 0].map(radians)
        animation.keyTimes = [0, 0.15, 0.3, 0.45, 0.6, 0.75, 1]
        animation.duration = 2
        animation.timingFunction = easeInOut
        return animation
    }

    /// A small hop ("done").
    public static func hop(scale: CGFloat) -> CAAnimationGroup {
        let rise = CAKeyframeAnimation(keyPath: "transform.translation.y")
        rise.values = [0, 0, -3 * scale, 0, 0]
        rise.keyTimes = [0, 0.2, 0.45, 0.7, 1]
        let squash = CAKeyframeAnimation(keyPath: "transform.scale.y")
        squash.values = [1, 0.88, 1, 1, 1]
        squash.keyTimes = [0, 0.2, 0.45, 0.7, 1]
        return group([rise, squash], duration: 1.2)
    }

    /// Raises one arm and holds it briefly ("done"). The left arm turns clockwise to go up.
    public static func armUp(left: Bool) -> CAKeyframeAnimation {
        let angle = left ? 80.0 : -80.0
        let animation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        animation.values = [0, 0, angle, angle, 0].map(radians)
        animation.keyTimes = [0, 0.2, 0.45, 0.8, 1]
        animation.duration = 1.6
        animation.timingFunction = easeInOut
        return animation
    }

    /// A quick side-to-side head shake ("error").
    public static func shake(scale: CGFloat) -> CAKeyframeAnimation {
        let distance = 1.2 * scale
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.values = [0, -distance, distance, -distance, distance, -distance, distance, 0]
        animation.duration = 0.9
        animation.timingFunction = easeInOut
        return animation
    }

    // MARK: Helpers

    private static var easeInOut: CAMediaTimingFunction { CAMediaTimingFunction(name: .easeInEaseOut) }

    private static func radians(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }

    private static func group(_ animations: [CAAnimation], duration: CFTimeInterval) -> CAAnimationGroup {
        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = duration
        group.timingFunction = easeInOut
        return group
    }
}
