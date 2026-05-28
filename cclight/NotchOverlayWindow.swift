import AppKit

/// Borderless, transparent, click-through window that sits exactly under the
/// notch. Belongs to all Spaces, stays above the menu bar, never steals focus.
final class NotchOverlayWindow: NSWindow {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.level = NSWindow.Level(Int(CGShieldingWindowLevel()) + 1)
        self.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]
        // Never become key/main — we don't accept any input.
        self.acceptsMouseMovedEvents = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
