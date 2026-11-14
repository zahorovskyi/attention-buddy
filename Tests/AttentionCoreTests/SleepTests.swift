import Foundation
import Testing

@testable import AttentionCore

/// A calendar and locale fixed to UTC and 24-hour time, so the tests don't depend on the machine.
private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
    return calendar
}
private let british = Locale(identifier: "en_GB")

private func date(_ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
    utc.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: hour, minute: minute, second: second))
        ?? Date()
}

@Suite("Sleep options")
struct SleepOptionTests {
    @Test("Seven stops from 15 minutes to the end of the day, in slider order")
    func stops() {
        #expect(SleepOption.allCases.map(\.shortLabel) == ["15m", "30m", "45m", "1h", "2h", "4h", "Today"])
        #expect(
            SleepOption.allCases.map(\.title) == [
                "15 minutes", "30 minutes", "45 minutes", "1 hour", "2 hours", "4 hours", "End of day",
            ])
    }

    @Test(
        "Each option wakes up after its duration",
        arguments: [
            (SleepOption.fifteenMinutes, 15.0), (.thirtyMinutes, 30), (.fortyFiveMinutes, 45), (.oneHour, 60),
            (.twoHours, 120), (.fourHours, 240),
        ])
    func durations(option: SleepOption, minutes: Double) {
        let now = date(12, 2)
        #expect(option.wakeTime(from: now, calendar: utc) == now.addingTimeInterval(minutes * 60))
    }

    @Test("End of day wakes up at the next midnight, even a few seconds before it")
    func endOfDay() {
        let midnight = date(0, 0).addingTimeInterval(24 * 60 * 60)
        #expect(SleepOption.restOfDay.wakeTime(from: date(9, 30), calendar: utc) == midnight)
        #expect(SleepOption.restOfDay.wakeTime(from: date(23, 59, 30), calendar: utc) == midnight)
    }
}

@Suite("Sleep schedule")
struct SleepScheduleTests {
    private func makeDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "attention-buddy-sleep-\(UUID().uuidString)"))
    }

    @Test("Asleep until the wake-up time, awake after it")
    func asleepUntilWakeTime() {
        var sleep = SleepSchedule()
        #expect(!sleep.isAsleep(at: date(12, 0)))
        sleep.start(.thirtyMinutes, at: date(12, 0), calendar: utc)
        #expect(sleep.option == .thirtyMinutes)
        #expect(sleep.isAsleep(at: date(12, 29, 59)))
        #expect(!sleep.isAsleep(at: date(12, 30)))
    }

    @Test("Choosing again changes the wake-up time; waking up clears it")
    func changeAndWake() {
        var sleep = SleepSchedule()
        sleep.start(.fourHours, at: date(12, 0), calendar: utc)
        sleep.start(.fifteenMinutes, at: date(12, 5), calendar: utc)
        #expect(sleep.wakeAt == date(12, 20))
        sleep.wake()
        #expect(sleep == SleepSchedule())
        #expect(!sleep.isAsleep(at: date(12, 6)))
    }

    @Test("A sleep is saved, so it survives a restart and a Quit")
    func persistence() throws {
        let defaults = try makeDefaults()
        #expect(SleepSchedule(defaults: defaults) == SleepSchedule())
        var sleep = SleepSchedule()
        sleep.start(.twoHours, at: date(8, 0), calendar: utc)
        sleep.save(to: defaults)
        #expect(SleepSchedule(defaults: defaults) == sleep)
        sleep.wake()
        sleep.save(to: defaults)
        #expect(defaults.object(forKey: SleepSchedule.wakeKey) == nil)
        #expect(defaults.object(forKey: SleepSchedule.optionKey) == nil)
    }

    @Test("An unknown saved option keeps the wake-up time")
    func unknownOption() throws {
        let defaults = try makeDefaults()
        defaults.set(date(13, 0).timeIntervalSince1970, forKey: SleepSchedule.wakeKey)
        defaults.set(99, forKey: SleepSchedule.optionKey)
        let sleep = SleepSchedule(defaults: defaults)
        #expect(sleep.option == nil)
        #expect(sleep.isAsleep(at: date(12, 0)))
    }

    @Test(
        "Time left is rounded up to whole minutes",
        arguments: [(30.0, "1 min"), (2490.0, "42 min"), (7200.0, "2 h"), (11_100.0, "3 h 5 min")])
    func remaining(seconds: Double, expected: String) {
        let now = date(12, 0)
        let sleep = SleepSchedule(wakeAt: now.addingTimeInterval(seconds), option: nil)
        #expect(sleep.remainingText(at: now) == expected)
        #expect(sleep.remainingText(at: now.addingTimeInterval(seconds)) == "")
    }

    @Test("Wake-up times read as a clock time, or as midnight")
    func untilText() {
        #expect(SleepSchedule.untilText(date(12, 47), calendar: utc, locale: british) == "until 12:47")
        #expect(SleepSchedule.untilText(date(0, 0), calendar: utc, locale: british) == "until midnight")
    }

    @Test("The card and VoiceOver say until when the icon sleeps")
    func texts() {
        #expect(
            SleepText.cardHeader("1 session needs you", wakeAt: date(12, 47), calendar: utc, locale: british)
                == "Asleep until 12:47 · 1 session needs you")
        #expect(
            SleepText.accessibilityPrefix(wakeAt: date(0, 0), calendar: utc, locale: british)
                == "Asleep until midnight.")
    }
}

@Suite("Asleep state")
struct AsleepStateTests {
    @Test("Asleep outranks every session state and plays no animation")
    func silent() {
        #expect(IconState.allCases.allSatisfy { $0 <= .asleep })
        #expect(StateText.label(for: .asleep) == "Asleep")
        var scheduler = AnimationScheduler(repeatInterval: 15)
        let start = date(12, 0)
        _ = scheduler.update(to: .needsYou, at: start, reduceMotion: false)
        let falling = scheduler.update(to: .asleep, at: start.addingTimeInterval(1), reduceMotion: false)
        #expect(falling == .init(stateChanged: true, animation: nil))
        let later = scheduler.update(to: .asleep, at: start.addingTimeInterval(60), reduceMotion: false)
        #expect(later == .init(stateChanged: false, animation: nil))
    }

    @Test("Waking up with a session waiting jumps and waves right away")
    func wakeShowsRealState() {
        var scheduler = AnimationScheduler(repeatInterval: 15)
        let start = date(12, 0)
        _ = scheduler.update(to: .asleep, at: start, reduceMotion: false)
        let waking = scheduler.update(to: .needsYou, at: start.addingTimeInterval(5), reduceMotion: false)
        #expect(waking == .init(stateChanged: true, animation: .jumpAndWave))
    }
}

@Suite("Card size and sleep slider settings")
struct CardSettingsTests {
    private func makeDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "attention-buddy-card-\(UUID().uuidString)"))
    }

    @Test("The card starts at 1× with the sleep slider shown")
    func defaults() throws {
        let settings = AttentionSettings(defaults: try makeDefaults())
        #expect(settings.cardScale == 1)
        #expect(settings.showsSleepSlider)
        #expect(AttentionSettings.cardScaleRange == 1...2)
    }

    @Test("Saved values are read and card sizes are clamped", arguments: [(0.5, 1.0), (1.5, 1.5), (3.0, 2.0)])
    func saved(cardScale: Double, expected: Double) throws {
        let defaults = try makeDefaults()
        defaults.set(cardScale, forKey: "cardScale")
        defaults.set(false, forKey: "showSleepSlider")
        let settings = AttentionSettings(defaults: defaults)
        #expect(settings.cardScale == expected)
        #expect(!settings.showsSleepSlider)
        #expect(AttentionSettings.clampedCardScale(cardScale) == expected)
    }

    @Test("The card size label", arguments: [(1.0, "1×"), (1.25, "1.3×"), (1.5, "1.5×"), (2.0, "2×")])
    func label(scale: Double, expected: String) {
        #expect(AttentionSettings.cardSizeLabel(forScale: scale) == expected)
    }
}
