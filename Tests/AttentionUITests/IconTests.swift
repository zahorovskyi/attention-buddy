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
                "Show waiting sessions", "Mark all as seen", "Forget all sessions", "-", "Settings…",
                "About Attention Buddy \(AppVersion.current)", "Quit",
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
