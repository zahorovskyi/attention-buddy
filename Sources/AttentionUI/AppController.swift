import AppKit

#if canImport(AttentionCore)
    import AttentionCore
#endif

/// Runs the floating icon: reads session state as soon as it changes (and twice a second as a
/// fallback), updates the icon, marks sessions as seen when the user looks at Claude,
/// and handles clicks, the hover card, sleep and the menu.
@MainActor
public final class AppController: NSObject, NSApplicationDelegate {
    /// The Claude desktop app. Switching to it counts as "looking at" every session.
    public static let claudeBundleIdentifier = "com.anthropic.claudefordesktop"
    /// Opens Claude's "Sessions waiting for you" list.
    public static let waitingSessionsURL = ClaudeLinks.waitingSessions

    private let store: SessionStore
    private var settings: AttentionSettings
    private var settingsWindow: SettingsWindow?
    private let preferences: UserDefaults
    private var seen: SeenTracker
    /// While asleep the icon stays grey and silent; saved so it survives a restart.
    private(set) var sleep: SleepSchedule
    private var scheduler: AnimationScheduler
    private var sessions: [SessionRecord] = []
    private var resolved: [(session: SessionRecord, state: IconState)] = []
    private var panel: FloatingPanel?
    private var iconView: IconView?
    private var timer: Timer?
    private let watcher = StateFolderWatcher()
    private let hoverCard = HoverCard()
    private var presenter = CardPresenter()
    private var pendingCardWork: DispatchWorkItem?
    private var outsideClickMonitor: Any?
    private let desktopSessions = DesktopSessionIndex()
    /// Pause before the card opens on hover, and grace period before it closes.
    static let cardShowDelay: TimeInterval = 0.35
    static let cardHideDelay: TimeInterval = 0.25
    /// Keeps macOS App Nap from slowing the icon's timers while it sits in the background.
    private var activity: NSObjectProtocol?

    /// Watches the app's own program file; when an update replaces it, `onUpdateInstalled` runs.
    public var executableWatcher: ExecutableWatcher?
    /// Restarts into the new version (set by the entry point, which owns the instance lock).
    public var onUpdateInstalled: (() -> Void)?
    private var updateHandled = false

    public init(store: SessionStore, settings: AttentionSettings, preferences: UserDefaults) {
        self.store = store
        self.settings = settings
        self.preferences = preferences
        self.seen = SeenTracker(timeout: settings.seenTimeout)
        self.scheduler = AnimationScheduler(repeatInterval: settings.repeatInterval)
        self.sleep = SleepSchedule(defaults: preferences)
        super.init()
        hoverCard.scale = CGFloat(settings.cardScale)
        hoverCard.showsSleepSlider = settings.showsSleepSlider
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let view = makeIconView(scale: settings.scale)
        let panel = FloatingPanel(contentView: view)
        panel.setFrameOrigin(restoredOrigin(size: view.frame.size))
        panel.orderFrontRegardless()
        self.panel = panel
        self.iconView = view

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

        hoverCard.onPointerInside = { [weak self] inside in
            guard let self else {
                return
            }
            self.apply(inside ? self.presenter.pointerEnteredCard() : self.presenter.pointerExitedCard())
        }
        hoverCard.onSelectSession = { [weak self] sessionID in self?.openSession(sessionID) }
        hoverCard.onChooseSleep = { [weak self] option in self?.startSleep(option) }
        hoverCard.onWake = { [weak self] in self?.wakeUp() }
        // Clicks in other apps close a pinned card. (Monitors never see this app's own clicks.)
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else {
                    return
                }
                self.apply(self.presenter.dismiss())
            }
        }

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

    private func makeIconView(scale: Double) -> IconView {
        let view = IconView(scale: CGFloat(scale))
        view.onClick = { [weak self] in self?.iconClicked() }
        view.onMoved = { [weak self] in self?.savePosition() }
        view.onMenu = { [weak self] event in self?.showMenu(for: event) }
        view.onHover = { [weak self] inside in self?.hoverChanged(inside) }
        view.onDragBegan = { [weak self] in self?.dismissCard() }
        return view
    }

    // MARK: Size

    /// Swaps in an icon of the new size, keeping the edges nearest the screen corner in place.
    private func resizeIcon(to scale: Double) {
        guard let panel, scale != settings.scale else {
            return
        }
        settings.scale = scale
        preferences.set(scale, forKey: "scale")

        dismissCard()
        let view = makeIconView(scale: scale)
        view.show(scheduler.current, animated: false, reduceMotion: reduceMotion)
        view.setAccessibilityLabel(iconView?.accessibilityLabel())
        panel.replaceContent(with: view, screens: visibleScreens())
        iconView = view
        savePosition()
    }

    /// Opens the Settings window. Deliberately not named `openSettings`: see `makeMenu()`.
    @objc private func openConfigurationWindow() {
        if settingsWindow == nil {
            let window = SettingsWindow(
                scale: settings.scale, cardScale: settings.cardScale, showsSleepSlider: settings.showsSleepSlider)
            window.onScaleChange = { [weak self] scale in self?.resizeIcon(to: scale) }
            window.onCardScaleChange = { [weak self] scale in self?.resizeCard(to: scale) }
            window.onSleepSliderChange = { [weak self] shows in self?.setSleepSliderShown(shows) }
            settingsWindow = window
        }
        settingsWindow?.update(
            scale: settings.scale, cardScale: settings.cardScale, showsSleepSlider: settings.showsSleepSlider)
        settingsWindow?.show()
    }

    /// Resizes the session card and its sleep slider.
    private func resizeCard(to scale: Double) {
        guard scale != settings.cardScale else {
            return
        }
        settings.cardScale = scale
        preferences.set(scale, forKey: "cardScale")
        hoverCard.scale = CGFloat(scale)
        if hoverCard.isVisible {
            showCard()
        }
    }

    /// Shows or hides the sleep slider. Hiding it also wakes the icon, so a sleep never lingers
    /// without its Wake up button.
    func setSleepSliderShown(_ shows: Bool) {
        settings.showsSleepSlider = shows
        preferences.set(shows, forKey: "showSleepSlider")
        hoverCard.showsSleepSlider = shows
        if !shows && sleep.wakeAt != nil {
            wakeUp()
        }
        if hoverCard.isVisible {
            showCard()
        }
    }

    // MARK: Sleep

    /// Puts the icon to sleep (or changes how long). The card stays open, so the user sees it.
    func startSleep(_ option: SleepOption) {
        sleep.start(option, at: Date())
        sleep.save(to: preferences)
        refresh()
    }

    func wakeUp() {
        sleep.wake()
        sleep.save(to: preferences)
        refresh()
    }

    @objc private func resumeFromMenu() {
        wakeUp()
    }

    @objc private func durationChosen(_ item: NSMenuItem) {
        guard let option = SleepOption(rawValue: item.tag) else {
            return
        }
        startSleep(option)
    }

    // MARK: Session card

    private func hoverChanged(_ inside: Bool) {
        apply(inside ? presenter.pointerEnteredIcon() : presenter.pointerExitedIcon())
    }

    private func dismissCard() {
        apply(presenter.dismiss())
    }

    /// Carries out what `CardPresenter` decided.
    private func apply(_ action: CardPresenter.Action) {
        switch action {
        case .none:
            break
        case .cancelPending:
            cancelPendingCardWork()
        case .scheduleShow:
            schedule(after: Self.cardShowDelay) { $0.presenter.showDelayEnded() }
        case .scheduleHide:
            schedule(after: Self.cardHideDelay) { $0.presenter.hideDelayEnded() }
        case .show:
            cancelPendingCardWork()
            showCard()
        case .hide:
            cancelPendingCardWork()
            hoverCard.hide()
        }
    }

    private func schedule(after delay: TimeInterval, _ decide: @escaping (AppController) -> CardPresenter.Action) {
        cancelPendingCardWork()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else {
                    return
                }
                self.apply(decide(self))
            }
        }
        pendingCardWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelPendingCardWork() {
        pendingCardWork?.cancel()
        pendingCardWork = nil
    }

    private func showCard() {
        guard let frame = panel?.frame else {
            return
        }
        var content = HoverCardContent.make(from: withDesktopTitles(resolved, refresh: true)) {
            [desktopSessions] session in
            desktopSessions.desktopID(for: session.id) != nil
        }
        let now = Date()
        let asleep = sleep.isAsleep(at: now)
        if asleep, let wakeAt = sleep.wakeAt {
            content.header = SleepText.cardHeader(content.header, wakeAt: wakeAt)
        }
        hoverCard.updateSleep(asleep: asleep, option: sleep.option, remaining: sleep.remainingText(at: now))
        hoverCard.show(content, near: frame)
    }

    /// Uses the title the user gave a session in the Claude desktop app, which no hook reports,
    /// so a rename shows up while the card is open. `refresh` re-reads files that changed.
    private func withDesktopTitles(
        _ entries: [(session: SessionRecord, state: IconState)],
        refresh: Bool
    ) -> [(session: SessionRecord, state: IconState)] {
        let titled = desktopSessions.applyingDesktopTitles(to: entries.map(\.session), refresh: refresh)
        return zip(titled, entries).map { (session: $0, state: $1.state) }
    }

    /// Opens one session in the Claude desktop app and closes the card.
    private func openSession(_ sessionID: String) {
        dismissCard()
        guard let session = sessions.first(where: { $0.id == sessionID }),
            let desktopID = desktopSessions.desktopID(for: sessionID),
            let url = ClaudeLinks.session(desktopID, isWaiting: session.status == .needs)
        else {
            activateClaude()
            return
        }
        seen.markSeen([session], at: Date())
        refresh()
        NSWorkspace.shared.open(url)
    }

    // MARK: Refresh

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func refresh() {
        if !updateHandled, executableWatcher?.hasBeenReplaced() == true {
            updateHandled = true
            onUpdateInstalled?()
            return
        }
        let now = Date()
        sessions = store.load()
        seen.forget(sessionsNotIn: Set(sessions.map(\.id)))
        resolved = StateResolver.resolve(sessions, seen: seen, at: now)
        if sleep.wakeAt != nil && !sleep.isAsleep(at: now) {
            sleep.wake()
            sleep.save(to: preferences)
        }
        // Asleep, the icon stays grey and silent; on waking it shows the real state right away.
        var state = IconState.aggregate(resolved.map(\.state))
        if sleep.isAsleep(at: now) {
            state = .asleep
        }

        let update = scheduler.update(to: state, at: now, reduceMotion: reduceMotion)
        if update.stateChanged {
            iconView?.show(state, animated: true, reduceMotion: reduceMotion)
        }
        if let animation = update.animation {
            iconView?.play(animation)
        }
        // VoiceOver reads the same text the session card shows. Titles already read from the
        // desktop app are used, but files are only re-read while the card is open.
        var description = StateText.tooltip(for: withDesktopTitles(resolved, refresh: false))
        if state == .asleep, let wakeAt = sleep.wakeAt {
            description = SleepText.accessibilityPrefix(wakeAt: wakeAt) + "\n" + description
        }
        if iconView?.accessibilityLabel() != description {
            iconView?.setAccessibilityLabel(description)
        }
        if hoverCard.isVisible {
            showCard()
        }
    }

    private func markSessionsSeen() {
        seen.markSeen(sessions, at: Date())
        refresh()
    }

    // MARK: Events

    @objc private func applicationActivated(_ notification: Notification) {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        if app?.bundleIdentifier == Self.claudeBundleIdentifier {
            markSessionsSeen()
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

    /// A click opens (or closes) the session card, pinned open, and counts as looking at every
    /// session. Choosing a session in the card opens it in Claude.
    private func iconClicked() {
        markSessionsSeen()
        apply(presenter.iconClicked())
    }

    // MARK: Menu

    private func showMenu(for event: NSEvent) {
        guard let iconView else {
            return
        }
        dismissCard()
        NSMenu.popUpContextMenu(makeMenu(), with: event, for: iconView)
    }

    /// The right-click menu. The sessions themselves live in the hover card; the menu only holds
    /// actions, all without icons so every item lines up.
    ///
    /// Action names matter: macOS 26 adds a symbol on its own to items whose action looks like a
    /// standard one (an action named `openSettings` gets a gear), which indents the whole group.
    /// So the Settings item uses the neutral name `openConfigurationWindow`.
    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(actionItem("Show waiting sessions", #selector(showWaitingSessions)))
        menu.addItem(actionItem("Mark all as seen", #selector(markAllSeen)))
        menu.addItem(actionItem("Forget all sessions", #selector(forgetSessions)))
        menu.addItem(.separator())
        menu.addItem(sleepMenuItem())
        if sleep.isAsleep(at: Date()) {
            menu.addItem(actionItem("Wake up", #selector(resumeFromMenu)))
        }
        menu.addItem(.separator())
        menu.addItem(actionItem("Settings…", #selector(openConfigurationWindow)))
        menu.addItem(actionItem("About Attention Buddy \(AppVersion.current)", #selector(openAbout)))
        menu.addItem(.separator())
        menu.addItem(actionItem("Hide until next session", #selector(hideUntilNextSession)))
        menu.addItem(actionItem("Quit", #selector(quit)))
        return menu
    }

    /// "Sleep" with one item per duration. Action and item names stay neutral, see `makeMenu()`.
    private func sleepMenuItem() -> NSMenuItem {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for option in SleepOption.allCases {
            let item = actionItem(option.title, #selector(durationChosen(_:)))
            item.tag = option.rawValue
            submenu.addItem(item)
        }
        let parent = NSMenuItem(title: "Sleep", action: nil, keyEquivalent: "")
        parent.submenu = submenu
        return parent
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
        markSessionsSeen()
        openWaitingSessions()
    }

    @objc private func markAllSeen() {
        markSessionsSeen()
    }

    @objc private func forgetSessions() {
        store.removeAll()
        refresh()
    }

    /// Closes the icon; the next Claude Code session starts it again.
    @objc private func hideUntilNextSession() {
        NSApp.terminate(nil)
    }

    /// Closes the icon until the next login: the note stops session starts from bringing it back.
    @objc private func quit() {
        QuitNote(directory: store.directory).write()
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
