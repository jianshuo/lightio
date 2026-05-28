import CoreGraphics
import Foundation

public enum NotchGeometry {
    /// Compute the on-screen rect of the physical notch (in screen-space points).
    /// `screenFrame` is in the same coordinate system used by `NSScreen.frame`
    /// (origin at bottom-left, y grows upward).
    public static func notchRect(screenFrame: CGRect, notchSize: CGSize, menuBarHeight: CGFloat) -> CGRect {
        let originX = screenFrame.midX - notchSize.width / 2
        let originY = screenFrame.maxY - notchSize.height
        return CGRect(origin: CGPoint(x: originX, y: originY), size: notchSize)
    }

    /// Expand the notch rect by `glowPadding` on all sides — the resulting rect
    /// is where the borderless NSWindow is placed so the glow has room to bleed.
    public static func overlayWindowFrame(notchRect: CGRect, glowPadding: CGFloat) -> CGRect {
        notchRect.insetBy(dx: -glowPadding, dy: -glowPadding)
    }
}
