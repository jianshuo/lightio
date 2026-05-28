import AppKit
import Combine
import QuartzCore
import VibelightCore

/// Renders the glow underneath the notch. Driven by a published `MergedState`.
final class NotchOverlayView: NSView {
    private let glowLayer = CALayer()
    private let outerGlowLayer = CALayer()
    private let lineLayer = CALayer()
    private var subs: Set<AnyCancellable> = []
    private var currentState: MergedState = .idle

    init(notchSizeInWindow: CGSize) {
        super.init(frame: .zero)
        wantsLayer = true
        layer = CALayer()
        layer?.masksToBounds = false
        setupSublayers(notchSize: notchSizeInWindow)
        applyState(.idle, animated: false)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Subscribe to a MergedState publisher (e.g. StateStore.$currentState).
    func bind<P: Publisher>(_ publisher: P) where P.Output == MergedState, P.Failure == Never {
        publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.applyState(state, animated: true) }
            .store(in: &subs)
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        layoutSublayers()
    }

    private func setupSublayers(notchSize: CGSize) {
        // The notch occupies the top-center of the window. The line and glow
        // hug the *bottom edge* of that notch.
        layer?.addSublayer(outerGlowLayer)
        layer?.addSublayer(glowLayer)
        layer?.addSublayer(lineLayer)

        outerGlowLayer.shadowOpacity = 0.4
        outerGlowLayer.shadowRadius = 32
        outerGlowLayer.shadowOffset = .zero
        outerGlowLayer.backgroundColor = NSColor.clear.cgColor

        glowLayer.shadowOpacity = 0.85
        glowLayer.shadowRadius = 18
        glowLayer.shadowOffset = .zero
        glowLayer.backgroundColor = NSColor.clear.cgColor

        lineLayer.cornerRadius = 1
    }

    private func layoutSublayers() {
        let b = bounds
        // Notch rect, centered horizontally, at the top of the window.
        // The window frame was inset by `glowPadding` on all sides, so the
        // notch sits `glowPadding` from the top.
        let pad: CGFloat = 40
        let notchWidth = b.width - pad * 2
        let notchHeight: CGFloat = 32
        let notchRect = CGRect(
            x: pad,
            y: b.height - pad - notchHeight,
            width: notchWidth,
            height: notchHeight
        )

        // Line: 1pt strip at the BOTTOM edge of the notch.
        lineLayer.frame = CGRect(
            x: notchRect.minX + 6,
            y: notchRect.minY,
            width: notchRect.width - 12,
            height: 1.5
        )

        // Glow source: the shape of the line, but with bigger shadow radii.
        for shadow in [glowLayer, outerGlowLayer] {
            shadow.frame = lineLayer.frame
            shadow.shadowPath = CGPath(rect: shadow.bounds, transform: nil)
        }
    }

    // MARK: - State

    private func applyState(_ state: MergedState, animated: Bool) {
        let newColor = Self.cgColor(for: state)
        let newOpacity: Float = (state == .idle) ? 0.15 : 1.0
        let previousState = currentState
        currentState = state

        // Reduce-motion users get an instant swap.
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let shouldPulse = animated && !reduceMotion && state != previousState

        if !shouldPulse {
            CATransaction.begin()
            CATransaction.setAnimationDuration(animated ? 0.05 : 0)
            glowLayer.shadowColor = newColor
            outerGlowLayer.shadowColor = newColor
            lineLayer.backgroundColor = newColor
            glowLayer.opacity = newOpacity
            outerGlowLayer.opacity = newOpacity
            lineLayer.opacity = newOpacity
            CATransaction.commit()
            return
        }

        // Ding pulse: 0ms current → 150ms white → 350ms new color.
        let whiteColor = NSColor.white.cgColor
        for layer in [glowLayer, outerGlowLayer, lineLayer] {
            let key = "ding-pulse"
            layer.removeAnimation(forKey: key)

            let property = (layer === lineLayer) ? "backgroundColor" : "shadowColor"
            let anim = CAKeyframeAnimation(keyPath: property)
            anim.duration = 0.35
            anim.values = [
                layer.presentation()?.value(forKeyPath: property) as Any,
                whiteColor,
                newColor as Any,
            ]
            anim.keyTimes = [0.0, 0.42, 1.0]
            anim.timingFunctions = [
                CAMediaTimingFunction(name: .easeOut),
                CAMediaTimingFunction(name: .easeIn),
            ]
            anim.isRemovedOnCompletion = true
            layer.add(anim, forKey: key)
            layer.setValue(newColor, forKeyPath: property)
        }

        // Opacity transitions in parallel — fade-in of the new color over 350ms.
        let opacityAnim = CABasicAnimation(keyPath: "opacity")
        opacityAnim.duration = 0.35
        opacityAnim.fromValue = max(glowLayer.opacity, 0.5)
        opacityAnim.toValue = newOpacity
        for layer in [glowLayer, outerGlowLayer, lineLayer] {
            layer.opacity = newOpacity
            layer.add(opacityAnim, forKey: "ding-opacity")
        }
    }

    /// Force the view to a specific state without going through the publisher.
    /// Used only for the startup self-test flash.
    func previewState(_ state: MergedState) {
        applyState(state, animated: true)
    }

    static func cgColor(for state: MergedState) -> CGColor {
        switch state {
        case .working:
            return NSColor(red: 95/255.0, green: 207/255.0, blue: 122/255.0, alpha: 1).cgColor
        case .waiting:
            return NSColor(red: 245/255.0, green: 166/255.0, blue: 35/255.0, alpha: 1).cgColor
        case .idle:
            return NSColor(white: 0.85, alpha: 1).cgColor
        }
    }
}
