import AppKit
import QuartzCore

#if canImport(AttentionCore)
    import AttentionCore
#endif

/// Renders the icon to PNG without showing a window. Used by `attention-buddy snapshot`
/// to produce reference images, and by the snapshot tests.
@MainActor
public enum SnapshotRenderer {
    /// A still pose, for checking that moving parts turn the right way.
    public enum Pose: String, CaseIterable, Sendable {
        /// The resting figure.
        case rest
        /// Right arm raised, as at the top of the wave.
        case waving
        /// Both arms up, as in the "done" hop.
        case armsUp
    }

    /// Renders `state` in `pose` and returns PNG data, or `nil` if drawing failed.
    public static func png(state: IconState, pose: Pose = .rest, scale: CGFloat) -> Data? {
        guard let image = image(state: state, pose: pose, scale: scale) else {
            return nil
        }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    /// Renders `state` in `pose` to an image whose first row is the top of the icon.
    public static func image(state: IconState, pose: Pose = .rest, scale: CGFloat) -> CGImage? {
        let view = IconView(scale: scale)
        view.show(state, animated: false, reduceMotion: true)
        apply(pose, to: view)
        return render(view)
    }

    static func apply(_ pose: Pose, to view: IconView) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        switch pose {
        case .rest:
            break
        case .waving:
            view.rightArmLayer.transform = CATransform3DMakeRotation(-90 * .pi / 180, 0, 0, 1)
        case .armsUp:
            view.leftArmLayer.transform = CATransform3DMakeRotation(80 * .pi / 180, 0, 0, 1)
            view.rightArmLayer.transform = CATransform3DMakeRotation(-80 * .pi / 180, 0, 0, 1)
        }
        CATransaction.commit()
    }

    static func render(_ view: IconView) -> CGImage? {
        guard let layer = view.layer else {
            return nil
        }
        let width = Int(view.bounds.width.rounded(.up))
        let height = Int(view.bounds.height.rounded(.up))
        guard
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else {
            return nil
        }
        // The view's own near-transparent hit area is not part of the picture.
        let background = layer.backgroundColor
        layer.backgroundColor = nil
        layer.render(in: context)
        layer.backgroundColor = background
        return context.makeImage()
    }
}
