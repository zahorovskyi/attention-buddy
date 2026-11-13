import CoreGraphics

/// Keeps the icon somewhere the user can see it.
public enum Placement {
    /// The default spot: near the bottom-right corner of a screen's visible area (above the Dock),
    /// `margin` points in from the right and bottom edges. AppKit coordinates (y pointing up).
    public static func defaultOrigin(size: CGSize, visibleFrame: CGRect, margin: CGFloat = 24) -> CGPoint {
        CGPoint(
            x: visibleFrame.maxX - size.width - margin,
            y: visibleFrame.minY + margin
        )
    }

    /// The new origin when the icon changes size.
    ///
    /// The edges nearest the screen's corner stay where they are: in the right half of the screen
    /// the right edge stays put, in the left half the left edge; in the bottom half the bottom
    /// edge, in the top half the top edge. So the icon grows away from its corner, never drifts,
    /// and shrinking back returns it exactly to where it was. It is also kept on screen.
    /// Visible frames, AppKit coordinates (y pointing up).
    public static func resizedOrigin(from frame: CGRect, to size: CGSize, screens: [CGRect]) -> CGPoint {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        guard let screen = screens.first(where: { $0.contains(center) }) ?? screens.first else {
            return frame.origin
        }
        var origin = CGPoint.zero
        if center.x >= screen.midX {
            origin.x = frame.maxX - size.width
        } else {
            origin.x = frame.minX
        }
        if center.y >= screen.midY {
            origin.y = frame.maxY - size.height
        } else {
            origin.y = frame.minY
        }
        origin.x = min(max(origin.x, screen.minX), screen.maxX - size.width)
        origin.y = min(max(origin.y, screen.minY), screen.maxY - size.height)
        return origin
    }

    /// Where the hover card goes: centered below the icon, or above it when there is no room
    /// below, and always inside the screen. Coordinates are AppKit's (y pointing up).
    public static func hoverCardFrame(
        cardSize: CGSize,
        iconFrame: CGRect,
        screen: CGRect,
        gap: CGFloat = 6
    ) -> CGRect {
        var y = iconFrame.minY - gap - cardSize.height
        if y < screen.minY {
            y = iconFrame.maxY + gap
        }
        y = min(max(y, screen.minY), screen.maxY - cardSize.height)
        var x = iconFrame.midX - cardSize.width / 2
        x = min(max(x, screen.minX), screen.maxX - cardSize.width)
        return CGRect(x: x, y: y, width: cardSize.width, height: cardSize.height)
    }

    /// Returns `origin` when the icon's center is on one of `screens` (visible frames),
    /// otherwise the default spot on the first screen. Handles unplugged monitors.
    public static func clamp(origin: CGPoint, size: CGSize, screens: [CGRect]) -> CGPoint {
        let center = CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
        if screens.contains(where: { $0.contains(center) }) {
            return origin
        }
        guard let first = screens.first else {
            return origin
        }
        return defaultOrigin(size: size, visibleFrame: first)
    }
}
