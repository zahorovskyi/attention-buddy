import Foundation

/// Settings the user can change with `defaults write io.github.zahorovskyi.attention-buddy <key> <value>`.
public struct AttentionSettings: Equatable, Sendable {
    public static let defaultsDomain = "io.github.zahorovskyi.attention-buddy"

    /// Seconds a waiting session stays "seen" before asking for attention again. Key `seenTimeout`.
    public var seenTimeout: TimeInterval
    /// Seconds between repeated jump-and-wave animations while a session waits. Key `repeatInterval`.
    public var repeatInterval: TimeInterval
    /// Size of the icon: points per icon pixel. Key `scale`. Changed with the Settings slider.
    public var scale: Double

    /// Allowed icon scales: the smallest size (1×) up to four times bigger (4×).
    public static let scaleRange: ClosedRange<Double> = 1.5...6

    /// The size a new install starts with: 2×.
    public static let defaultScale: Double = 3

    public static let standard = AttentionSettings(seenTimeout: 180, repeatInterval: 15, scale: defaultScale)

    /// The icon size as a multiple of the smallest size: 1 at the smallest, 4 at the biggest.
    public static func sizeMultiplier(forScale scale: Double) -> Double {
        scale / scaleRange.lowerBound
    }

    /// The size shown next to the slider, for example "1×", "2.5×" or "4×".
    public static func sizeLabel(forScale scale: Double) -> String {
        let rounded = (sizeMultiplier(forScale: scale) * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return "\(Int(rounded))×"
        }
        return String(format: "%.1f×", rounded)
    }

    /// Keeps a scale inside `scaleRange`.
    public static func clampedScale(_ scale: Double) -> Double {
        min(max(scale, scaleRange.lowerBound), scaleRange.upperBound)
    }

    public init(seenTimeout: TimeInterval, repeatInterval: TimeInterval, scale: Double) {
        self.seenTimeout = seenTimeout
        self.repeatInterval = repeatInterval
        self.scale = scale
    }

    /// Reads the settings, keeping each value inside a sensible range.
    public init(defaults: UserDefaults) {
        let standard = AttentionSettings.standard
        self.init(
            seenTimeout: Self.read("seenTimeout", from: defaults, default: standard.seenTimeout, range: 10...3600),
            repeatInterval: Self.read(
                "repeatInterval", from: defaults, default: standard.repeatInterval, range: 5...600),
            scale: Self.read("scale", from: defaults, default: standard.scale, range: Self.scaleRange)
        )
    }

    private static func read(
        _ key: String,
        from defaults: UserDefaults,
        default fallback: Double,
        range: ClosedRange<Double>
    ) -> Double {
        guard defaults.object(forKey: key) != nil else {
            return fallback
        }
        let value = defaults.double(forKey: key)
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
