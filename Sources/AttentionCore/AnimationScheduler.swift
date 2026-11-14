import Foundation

/// A one-shot animation the icon plays on top of its looping state animation.
public enum IconAnimation: Sendable, Equatable {
    /// Jump and wave one arm: a session needs you.
    case jumpAndWave
    /// One hop with both arms up: a session finished.
    case celebrate
    /// A short head shake: a turn failed.
    case shake
}

/// Decides when to play one-shot animations as the icon's state changes over time.
///
/// "Needs you" plays when it starts and then every `repeatInterval` while nobody responds.
/// "Done" and "error" play once when they start. Reduce Motion turns all of them off.
public struct AnimationScheduler: Sendable {
    public var repeatInterval: TimeInterval
    public private(set) var current: IconState = .idle
    private var lastAttention: Date?

    public init(repeatInterval: TimeInterval) {
        self.repeatInterval = repeatInterval
    }

    public struct Update: Equatable, Sendable {
        /// Whether the shown state changed, so the looping animation and colors need updating.
        public var stateChanged: Bool
        /// The one-shot animation to play now, if any.
        public var animation: IconAnimation?
    }

    public mutating func update(to state: IconState, at now: Date, reduceMotion: Bool) -> Update {
        let changed = state != current
        current = state

        var animation: IconAnimation?
        switch state {
        case .needsYou:
            if changed || isRepeatDue(at: now) {
                lastAttention = now
                animation = .jumpAndWave
            }
        case .done:
            if changed {
                animation = .celebrate
            }
        case .error:
            if changed {
                animation = .shake
            }
        case .idle, .working, .seen, .asleep:
            animation = nil
        }

        if state != .needsYou {
            lastAttention = nil
        }
        if reduceMotion {
            animation = nil
        }
        return Update(stateChanged: changed, animation: animation)
    }

    private func isRepeatDue(at now: Date) -> Bool {
        guard let lastAttention else {
            return true
        }
        return now.timeIntervalSince(lastAttention) >= repeatInterval
    }
}
