import Foundation
import Testing

@testable import AttentionCore

private let start = Date(timeIntervalSince1970: 1_700_000_000)

private func session(_ id: String, _ status: SessionRecord.Status, stamp: String = "s1", age: TimeInterval = 0)
    -> SessionRecord
{
    SessionRecord(id: id, status: status, stamp: stamp, updatedAt: start.addingTimeInterval(-age))
}

@Suite("State priority")
struct PriorityTests {
    @Test("No sessions means idle")
    func emptyIsIdle() {
        #expect(IconState.aggregate([IconState]()) == .idle)
    }

    @Test(
        "The most urgent state wins",
        arguments: [
            ([IconState.working, .done], IconState.done),
            ([.done, .seen], .seen),
            ([.seen, .error], .error),
            ([.error, .needsYou, .working], .needsYou),
            ([.idle, .working], .working),
        ])
    func priority(states: [IconState], expected: IconState) {
        #expect(IconState.aggregate(states) == expected)
    }

    @Test("Each recorded status maps to an icon state")
    func statusMapping() {
        let seen = SeenTracker(timeout: 180)
        let expected: [SessionRecord.Status: IconState] = [
            .idle: .idle, .working: .working, .done: .done, .error: .error, .needs: .needsYou,
        ]
        for (status, state) in expected {
            #expect(StateResolver.state(of: session("a", status), seen: seen, at: start) == state)
        }
    }

    @Test("Resolved sessions are sorted most urgent first, then newest first")
    func resolveOrder() {
        let sessions = [
            session("old-done", .done, age: 50),
            session("needs", .needs, age: 100),
            session("new-done", .done, age: 1),
        ]
        let order = StateResolver.resolve(sessions, seen: SeenTracker(timeout: 180), at: start).map(\.session.id)
        #expect(order == ["needs", "new-done", "old-done"])
    }
}

@Suite("The seen timer")
struct SeenTrackerTests {
    @Test("Looking at Claude turns a waiting session into seen")
    func marksSeen() {
        var tracker = SeenTracker(timeout: 180)
        let waiting = session("a", .needs)
        tracker.markSeen([waiting], at: start)
        #expect(StateResolver.state(of: waiting, seen: tracker, at: start.addingTimeInterval(10)) == .seen)
    }

    @Test("Seen expires after the timeout and asks for attention again")
    func expires() {
        var tracker = SeenTracker(timeout: 180)
        let waiting = session("a", .needs)
        tracker.markSeen([waiting], at: start)
        #expect(tracker.isSeen(waiting, at: start.addingTimeInterval(179.9)))
        #expect(!tracker.isSeen(waiting, at: start.addingTimeInterval(180)))
    }

    @Test("Looking again restarts the timer")
    func lookAgainRestarts() {
        var tracker = SeenTracker(timeout: 180)
        let waiting = session("a", .needs)
        tracker.markSeen([waiting], at: start)
        tracker.markSeen([waiting], at: start.addingTimeInterval(170))
        #expect(tracker.isSeen(waiting, at: start.addingTimeInterval(300)))
    }

    @Test("A new request from the same session is not seen yet")
    func newRequestClearsSeen() {
        var tracker = SeenTracker(timeout: 180)
        tracker.markSeen([session("a", .needs, stamp: "first")], at: start)
        #expect(!tracker.isSeen(session("a", .needs, stamp: "second"), at: start.addingTimeInterval(1)))
    }

    @Test("Only waiting sessions can be marked seen")
    func ignoresOtherStatuses() {
        var tracker = SeenTracker(timeout: 180)
        let working = session("a", .working)
        tracker.markSeen([working], at: start)
        #expect(!tracker.isSeen(working, at: start))
    }

    @Test("Marks for vanished sessions are forgotten")
    func forgetsVanished() {
        var tracker = SeenTracker(timeout: 180)
        let waiting = session("a", .needs)
        tracker.markSeen([waiting], at: start)
        tracker.forget(sessionsNotIn: [])
        #expect(!tracker.isSeen(waiting, at: start))
    }
}

@Suite("Animation scheduling")
struct AnimationSchedulerTests {
    @Test("Needs you plays at once, then again only after the repeat interval")
    func needsYouRepeats() {
        var scheduler = AnimationScheduler(repeatInterval: 15)
        #expect(scheduler.update(to: .needsYou, at: start, reduceMotion: false).animation == .jumpAndWave)
        #expect(scheduler.update(to: .needsYou, at: start.addingTimeInterval(14), reduceMotion: false).animation == nil)
        #expect(
            scheduler.update(to: .needsYou, at: start.addingTimeInterval(15), reduceMotion: false).animation
                == .jumpAndWave)
    }

    @Test("Done and error play once when they start")
    func oneShots() {
        var scheduler = AnimationScheduler(repeatInterval: 15)
        #expect(
            scheduler.update(to: .done, at: start, reduceMotion: false)
                == .init(stateChanged: true, animation: .celebrate))
        #expect(
            scheduler.update(to: .done, at: start, reduceMotion: false) == .init(stateChanged: false, animation: nil))
        #expect(scheduler.update(to: .error, at: start, reduceMotion: false).animation == .shake)
    }

    @Test("Working, idle and seen have no one-shot animation", arguments: [IconState.working, .idle, .seen])
    func quietStates(state: IconState) {
        var scheduler = AnimationScheduler(repeatInterval: 15)
        _ = scheduler.update(to: .needsYou, at: start, reduceMotion: false)
        #expect(scheduler.update(to: state, at: start, reduceMotion: false).animation == nil)
    }

    @Test("Coming back to needs you from seen plays immediately")
    func returnFromSeen() {
        var scheduler = AnimationScheduler(repeatInterval: 15)
        _ = scheduler.update(to: .needsYou, at: start, reduceMotion: false)
        _ = scheduler.update(to: .seen, at: start.addingTimeInterval(2), reduceMotion: false)
        #expect(
            scheduler.update(to: .needsYou, at: start.addingTimeInterval(4), reduceMotion: false).animation
                == .jumpAndWave)
    }

    @Test("Reduce Motion turns off one-shots but still reports state changes")
    func reduceMotion() {
        var scheduler = AnimationScheduler(repeatInterval: 15)
        #expect(
            scheduler.update(to: .needsYou, at: start, reduceMotion: true) == .init(stateChanged: true, animation: nil))
    }
}

@Suite("Settings")
struct SettingsTests {
    private func makeDefaults() throws -> UserDefaults {
        let suite = "attention-buddy-tests-\(UUID().uuidString)"
        return try #require(UserDefaults(suiteName: suite))
    }

    @Test("Defaults apply when nothing is set")
    func standardValues() throws {
        #expect(AttentionSettings(defaults: try makeDefaults()) == .standard)
    }

    @Test("Values outside the allowed range are clamped")
    func clamps() throws {
        let defaults = try makeDefaults()
        defaults.set(1, forKey: "seenTimeout")
        defaults.set(100_000, forKey: "repeatInterval")
        defaults.set(2.5, forKey: "scale")
        let settings = AttentionSettings(defaults: defaults)
        #expect(settings.seenTimeout == 10)
        #expect(settings.repeatInterval == 600)
        #expect(settings.scale == 2.5)
    }
}

@Suite("Icon size")
struct IconSizeTests {
    @Test("The size runs from the original size up to four times bigger")
    func range() {
        #expect(AttentionSettings.scaleRange.lowerBound == AttentionSettings.standard.scale)
        #expect(AttentionSettings.scaleRange.upperBound == AttentionSettings.standard.scale * 4)
    }

    @Test("Saved sizes outside the range are clamped", arguments: [(0.5, 1.5), (3.0, 3.0), (100.0, 6.0)])
    func clamping(saved: Double, expected: Double) throws {
        let defaults = try #require(UserDefaults(suiteName: "attention-buddy-size-\(UUID().uuidString)"))
        defaults.set(saved, forKey: "scale")
        #expect(AttentionSettings(defaults: defaults).scale == expected)
        #expect(AttentionSettings.clampedScale(saved) == expected)
    }

    @Test(
        "The slider label shows the size as a multiple of the smallest",
        arguments: [(1.5, "1×"), (3.0, "2×"), (3.75, "2.5×"), (4.4, "2.9×"), (6.0, "4×")])
    func label(scale: Double, expected: String) {
        #expect(AttentionSettings.sizeLabel(forScale: scale) == expected)
    }
}
