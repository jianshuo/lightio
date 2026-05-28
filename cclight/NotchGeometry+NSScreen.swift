import AppKit
import CCLightCore

extension NotchGeometry {
    /// Best-effort: read the notch dimensions from `NSScreen.safeAreaInsets`
    /// when present (macOS 12+ on notched Macs), falling back to
    /// `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` (the lateral rects
    /// flanking the notch). Returns nil if the screen has no notch.
    static func notchRect(for screen: NSScreen) -> CGRect? {
        let insets = screen.safeAreaInsets
        guard insets.top > 0 else { return nil }

        let menuBarHeight = NSStatusBar.system.thickness  // ~24pt
        let notchHeight = insets.top

        // Estimate notch width from auxiliaryTopLeftArea (the rect to the LEFT of the notch).
        // If it exists, screen width - left.maxX - rightArea.width gives notch width.
        let left = screen.auxiliaryTopLeftArea
        let right = screen.auxiliaryTopRightArea
        let notchWidth: CGFloat
        if let left = left, let right = right {
            notchWidth = screen.frame.maxX - left.maxX - right.width
        } else {
            // Fallback default; M4 14" notch is ~200pt.
            notchWidth = 200
        }

        return notchRect(
            screenFrame: screen.frame,
            notchSize: CGSize(width: notchWidth, height: notchHeight),
            menuBarHeight: menuBarHeight
        )
    }
}
