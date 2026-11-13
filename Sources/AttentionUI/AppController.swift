import AppKit

#if canImport(AttentionCore)
    import AttentionCore
#endif

/// Runs the floating icon: reads session state as soon as it changes (and twice a second as a
/// fallback), updates the icon, marks waiting sessions as seen when the user looks at Claude,
/// and handles clicks, the hover card and the menu.
@MainActor
public final class AppController: NSObject, NSApplicationDelegate {
    /// The Claude desktop app. Switching to it counts as "looking at" waiting sessions.
    public static let claudeBundleIdentifier = "com.anthropic.claudefordesktop"
    /// Opens Claude's "Sessions waiting for you" list.
    public static let waitingSessionsURL = URL(string: "claude://code/needs-input")

    private let store: SessionStore
    private let settings: AttentionSettings
    private let preferences: UserDefaults
    private var seen: SeenTracker
    private var scheduler: AnimationScheduler
    private var sessions: [SessionRecord] = []
    private var resolved: [(session: SessionRecord, state: IconState)] = []
    private var panel: FloatingPanel?
    private var iconView: IconView?
    private var timer: Timer?
    private let watcher = StateFolderWatcher()
    private let hoverCard = HoverCard()
    private var hoverWork: DispatchWorkItem?
    /// Keeps macOS App Nap from slowing the icon's timers while it sits in the background.
    private var activity: NSObjectProtocol?

    public init(store: SessionStore, settings: AttentionSettings, preferences: UserDefaults) {
        self.store = store
        self.settings = settings
        self.preferences = preferences
        self.seen = SeenTracker(timeout: settings.seenTimeout)
        self.scheduler = AnimationScheduler(repeatInterval: settings.repeatInterval)
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let view = IconView(scale: CGFloat(settings.scale))
        let panel = FloatingPanel(contentView: view)
        panel.setFrameOrigin(restoredOrigin(size: view.frame.size))
        panel.orderFrontRegardless()
        self.panel = panel
        self.iconView = view

        view.onClick = { [weak self] in self?.iconClicked() }
        view.onMoved = { [weak self] in self?.savePosition() }
        view.onMenu = { [weak self] event in self?.showMenu(for: event) }
        view.onHover = { [weak self] inside in self?.hoverChanged(inside) }

        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Shows Claude Code session state as it changes")

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(
            self, selector: #selector(applicationActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        workspace.addObserver(
            self, selector: #selector(accessibilityOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        refresh()
        try? FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        watcher.start(watching: store.directory) { [weak self] in
            self?.refresh()
        }
        // The poll catches what the watcher can't: the "seen" timeout, repeat animations and exited sessions.
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
    }

    // MARK: Hover card

    private func hoverChanged(_ inside: Bool) {
        hoverWork?.cancel()
        hoverWork = nil
        guard inside else {
            hoverCard.hide()
            return
        }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.showHoverCard()
            }
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func showHoverCard() {
        guard let frame = panel?.frame else {
            return
        }
        hoverCard.show(HoverCardContent.make(from: resolved), near: frame)
    }

    // MARK: Refresh

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func refresh() {
        let now = Date()
        sessions = store.load()
        seen.forget(sessionsNotIn: Set(sessions.map(\.id)))
        resolved = StateResolver.resolve(sessions, seen: seen, at: now)
        let state = IconState.aggregate(resolved.map(\.state))

        let update = scheduler.update(to: state, at: now, reduceMotion: reduceMotion)
        if update.stateChanged {
            iconView?.show(state, animated: true, reduceMotion: reduceMotion)
        }
        if let animation = update.animation {
            iconView?.play(animation)
        }
        // VoiceOver reads the same text the hover card shows.
        let description = StateText.tooltip(for: resolved)
        if iconView?.accessibilityLabel() != description {
            iconView?.setAccessibilityLabel(description)
        }
        if hoverCard.isVisible {
            showHoverCard()
        }
    }

    private func markWaitingSessionsSeen() {
        seen.markSeen(sessions, at: Date())
        refresh()
    }

    // MARK: Events

    @objc private func applicationActivated(_ notification: Notification) {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        if app?.bundleIdentifier == Self.claudeBundleIdentifier {
            markWaitingSessionsSeen()
        }
    }

    @objc private func accessibilityOptionsChanged() {
        iconView?.show(scheduler.current, animated: false, reduceMotion: reduceMotion)
    }

    @objc private func screensChanged() {
        guard let panel else {
            return
        }
        let origin = Placement.clamp(origin: panel.frame.origin, size: panel.frame.size, screens: visibleScreens())
        panel.setFrameOrigin(origin)
    }

    private func iconClicked() {
        let needsAttention = [IconState.needsYou, .seen, .error].contains(scheduler.current)
        markWaitingSessionsSeen()
        if needsAttention {
            openWaitingSessions()
        } else {
            activateClaude()
        }
    }

    // MARK: Menu

    private func showMenu(for event: NSEvent) {
        guard let iconView else {
            return
        }
        // The sessions themselves live in the hover card; the menu only holds actions.
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(actionItem("Show waiting sessions", #selector(showWaitingSessions)))
        menu.addItem(actionItem("Mark all as seen", #selector(markAllSeen)))
        menu.addItem(actionItem("Forget all sessions", #selector(forgetSessions)))
        menu.addItem(.separator())
        menu.addItem(actionItem("About Attention Buddy \(AppVersion.current)", #selector(openAbout)))
        menu.addItem(actionItem("Quit", #selector(quit)))
        NSMenu.popUpContextMenu(menu, with: event, for: iconView)
    }

    @objc private func openAbout() {
        guard let url = URL(string: AppVersion.repositoryURL) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func actionItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func showWaitingSessions() {
        markWaitingSessionsSeen()
        openWaitingSessions()
    }

    @objc private func markAllSeen() {
        markWaitingSessionsSeen()
    }

    @objc private func forgetSessions() {
        store.removeAll()
        refresh()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: Claude

    private func openWaitingSessions() {
        guard let url = Self.waitingSessionsURL, NSWorkspace.shared.urlForApplication(toOpen: url) != nil else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func activateClaude() {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.claudeBundleIdentifier)
        else {
            return
        }
        NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: Position

    private func visibleScreens() -> [CGRect] {
        NSScreen.screens.map(\.visibleFrame)
    }

    private func restoredOrigin(size: CGSize) -> CGPoint {
        let screens = visibleScreens()
        if preferences.object(forKey: "positionX") != nil {
            let saved = CGPoint(x: preferences.double(forKey: "positionX"), y: preferences.double(forKey: "positionY"))
            return Placement.clamp(origin: saved, size: size, screens: screens)
        }
        guard let main = NSScreen.main?.visibleFrame ?? screens.first else {
            return .zero
        }
        return Placement.defaultOrigin(size: size, visibleFrame: main)
    }

    private func savePosition() {
        guard let origin = panel?.frame.origin else {
            return
        }
        preferences.set(Double(origin.x), forKey: "positionX")
        preferences.set(Double(origin.y), forKey: "positionY")
    }
}
