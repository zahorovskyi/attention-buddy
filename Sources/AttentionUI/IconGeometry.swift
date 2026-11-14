import CoreGraphics

/// The Claude Code mascot, split into parts that can move on their own.
///
/// Rectangles use "icon pixels" from the original 24×24 artwork, with y pointing down.
/// The canvas adds a pixel of margin on each side and keeps room above the head for jumps.
public enum IconGeometry {
    /// Size of the drawing area in icon pixels.
    public static let canvas = CGSize(width: 26, height: 21)
    /// Shift from artwork coordinates to canvas coordinates.
    public static let offset = CGPoint(x: 1, y: 0)

    public static let body = CGRect(x: 3, y: 5, width: 18, height: 12.079)
    /// Eye holes, relative to the body's top-left corner.
    public static let eyes = [
        CGRect(x: 3, y: 3.102, width: 1.488, height: 2.847),
        CGRect(x: 13.51, y: 3.102, width: 1.49, height: 2.847),
    ]

    /// Arms overlap the body slightly so no seam shows when they rotate.
    public static let leftArm = CGRect(x: 0, y: 10.95, width: 3.1, height: 3.1)
    public static let rightArm = CGRect(x: 20.9, y: 10.949, width: 3.1, height: 3.102)
    public static let leftShoulder = CGPoint(x: 3, y: 12.5)
    public static let rightShoulder = CGPoint(x: 21, y: 12.5)

    /// Legs in two pairs that step alternately. They start inside the body to avoid a seam.
    public static let legsA = [
        CGRect(x: 4.487, y: 17, width: 1.513, height: 3),
        CGRect(x: 15, y: 17, width: 1.513, height: 3),
    ]
    public static let legsB = [
        CGRect(x: 7.488, y: 17, width: 1.512, height: 3),
        CGRect(x: 18, y: 17, width: 1.513, height: 3),
    ]

    /// How open the eyes are while asleep: a thin slit.
    public static let sleepyEyeOpenness: CGFloat = 0.16
    /// How far the arms turn down while asleep, in degrees.
    public static let sleepingArmAngle: CGFloat = 72

    /// The point between the feet that jumps squash and stretch around.
    public static let feet = CGPoint(x: 12, y: 20)

    /// Size of the whole icon in points.
    public static func size(scale: CGFloat) -> CGSize {
        CGSize(width: canvas.width * scale, height: canvas.height * scale)
    }

    /// A rectangle in artwork coordinates converted to canvas points.
    public static func canvasRect(_ rect: CGRect, scale: CGFloat) -> CGRect {
        CGRect(
            x: (rect.minX + offset.x) * scale,
            y: (rect.minY + offset.y) * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }

    /// A point in artwork coordinates converted to canvas points.
    public static func canvasPoint(_ point: CGPoint, scale: CGFloat) -> CGPoint {
        CGPoint(x: (point.x + offset.x) * scale, y: (point.y + offset.y) * scale)
    }

    /// The body with its eye holes (fill it with the even-odd rule), in body-local points.
    /// `eyeOpenness` is 1 for open eyes and close to 0 mid-blink. A blink closes toward the
    /// middle of the eye; sleepy eyes (`lidsDown`) keep only a slit at the bottom.
    public static func bodyPath(scale: CGFloat, eyeOpenness: CGFloat = 1, lidsDown: Bool = false) -> CGPath {
        let path = CGMutablePath()
        path.addRect(CGRect(x: 0, y: 0, width: body.width * scale, height: body.height * scale))
        for eye in eyes {
            let height = eye.height * eyeOpenness
            var top = eye.midY - height / 2
            if lidsDown {
                top = eye.maxY - height
            }
            path.addRect(
                CGRect(
                    x: eye.minX * scale,
                    y: top * scale,
                    width: eye.width * scale,
                    height: height * scale
                ))
        }
        return path
    }
}
