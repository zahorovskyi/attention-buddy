import AppKit
import QuartzCore
import Testing

@testable import AttentionCore
@testable import AttentionUI

@Suite("Icon geometry")
struct IconGeometryTests {
    @Test("The canvas keeps the artwork's proportions at any scale")
    func size() {
        #expect(IconGeometry.size(scale: 2) == CGSize(width: 52, height: 42))
    }

    @Test("Artwork coordinates shift by the margin and scale")
    func canvasRect() {
        let rect = IconGeometry.canvasRect(CGRect(x: 3, y: 5, width: 18, height: 12), scale: 2)
        #expect(rect == CGRect(x: 8, y: 10, width: 36, height: 24))
    }

    @Test("The body path cuts out both eyes")
    func eyeHoles() {
        let path = IconGeometry.bodyPath(scale: 1)
        let leftEyeCenter = CGPoint(x: 3.7, y: 4.5)
        let bodyCenter = CGPoint(x: 9, y: 9)
        #expect(!path.contains(leftEyeCenter, using: .evenOdd))
        #expect(path.contains(bodyCenter, using: .evenOdd))
    }
}

@Suite("Icon styles")
struct IconStyleTests {
    @Test("Only needs you pulses, only working walks")
    func loops() {
        for state in IconState.allCases {
            let style = IconStyle.forState(state)
            #expect(style.pulses == (state == .needsYou))
            #expect(style.walks == (state == .working))
        }
    }

    @Test("Colors: clay while idle or working, red when it needs you, green when done")
    func colors() {
        #expect(IconStyle.forState(.working).color == Palette.clay)
        #expect(IconStyle.forState(.working).opacity < 1)
        #expect(IconStyle.forState(.needsYou).color == Palette.red)
        #expect(IconStyle.forState(.seen).color == Palette.red)
        #expect(IconStyle.forState(.error).color == Palette.red)
        #expect(IconStyle.forState(.done).color == Palette.green)
    }
}

/// Keyframe values as plain numbers, whatever numeric type they were stored as.
private func numbers(_ values: [Any]?) -> [Double] {
    (values ?? []).compactMap { ($0 as? NSNumber)?.doubleValue }
}

@Suite("Animations")
struct IconAnimationTests {
    @Test("The wave turns the right arm upward (negative angles in y-down space)")
    func waveDirection() throws {
        let values = try #require(IconAnimations.wave().values as? [Double])
        #expect(values.first == 0 && values.last == 0)
        #expect(values.dropFirst().dropLast().allSatisfy { $0 < 0 })
        #expect(values.min()! >= -Double.pi)
    }

    @Test("Raising arms turns the left arm clockwise and the right arm counterclockwise")
    func armDirections() throws {
        let left = try #require(IconAnimations.armUp(left: true).values as? [Double])
        let right = try #require(IconAnimations.armUp(left: false).values as? [Double])
        #expect(left.max()! > 0)
        #expect(right.min()! < 0)
    }

    @Test("The jump moves up by four icon pixels at the given scale")
    func jumpHeight() throws {
        let group = IconAnimations.jump(scale: 2)
        let rise = try #require(group.animations?.first as? CAKeyframeAnimation)
        #expect(rise.keyPath == "transform.translation.y")
        #expect(numbers(rise.values).min() == -8)
        #expect(group.duration == 1)
    }

    @Test("Looping animations repeat forever and one-shots do not")
    func repetition() {
        #expect(IconAnimations.pulse().repeatCount == .infinity)
        #expect(IconAnimations.step(phase: 0, scale: 1).repeatCount == .infinity)
        #expect(IconAnimations.wave().repeatCount == 0)
        #expect(IconAnimations.shake(scale: 1).repeatCount == 0)
    }

    @Test("The two leg pairs step in opposite phases")
    func legPhases() {
        let first = numbers(IconAnimations.step(phase: 0, scale: 1).values)
        let second = numbers(IconAnimations.step(phase: 1, scale: 1).values)
        #expect(first == [0, -1])
        #expect(second == [-1, 0])
    }
}

@MainActor
@Suite("Icon view")
struct IconViewTests {
    @Test("The figure has a body, two arms and four legs")
    func parts() {
        let view = IconView(scale: 2)
        #expect(view.shapeLayers.count == 7)
        #expect(view.figureLayer.sublayers?.count == 7)
    }

    @Test("Arms rotate around the shoulders")
    func pivots() {
        let view = IconView(scale: 2)
        #expect(view.rightArmLayer.position == IconGeometry.canvasPoint(IconGeometry.rightShoulder, scale: 2))
        #expect(view.leftArmLayer.position == IconGeometry.canvasPoint(IconGeometry.leftShoulder, scale: 2))
    }

    @Test("Each state starts the right looping animations")
    func loopsPerState() {
        let view = IconView(scale: 2)
        view.show(.needsYou, animated: false, reduceMotion: false)
        #expect(view.figureLayer.animation(forKey: "pulse") != nil)
        #expect(view.bodyLayer.animation(forKey: "blink") == nil)

        view.show(.working, animated: false, reduceMotion: false)
        #expect(view.figureLayer.animation(forKey: "pulse") == nil)
        #expect(view.figureLayer.animation(forKey: "bob") != nil)
        #expect(view.legLayersA.allSatisfy { $0.animation(forKey: "step") != nil })
        #expect(view.bodyLayer.animation(forKey: "blink") != nil)
        #expect(view.shownState == .working)
    }

    @Test("Reduce Motion keeps only the pulse")
    func reduceMotion() {
        let view = IconView(scale: 2)
        view.show(.working, animated: false, reduceMotion: true)
        #expect(view.figureLayer.animation(forKey: "bob") == nil)
        #expect(view.bodyLayer.animation(forKey: "blink") == nil)
        view.show(.needsYou, animated: false, reduceMotion: true)
        #expect(view.figureLayer.animation(forKey: "pulse") != nil)
    }

    @Test("One-shots attach to the right layers")
    func oneShots() {
        let view = IconView(scale: 2)
        view.play(.jumpAndWave)
        #expect(view.motionLayer.animation(forKey: "jump") != nil)
        #expect(view.rightArmLayer.animation(forKey: "wave") != nil)
        view.play(.celebrate)
        #expect(view.leftArmLayer.animation(forKey: "armUp") != nil)
        view.play(.shake)
        #expect(view.motionLayer.animation(forKey: "shake") != nil)
    }
}

/// Reads rendered pixels. Coordinates are in icon pixels of the artwork, y pointing down.
@MainActor
private struct RenderedIcon {
    let image: CGImage
    let scale: CGFloat
    private let bytes: [UInt8]

    init?(state: IconState, pose: SnapshotRenderer.Pose = .rest, scale: CGFloat = 8) {
        guard let image = SnapshotRenderer.image(state: state, pose: pose, scale: scale),
            let space = CGColorSpace(name: CGColorSpace.sRGB)
        else {
            return nil
        }
        var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard
                let context = CGContext(
                    data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                    bytesPerRow: image.width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard drawn else {
            return nil
        }
        self.image = image
        self.scale = scale
        self.bytes = buffer
    }

    /// RGBA at an artwork point. The bitmap's first row is the top of the icon.
    func pixel(_ x: CGFloat, _ y: CGFloat) -> (red: Int, green: Int, blue: Int, alpha: Int) {
        let column = Int((x + IconGeometry.offset.x) * scale)
        let row = Int((y + IconGeometry.offset.y) * scale)
        let index = (row * image.width + column) * 4
        return (Int(bytes[index]), Int(bytes[index + 1]), Int(bytes[index + 2]), Int(bytes[index + 3]))
    }
}

@MainActor
@Suite("Rendered icon")
struct RenderedIconTests {
    @Test("The body shows the state's color", arguments: [IconState.needsYou, .done])
    func bodyColor(state: IconState) throws {
        let icon = try #require(RenderedIcon(state: state))
        let body = icon.pixel(12, 8)
        #expect(body.alpha == 255)
        if state == .needsYou {
            #expect(body.red > 200 && body.green < 100)
        } else {
            #expect(body.green > 150 && body.red < 100)
        }
    }

    @Test("Eye holes and the space around the figure are transparent")
    func transparency() throws {
        let icon = try #require(RenderedIcon(state: .needsYou))
        #expect(icon.pixel(6.7, 9.5).alpha == 0)
        #expect(icon.pixel(12, 2).alpha == 0)
    }

    @Test("The figure stands upright: legs at the bottom, eyes in the upper half")
    func upright() throws {
        let icon = try #require(RenderedIcon(state: .done))
        #expect(icon.pixel(5.2, 19).alpha == 255)
        #expect(icon.pixel(5.2, 3).alpha == 0)
    }

    @Test("Waving raises the right arm above the shoulder")
    func wavingPose() throws {
        let resting = try #require(RenderedIcon(state: .needsYou))
        let waving = try #require(RenderedIcon(state: .needsYou, pose: .waving))
        #expect(resting.pixel(22, 10).alpha == 0)
        #expect(waving.pixel(22, 10).alpha == 255)
        #expect(waving.pixel(23.5, 13.5).alpha == 0)
    }

    @Test("PNG export works for every state")
    func pngExport() {
        for state in IconState.allCases {
            #expect(SnapshotRenderer.png(state: state, scale: 2) != nil)
        }
    }
}

@MainActor
@Suite("Hover card")
struct HoverCardTests {
    @Test("Shows one row per session and hides again")
    func rowsAndVisibility() {
        let card = HoverCard()
        let content = HoverCardContent(
            header: "2 sessions need you",
            rows: [
                .init(title: "Fix login", detail: "Needs your approval for Bash", state: .needsYou),
                .init(title: "Docs", detail: "Done", state: .done),
            ],
            overflow: nil)
        card.show(content, near: CGRect(x: 400, y: 400, width: 39, height: 32))
        #expect(card.isVisible)
        #expect(card.rowCount == 2)
        #expect(card.content == content)
        card.hide()
        #expect(!card.isVisible)
    }
}

@MainActor
@Suite("Settings window")
struct SettingsWindowTests {
    @Test("The slider covers 1× to 4× and starts at the current size")
    func sliderRange() {
        let settings = SettingsWindow(scale: 3)
        #expect(settings.slider.minValue == 1.5)
        #expect(settings.slider.maxValue == 6)
        #expect(settings.slider.doubleValue == 3)
        #expect(settings.sizeLabel.stringValue == "2×")
    }

    @Test("Moving the slider reports the new size and updates the label")
    func sliderReports() {
        let settings = SettingsWindow(scale: 1.5)
        var reported: [Double] = []
        settings.onScaleChange = { reported.append($0) }
        settings.slider.doubleValue = 6
        settings.sliderMoved()
        #expect(reported == [6])
        #expect(settings.sizeLabel.stringValue == "4×")
    }

    @Test("The biggest icon is four times the smallest")
    func iconSizes() {
        let small = IconView(scale: 1.5).frame.size
        let big = IconView(scale: 6).frame.size
        #expect(big.width == small.width * 4)
        #expect(big.height == small.height * 4)
    }
}

@MainActor
@Suite("Resizing the floating window")
struct FloatingPanelResizeTests {
    @Test("Swapping in a bigger icon grows the window and does not clip the icon")
    func growsWindow() {
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let small = IconView(scale: 1.5)
        let panel = FloatingPanel(contentView: small)
        panel.setFrameOrigin(Placement.defaultOrigin(size: small.frame.size, visibleFrame: screen))
        let before = panel.frame

        let big = IconView(scale: 6)
        let bigSize = big.frame.size
        panel.replaceContent(with: big, screens: [screen])

        #expect(panel.frame.size == bigSize)
        #expect(big.frame.size == bigSize)
        #expect(big.bounds.size == bigSize)
        // Bottom-right corner: the right and bottom edges did not move.
        #expect(panel.frame.maxX == before.maxX)
        #expect(panel.frame.minY == before.minY)
    }
}

@MainActor
@Suite("Right-click menu")
struct MenuTests {
    private func makeController() -> AppController {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("attention-buddy-menu-\(UUID())")
        let defaults = UserDefaults(suiteName: "attention-buddy-menu-\(UUID().uuidString)") ?? .standard
        return AppController(store: SessionStore(directory: directory), settings: .standard, preferences: defaults)
    }

    @Test("The menu holds only these actions, in this order")
    func items() {
        let titles = makeController().makeMenu().items.map { $0.isSeparatorItem ? "-" : $0.title }
        #expect(
            titles == [
                "Show waiting sessions", "Mark all as seen", "Forget all sessions", "-", "Sleep", "-", "Settings…",
                "About Attention Buddy \(AppVersion.current)", "-", "Hide until next session", "Quit",
            ])
    }

    @Test("No item has an icon, and no action name invites macOS to add one")
    func noIcons() {
        for item in makeController().makeMenu().items where !item.isSeparatorItem {
            #expect(item.image == nil)
            let action = item.action.map(NSStringFromSelector)?.lowercased() ?? ""
            #expect(!action.contains("settings") && !action.contains("preferences"), "\(item.title): \(action)")
        }
    }
}

@MainActor
@Suite("Session card clicks")
struct SessionCardClickTests {
    private let content = HoverCardContent(
        header: "1 session needs you",
        rows: [
            .init(
                title: "Desktop task", detail: "Needs your approval for Bash", state: .needsYou, sessionID: "d1",
                canOpen: true),
            .init(
                title: "api-server", detail: "Working · in a terminal", state: .working, sessionID: "t1", canOpen: false
            ),
        ],
        overflow: nil)

    @Test("Clicking a desktop session reports it; terminal sessions do nothing")
    func rowClicks() {
        let card = HoverCard()
        var opened: [String] = []
        card.onSelectSession = { opened.append($0) }
        card.show(content, near: CGRect(x: 400, y: 400, width: 39, height: 32))
        #expect(card.rowCount == 2)
        card.rowViews[0].select()
        card.rowViews[1].select()
        #expect(opened == ["d1"])
        card.hide()
    }

    @Test("The card is shaped by a rounded mask, so no square corners show behind it")
    func cardHasRoundedMask() throws {
        let card = HoverCard()
        let mask = try #require(card.backgroundMask)
        let radius = HoverCard.cornerRadius
        #expect(mask.capInsets.top == radius)
        #expect(mask.capInsets.left == radius)
        #expect(mask.capInsets.bottom == radius)
        #expect(mask.capInsets.right == radius)
        #expect(mask.resizingMode == .stretch)
        let corner = try #require(mask.bitmapAlpha(atX: 0, y: 0))
        let middle = try #require(mask.bitmapAlpha(atX: radius, y: radius))
        #expect(corner < 0.1)
        #expect(middle > 0.9)
    }

    @Test("Only openable rows highlight under the pointer and accept clicks")
    func openableRowsTrackThePointer() {
        let card = HoverCard()
        card.show(content, near: CGRect(x: 400, y: 400, width: 39, height: 32))
        card.rowViews.forEach { $0.updateTrackingAreas() }
        #expect(!card.rowViews[0].trackingAreas.isEmpty)
        #expect(card.rowViews[1].trackingAreas.isEmpty)
        #expect(card.rowViews[0].accessibilityRole() == .button)
        card.hide()
    }
}

@MainActor
@Suite("Card dots")
struct CardDotTests {
    private func row(_ state: IconState, reduceMotion: Bool = false) -> SessionRowView {
        let data = HoverCardContent.Row(title: "Task", detail: "Detail", state: state, sessionID: "s", canOpen: true)
        return SessionRowView(row: data, reduceMotion: reduceMotion) { text, _, _, _ in
            NSTextField(labelWithString: text)
        }
    }

    @Test("A session that needs you has a blinking red dot")
    func needsYouBlinks() {
        let view = row(.needsYou)
        #expect(view.dot.layer?.animation(forKey: "pulse") != nil)
        #expect(view.dot.layer?.backgroundColor == Palette.red)
    }

    @Test("A working session's dot breathes slowly")
    func workingBreathes() {
        #expect(row(.working).dot.layer?.animation(forKey: "breathe") != nil)
        #expect(IconAnimations.breathe().duration > IconAnimations.pulse().duration)
    }

    @Test("Seen, done, error and idle dots stay steady", arguments: [IconState.seen, .done, .error, .idle])
    func steady(state: IconState) {
        let layer = row(state).dot.layer
        #expect(layer?.animation(forKey: "pulse") == nil)
        #expect(layer?.animation(forKey: "breathe") == nil)
    }

    @Test("Reduce Motion keeps the red blink but stops the breathing")
    func reduceMotion() {
        #expect(row(.needsYou, reduceMotion: true).dot.layer?.animation(forKey: "pulse") != nil)
        #expect(row(.working, reduceMotion: true).dot.layer?.animation(forKey: "breathe") == nil)
    }
}

extension NSImage {
    /// The opacity of one pixel when drawn at its own size (origin bottom-left), for tests.
    fileprivate func bitmapAlpha(atX x: CGFloat, y: CGFloat) -> CGFloat? {
        let width = Int(size.width)
        let height = Int(size.height)
        guard
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0)
        else {
            return nil
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.colorAt(x: Int(x), y: height - 1 - Int(y))?.alphaComponent
    }
}

// MARK: Sleep

@MainActor
@Suite("Sleeping icon")
struct SleepingIconTests {
    private func degrees(_ transform: CATransform3D) -> Double {
        atan2(Double(transform.m12), Double(transform.m11)) * 180 / .pi
    }

    @Test("Asleep is grey and still: no pulse, no walking, no blinking")
    func style() {
        let style = IconStyle.forState(.asleep)
        #expect(style.color == Palette.grey)
        #expect(style.sleeps)
        #expect(!style.pulses && !style.walks && !style.blinks)
        #expect(IconState.allCases.filter { IconStyle.forState($0).sleeps } == [.asleep])
    }

    @Test("The arms hang down while asleep and come back when it wakes")
    func arms() {
        let view = IconView(scale: 4)
        view.show(.asleep, animated: false, reduceMotion: true)
        #expect(abs(degrees(view.leftArmLayer.transform) + 72) < 0.01)
        #expect(abs(degrees(view.rightArmLayer.transform) - 72) < 0.01)
        view.show(.needsYou, animated: false, reduceMotion: true)
        #expect(CATransform3DIsIdentity(view.leftArmLayer.transform))
        #expect(CATransform3DIsIdentity(view.rightArmLayer.transform))
    }

    @Test("The eyes close to a thin slit at the bottom")
    func eyes() throws {
        let awake = try #require(RenderedIcon(state: .done))
        let asleep = try #require(RenderedIcon(state: .asleep))
        #expect(awake.pixel(6.7, 9).alpha == 0)
        #expect(asleep.pixel(6.7, 9).alpha == 255)
        #expect(asleep.pixel(6.7, 10.8).alpha == 0)
        #expect(asleep.pixel(12, 8).red == 0x8E)
    }

    @Test("It breathes and two z letters float, unless Reduce Motion is on")
    func motion() {
        let view = IconView(scale: 4)
        view.show(.asleep, animated: false, reduceMotion: false)
        #expect(view.figureLayer.animation(forKey: "breath") != nil)
        #expect(view.sleepLetters.count == 2)
        #expect(view.sleepLetters.allSatisfy { $0.animation(forKey: "float") != nil })
        view.show(.asleep, animated: false, reduceMotion: true)
        #expect(view.figureLayer.animation(forKey: "breath") == nil)
        #expect(view.sleepLetters.allSatisfy { $0.animation(forKey: "float") == nil })
        view.show(.working, animated: false, reduceMotion: false)
        #expect(view.figureLayer.animation(forKey: "breath") == nil)
    }
}

@MainActor
@Suite("Sleep slider")
struct SleepSliderTests {
    private func makeSlider(scale: CGFloat = 1) -> SleepSliderView {
        let slider = SleepSliderView(scale: scale)
        slider.frame = NSRect(x: 0, y: 0, width: SleepSliderView.baseMinimumWidth * scale, height: 66 * scale)
        slider.untilText = { option in "until test \(option.shortLabel)" }
        slider.layout()
        return slider
    }

    @Test("Stops map to positions along the track and back")
    func positions() {
        let slider = makeSlider()
        for option in SleepOption.allCases {
            let x = slider.x(at: SleepSliderView.position(of: option))
            #expect(SleepSliderView.nearestOption(to: slider.position(atX: x)) == option)
        }
        #expect(slider.position(atX: -100) == 0)
        #expect(slider.position(atX: 10_000) == 1)
    }

    @Test("Awake it invites a drag; dragging names the stop; letting go chooses it")
    func dragging() {
        let slider = makeSlider()
        var chosen: [SleepOption] = []
        slider.onChoose = { chosen.append($0) }
        #expect(slider.statusLeft.stringValue == "Sleep")
        #expect(slider.statusRight.stringValue == "Drag to choose")
        #expect(slider.wakeButton.isHidden)

        slider.beginDrag(atX: slider.x(at: 0))
        slider.drag(toX: slider.x(at: SleepSliderView.position(of: .oneHour)) + 3)
        #expect(slider.isTracking)
        #expect(slider.statusLeft.stringValue == "1 hour")
        #expect(slider.statusRight.stringValue == "until test 1h")
        slider.endDrag()
        #expect(!slider.isTracking)
        #expect(chosen == [.oneHour])
        #expect(slider.position == SleepSliderView.position(of: .oneHour))
    }

    @Test("Asleep it shows the time left and a Wake up button")
    func asleep() {
        let slider = makeSlider()
        var woke = 0
        slider.onWake = { woke += 1 }
        slider.update(asleep: true, option: .twoHours, remaining: "1 h 58 min")
        #expect(slider.statusLeft.stringValue == "Asleep · 1 h 58 min")
        #expect(!slider.wakeButton.isHidden)
        #expect(slider.selectedOption == .twoHours)
        #expect(
            slider.stopLabels[SleepOption.twoHours.rawValue].font?.fontDescriptor.symbolicTraits.contains(.bold) == true
                || slider.stopLabels[SleepOption.twoHours.rawValue].textColor == NSColor(cgColor: Palette.night))
        slider.wakeButton.press()
        #expect(woke == 1)
        slider.update(asleep: false, option: nil, remaining: "")
        #expect(slider.wakeButton.isHidden)
        #expect(slider.statusLeft.stringValue == "Sleep")
    }

    @Test("Updates from the app don't move the knob while the user drags it")
    func dragWins() {
        let slider = makeSlider()
        slider.beginDrag(atX: slider.x(at: 1))
        slider.update(asleep: true, option: .fifteenMinutes, remaining: "15 min")
        #expect(slider.selectedOption == .restOfDay)
        slider.endDrag()
    }

    @Test("VoiceOver steps through the stops")
    func accessibility() {
        let slider = makeSlider()
        var chosen: [SleepOption] = []
        slider.onChoose = { chosen.append($0) }
        #expect(slider.accessibilityRole() == .slider)
        #expect(slider.accessibilityValue() as? String == "Awake")
        #expect(slider.accessibilityPerformIncrement())
        slider.update(asleep: true, option: .fifteenMinutes, remaining: "15 min")
        #expect(slider.accessibilityPerformIncrement())
        #expect(chosen == [.fifteenMinutes, .thirtyMinutes])
        #expect(slider.wakeButton.accessibilityRole() == .button)
    }

    @Test("Every stop label fits inside the slider, even the selected one in bold")
    func labelsFit() {
        let slider = makeSlider()
        slider.update(asleep: true, option: .restOfDay, remaining: "9 h")
        for label in slider.stopLabels {
            #expect(label.frame.minX >= 0 && label.frame.maxX <= slider.bounds.width, "\(label.stringValue)")
            #expect(label.attributedStringValue.size().width <= label.frame.width, "\(label.stringValue)")
        }
    }

    @Test("Everything grows with the card size")
    func scales() {
        let normal = makeSlider()
        let big = makeSlider(scale: 2)
        #expect(big.fittingSize.height == normal.fittingSize.height * 2)
        #expect(big.stopLabels[0].font?.pointSize == (normal.stopLabels[0].font?.pointSize ?? 0) * 2)
        #expect(big.wakeButton.intrinsicContentSize.height == normal.wakeButton.intrinsicContentSize.height * 2)
    }
}

@MainActor
@Suite("Session card with the sleep slider")
struct CardSleepTests {
    private let content = HoverCardContent(
        header: "1 session needs you",
        rows: [.init(title: "Fix login", detail: "Needs your approval for Bash", state: .needsYou)],
        overflow: nil)

    @Test("The slider shows by default and survives a refresh of the rows")
    func sliderStays() throws {
        let card = HoverCard()
        card.show(content, near: CGRect(x: 400, y: 400, width: 78, height: 63))
        let slider = try #require(card.sleepSlider)
        var changed = content
        changed.header = "All done"
        card.show(changed, near: CGRect(x: 400, y: 400, width: 78, height: 63))
        #expect(card.sleepSlider === slider)
        #expect(slider.superview != nil)
        card.hide()
    }

    @Test("The card keeps its width when the summary gets longer, as when it falls asleep")
    func fixedWidth() {
        let card = HoverCard()
        card.show(content, near: CGRect(x: 400, y: 400, width: 78, height: 63))
        let awake = card.frame.width
        var asleep = content
        asleep.header = "Asleep until 16:58 · Waiting for your answer, and a few more words to be long"
        card.show(asleep, near: CGRect(x: 400, y: 400, width: 78, height: 63))
        #expect(card.frame.width == awake)
        #expect(awake == HoverCard.width)
        card.scale = 2
        card.show(asleep, near: CGRect(x: 400, y: 400, width: 78, height: 63))
        #expect(card.frame.width == HoverCard.width * 2)
        card.hide()
    }

    @Test("The Settings checkbox hides the slider")
    func hidden() {
        let card = HoverCard()
        card.showsSleepSlider = false
        card.show(content, near: CGRect(x: 400, y: 400, width: 78, height: 63))
        #expect(card.sleepSlider == nil)
        #expect(card.rowCount == 1)
        card.hide()
    }

    @Test("The card size scales the text, and the sleep state reaches the slider")
    func scaleAndState() throws {
        let card = HoverCard()
        card.scale = 1.5
        card.updateSleep(asleep: true, option: .fourHours, remaining: "3 h 59 min")
        card.show(content, near: CGRect(x: 400, y: 400, width: 78, height: 63))
        #expect(card.headerFontSize == 11 * 1.5)
        let slider = try #require(card.sleepSlider)
        #expect(slider.scale == 1.5)
        #expect(slider.selectedOption == .fourHours)
        #expect(slider.statusLeft.stringValue == "Asleep · 3 h 59 min")
        card.hide()
    }
}

@MainActor
@Suite("Sleep in the app")
struct AppSleepTests {
    private func makeController(defaults: UserDefaults) -> AppController {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("attention-buddy-sleep-\(UUID())")
        return AppController(store: SessionStore(directory: directory), settings: .standard, preferences: defaults)
    }

    @Test("Sleeping adds Wake up to the menu, is remembered after a restart, and waking clears it")
    func sleepAndWake() throws {
        let defaults = try #require(UserDefaults(suiteName: "attention-buddy-app-sleep-\(UUID().uuidString)"))
        let controller = makeController(defaults: defaults)
        let sleepItem = try #require(controller.makeMenu().items.first { $0.title == "Sleep" })
        #expect(sleepItem.submenu?.items.map(\.title) == SleepOption.allCases.map(\.title))

        controller.startSleep(.oneHour)
        #expect(controller.sleep.isAsleep(at: Date()))
        #expect(controller.makeMenu().items.contains { $0.title == "Wake up" })
        #expect(makeController(defaults: defaults).sleep.option == .oneHour)

        controller.wakeUp()
        #expect(!controller.sleep.isAsleep(at: Date()))
        #expect(!controller.makeMenu().items.contains { $0.title == "Wake up" })
        #expect(!makeController(defaults: defaults).sleep.isAsleep(at: Date()))
    }

    @Test("Hiding the sleep slider in Settings wakes the icon")
    func hidingSliderWakes() throws {
        let defaults = try #require(UserDefaults(suiteName: "attention-buddy-app-sleep-\(UUID().uuidString)"))
        let controller = makeController(defaults: defaults)
        controller.startSleep(.fourHours)
        controller.setSleepSliderShown(false)
        #expect(!controller.sleep.isAsleep(at: Date()))
        #expect(defaults.object(forKey: "showSleepSlider") as? Bool == false)
        #expect(!makeController(defaults: defaults).sleep.isAsleep(at: Date()))
    }

    @Test("Sleep menu actions have neutral names, so macOS adds no icons")
    func neutralNames() throws {
        let defaults = try #require(UserDefaults(suiteName: "attention-buddy-app-sleep-\(UUID().uuidString)"))
        let controller = makeController(defaults: defaults)
        controller.startSleep(.fifteenMinutes)
        let menu = controller.makeMenu()
        let sleepItems = menu.items.first { $0.title == "Sleep" }?.submenu?.items ?? []
        for item in menu.items + sleepItems where !item.isSeparatorItem {
            #expect(item.image == nil)
            let action = item.action.map(NSStringFromSelector)?.lowercased() ?? ""
            #expect(!action.contains("sleep") && !action.contains("wake"), "\(item.title): \(action)")
        }
        controller.wakeUp()
    }
}

@MainActor
@Suite("Settings window: card")
struct SettingsCardTests {
    @Test("The card slider covers 1× to 2× and the checkbox starts checked")
    func controls() {
        let settings = SettingsWindow(scale: 3)
        #expect(settings.cardSlider.minValue == 1)
        #expect(settings.cardSlider.maxValue == 2)
        #expect(settings.cardSizeLabel.stringValue == "1×")
        #expect(settings.sleepSliderCheckbox.state == .on)
    }

    @Test("Moving the card slider and unchecking the box report the changes")
    func reports() {
        let settings = SettingsWindow(scale: 3, cardScale: 1, showsSleepSlider: true)
        var sizes: [Double] = []
        var shown: [Bool] = []
        settings.onCardScaleChange = { sizes.append($0) }
        settings.onSleepSliderChange = { shown.append($0) }
        settings.cardSlider.doubleValue = 1.5
        settings.cardSliderMoved()
        settings.sleepSliderCheckbox.state = .off
        settings.sleepSliderToggled()
        #expect(sizes == [1.5])
        #expect(settings.cardSizeLabel.stringValue == "1.5×")
        #expect(shown == [false])
        settings.update(scale: 3, cardScale: 2, showsSleepSlider: true)
        #expect(settings.cardSizeLabel.stringValue == "2×")
        #expect(settings.sleepSliderCheckbox.state == .on)
    }
}
