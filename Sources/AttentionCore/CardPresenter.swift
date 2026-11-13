/// Decides when the session card opens and closes.
///
/// - Hovering the icon opens it after a short pause; it closes shortly after the pointer has
///   left both the icon and the card, so moving from one to the other keeps it open.
/// - Clicking the icon opens it at once and pins it: it then stays open until the icon is
///   clicked again, a session is chosen, or the user clicks anywhere else.
///
/// The app turns each returned action into timers and window calls; the rules stay testable.
public struct CardPresenter: Sendable {
    public enum Action: Equatable, Sendable {
        case none
        /// Start the short hover delay, then call `showDelayEnded()`.
        case scheduleShow
        /// Start the short grace period, then call `hideDelayEnded()`.
        case scheduleHide
        /// Cancel any pending show or hide.
        case cancelPending
        case show
        case hide
    }

    public private(set) var isShown = false
    public private(set) var isPinned = false
    private var pointerInIcon = false
    private var pointerInCard = false

    public init() {}

    public mutating func pointerEnteredIcon() -> Action {
        pointerInIcon = true
        return isShown ? .cancelPending : .scheduleShow
    }

    public mutating func pointerExitedIcon() -> Action {
        pointerInIcon = false
        guard isShown else {
            return .cancelPending
        }
        if isPinned || pointerInCard {
            return .none
        }
        return .scheduleHide
    }

    public mutating func pointerEnteredCard() -> Action {
        pointerInCard = true
        return .cancelPending
    }

    public mutating func pointerExitedCard() -> Action {
        pointerInCard = false
        if !isShown || isPinned || pointerInIcon {
            return .none
        }
        return .scheduleHide
    }

    public mutating func showDelayEnded() -> Action {
        guard pointerInIcon, !isShown else {
            return .none
        }
        isShown = true
        return .show
    }

    public mutating func hideDelayEnded() -> Action {
        guard isShown, !isPinned, !pointerInIcon, !pointerInCard else {
            return .none
        }
        isShown = false
        return .hide
    }

    /// A click on the icon toggles a pinned card.
    public mutating func iconClicked() -> Action {
        if isShown && isPinned {
            return dismiss()
        }
        isShown = true
        isPinned = true
        return .show
    }

    /// A click outside the icon and the card, a chosen session, a drag or the right-click menu.
    public mutating func dismiss() -> Action {
        guard isShown else {
            return .cancelPending
        }
        isShown = false
        isPinned = false
        return .hide
    }
}
