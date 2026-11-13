import CoreGraphics

#if canImport(AttentionCore)
    import AttentionCore
#endif

/// How the icon looks in each state: its color and which looping animations run.
public struct IconStyle: Equatable {
    public var color: CGColor
    public var opacity: Float
    /// Fade in and out once a second. Runs even with Reduce Motion, because it is the main signal.
    public var pulses: Bool
    /// Legs step in place and the body bobs.
    public var walks: Bool
    /// The eyes blink every few seconds.
    public var blinks: Bool

    /// The style for a state.
    public static func forState(_ state: IconState) -> IconStyle {
        switch state {
        case .idle:
            return IconStyle(color: Palette.clay, opacity: 0.55, pulses: false, walks: false, blinks: true)
        case .working:
            return IconStyle(color: Palette.clay, opacity: 0.55, pulses: false, walks: true, blinks: true)
        case .done:
            return IconStyle(color: Palette.green, opacity: 1, pulses: false, walks: false, blinks: true)
        case .seen:
            return IconStyle(color: Palette.red, opacity: 1, pulses: false, walks: false, blinks: true)
        case .error:
            return IconStyle(color: Palette.red, opacity: 1, pulses: false, walks: false, blinks: false)
        case .needsYou:
            return IconStyle(color: Palette.red, opacity: 1, pulses: true, walks: false, blinks: false)
        }
    }
}

/// The three colors the icon uses.
public enum Palette {
    /// The mascot's own clay color, #D97757.
    public static var clay: CGColor { srgb(0xD9, 0x77, 0x57) }
    /// "Needs you", #E5484D.
    public static var red: CGColor { srgb(0xE5, 0x48, 0x4D) }
    /// "Done", #46A758.
    public static var green: CGColor { srgb(0x46, 0xA7, 0x58) }

    private static func srgb(_ red: Int, _ green: Int, _ blue: Int) -> CGColor {
        CGColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
    }
}
