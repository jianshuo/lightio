import AppKit
import SwiftUI
import CCLightCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: StateStore!
    private var overlayWindow: NotchOverlayWindow!
    private var overlayView: NotchOverlayView!
    private var menuBar: MenuBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = StateStore()
        store.start()

        if let screen = NSScreen.main {
            let insets = screen.safeAreaInsets
            NSLog("cclight: screen frame=\(screen.frame), safeAreaInsets.top=\(insets.top), aux.left=\(String(describing: screen.auxiliaryTopLeftArea)), aux.right=\(String(describing: screen.auxiliaryTopRightArea))")
            if let notchRect = NotchGeometry.notchRect(for: screen) {
                NSLog("cclight: notchRect=\(notchRect)")
                let frame = NotchGeometry.overlayWindowFrame(notchRect: notchRect, glowPadding: 90)
                overlayWindow = NotchOverlayWindow(contentRect: frame)
                overlayView = NotchOverlayView(notchSize: notchRect.size)
                overlayWindow.contentView = overlayView
                overlayWindow.orderFrontRegardless()
                overlayView.bindSessions(store.$orderedSessionStates)
            } else {
                NSLog("cclight: no notch detected; overlay disabled")
            }
        } else {
            NSLog("cclight: NSScreen.main is nil")
        }

        menuBar = MenuBarController(store: store)
        menuBar.isLaunchAtLoginOn = { FirstRun.isLaunchAtLoginEnabled }
        menuBar.onInstallHooks = { [weak self] in self?.handleInstallHooks() }
        menuBar.onUninstallHooks = { [weak self] in self?.handleUninstallHooks() }
        menuBar.onToggleLaunchAtLogin = {
            FirstRun.setLaunchAtLogin(!FirstRun.isLaunchAtLoginEnabled)
        }

        DispatchQueue.main.async { [weak self] in self?.runFirstRunIfNeeded() }

        flashSelfTest()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store?.stop()
    }

    private func runFirstRunIfNeeded() {
        NSApp.activate(ignoringOtherApps: true)
        if FirstRun.claudeSettingsExists() {
            // Check whether cclight hooks are already present. We try the
            // bookmark-based path first; if no bookmark yet we do a best-effort
            // read from the standard location (may be denied in sandbox — in
            // that case we conservatively treat it as not-yet-installed and let
            // the user decide via the offer dialog, which will trigger the open
            // panel and grant access).
            let alreadyHasCCLight: Bool
            if let claudeDirURL = FirstRun.resolveClaudeAccess(),
               claudeDirURL.startAccessingSecurityScopedResource() {
                defer { claudeDirURL.stopAccessingSecurityScopedResource() }
                let settingsURL = claudeDirURL.appendingPathComponent("settings.json")
                alreadyHasCCLight = (try? Data(contentsOf: settingsURL))
                    .flatMap { String(data: $0, encoding: .utf8) }?
                    .contains(HookInstaller.marker) == true
            } else {
                alreadyHasCCLight = (try? Data(contentsOf: Paths.claudeSettingsFile))
                    .flatMap { String(data: $0, encoding: .utf8) }?
                    .contains(HookInstaller.marker) == true
            }
            if !alreadyHasCCLight {
                FirstRun.offerHooksInstall()
            }
        }
        if !FirstRun.isLaunchAtLoginEnabled {
            FirstRun.setLaunchAtLogin(true)
        }
    }

    private func handleInstallHooks() {
        if FirstRun.installHooks() {
            let alert = NSAlert()
            alert.messageText = "Hooks installed"
            alert.informativeText = "CCLight hooks added to ~/.claude/settings.json"
            alert.runModal()
        } else {
            let alert = NSAlert()
            alert.messageText = "Could not install hooks"
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    private func handleUninstallHooks() {
        _ = FirstRun.uninstallHooks()
    }

    private func flashSelfTest() {
        guard let overlayView = overlayView else { return }
        overlayView.previewState(.working)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.overlayView?.previewState(self?.store.currentState ?? .idle)
        }
    }
}
