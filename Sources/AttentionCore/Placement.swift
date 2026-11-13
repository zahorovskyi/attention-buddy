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
