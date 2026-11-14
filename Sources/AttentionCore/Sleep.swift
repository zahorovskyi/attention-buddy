import Foundation

/// How long the icon sleeps. The order is the order of the stops on the sleep slider.
public enum SleepOption: Int, CaseIterable, Sendable {
    case fifteenMinutes
    case thirtyMinutes
    case fortyFiveMinutes
    case oneHour
    case twoHours
    case fourHours
    /// Until the next midnight, local time.
    case restOfDay

    /// The label under the slider stop, for example "15m" or "Today".
    public var shortLabel: String {
        switch self {
        case .fifteenMinutes:
            return "15m"
        case .thirtyMinutes:
            return "30m"
        case .fortyFiveMinutes:
            return "45m"
        case .oneHour:
            return "1h"
        case .twoHours:
            return "2h"
        case .fourHours:
            return "4h"
        case .restOfDay:
            return "Today"
        }
    }

    /// The name shown while dragging and in the right-click menu, for example "45 minutes".
    public var title: String {
        switch self {
        case .fifteenMinutes:
            return "15 minutes"
        case .thirtyMinutes:
            return "30 minutes"
        case .fortyFiveMinutes:
            return "45 minutes"
        case .oneHour:
            return "1 hour"
        case .twoHours:
            return "2 hours"
        case .fourHours:
            return "4 hours"
        case .restOfDay:
            return "End of day"
        }
    }

    /// When a sleep chosen at `now` ends.
    public func wakeTime(from now: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .fifteenMinutes:
            return now.addingTimeInterval(15 * 60)
        case .thirtyMinutes:
            return now.addingTimeInterval(30 * 60)
        case .fortyFiveMinutes:
            return now.addingTimeInterval(45 * 60)
        case .oneHour:
            return now.addingTimeInterval(60 * 60)
        case .twoHours:
            return now.addingTimeInterval(2 * 60 * 60)
        case .fourHours:
            return now.addingTimeInterval(4 * 60 * 60)
        case .restOfDay:
            let startOfToday = calendar.startOfDay(for: now)
            return calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now.addingTimeInterval(24 * 60 * 60)
        }
    }
}

/// Whether the icon is asleep, and until when. While asleep it stays grey and silent: no red,
/// no blinking, no jumping. Sessions keep being recorded, and the icon shows their real state
/// as soon as it wakes up.
///
/// Saved in the preferences, so a sleep survives a restart of the icon and a Quit.
public struct SleepSchedule: Equatable, Sendable {
    /// Preference keys: the wake-up time in seconds since 1970, and the chosen option.
    public static let wakeKey = "sleepUntil"
    public static let optionKey = "sleepOption"

    public private(set) var wakeAt: Date?
    public private(set) var option: SleepOption?

    public init(wakeAt: Date? = nil, option: SleepOption? = nil) {
        self.wakeAt = wakeAt
        self.option = option
    }

    /// Reads a saved sleep. A missing or broken value means awake.
    public init(defaults: UserDefaults) {
        guard defaults.object(forKey: Self.wakeKey) != nil else {
            self.init()
            return
        }
        let wakeAt = Date(timeIntervalSince1970: defaults.double(forKey: Self.wakeKey))
        let option = SleepOption(rawValue: defaults.integer(forKey: Self.optionKey))
        self.init(wakeAt: wakeAt, option: option)
    }

    public func save(to defaults: UserDefaults) {
        guard let wakeAt else {
            defaults.removeObject(forKey: Self.wakeKey)
            defaults.removeObject(forKey: Self.optionKey)
            return
        }
        defaults.set(wakeAt.timeIntervalSince1970, forKey: Self.wakeKey)
        if let option {
            defaults.set(option.rawValue, forKey: Self.optionKey)
        } else {
            defaults.removeObject(forKey: Self.optionKey)
        }
    }

    public func isAsleep(at now: Date) -> Bool {
        guard let wakeAt else {
            return false
        }
        return now < wakeAt
    }

    /// Starts (or changes) a sleep chosen at `now`.
    public mutating func start(_ option: SleepOption, at now: Date, calendar: Calendar = .current) {
        self.option = option
        self.wakeAt = option.wakeTime(from: now, calendar: calendar)
    }

    public mutating func wake() {
        wakeAt = nil
        option = nil
    }

    /// Time left, rounded up to whole minutes: "42 min" or "3 h 5 min". Empty when awake.
    public func remainingText(at now: Date) -> String {
        guard let wakeAt, now < wakeAt else {
            return ""
        }
        let minutes = Int((wakeAt.timeIntervalSince(now) / 60).rounded(.up))
        if minutes < 60 {
            return "\(minutes) min"
        }
        let hours = minutes / 60
        let rest = minutes % 60
        if rest == 0 {
            return "\(hours) h"
        }
        return "\(hours) h \(rest) min"
    }

    /// "until 12:47", or "until midnight" when the sleep ends at the start of a day.
    public static func untilText(_ wakeAt: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: wakeAt)
        if parts.hour == 0 && parts.minute == 0 {
            return "until midnight"
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return "until " + formatter.string(from: wakeAt)
    }
}

/// Texts that show the sleep in the session card and to VoiceOver.
public enum SleepText {
    /// The card's summary line while asleep, for example "Asleep until 12:47 · 1 session needs you".
    public static func cardHeader(
        _ header: String, wakeAt: Date, calendar: Calendar = .current, locale: Locale = .current
    )
        -> String
    {
        "Asleep \(SleepSchedule.untilText(wakeAt, calendar: calendar, locale: locale)) · \(header)"
    }

    /// The line VoiceOver reads first while asleep, for example "Asleep until 12:47."
    public static func accessibilityPrefix(wakeAt: Date, calendar: Calendar = .current, locale: Locale = .current)
        -> String
    {
        "Asleep \(SleepSchedule.untilText(wakeAt, calendar: calendar, locale: locale))."
    }
}
