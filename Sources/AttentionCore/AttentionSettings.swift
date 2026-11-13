import Foundation

/// Settings the user can change with `defaults write io.github.zahorovskyi.attention-buddy <key> <value>`.
public struct AttentionSettings: Equatable, Sendable {
    public static let defaultsDomain = "io.github.zahorovskyi.attention-buddy"

    /// Seconds a waiting session stays "seen" before asking for attention again. Key `seenTimeout`.
    public var seenTimeout: TimeInterval
    /// Seconds between repeated jump-and-wave animations while a session waits. Key `repeatInterval`.
    public var repeatInterval: TimeInterval
    /// Size of the icon: points per icon pixel. Key `scale`.
    public var scale: Double

    public static let standard = AttentionSettings(seenTimeout: 180, repeatInterval: 15, scale: 1.5)

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
            scale: Self.read("scale", from: defaults, default: standard.scale, range: 0.75...4)
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
