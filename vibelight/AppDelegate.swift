import AppKit
import SwiftUI
import VibelightCore

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
            NSLog("vibelight: screen frame=\(screen.frame), safeAreaInsets.top=\(insets.top), aux.left=\(String(describing: screen.auxiliaryTopLeftArea)), aux.right=\(String(describing: screen.auxiliaryTopRightArea))")
            if let notchRect = NotchGeometry.notchRect(for: screen) {
                NSLog("vibelight: notchRect=\(notchRect)")
                let frame = NotchGeometry.overlayWindowFrame(notchRect: notchRect, glowPadding: 90)
                overlayWindow = NotchOverlayWindow(contentRect: frame)
                overlayView = NotchOverlayView(notchSize: notchRect.size)
                overlayWindow.contentView = overlayView
                overlayWindow.orderFrontRegardless()
                overlayView.bindSessions(store.$orderedSessionStates)
            } else {
                NSLog("vibelight: no notch detected; overlay disabled")
            }
        } else {
            NSLog("vibelight: NSScreen.main is nil")
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
        if !FirstRun.isSymlinkInstalled() {
            let alert = NSAlert()
            alert.messageText = "Install Vibe Light CLI?"
            alert.informativeText = """
            需要把 CLI 安装到 /usr/local/bin/vibelight，
            这一步需要管理员密码（一次性）。
            """
            alert.addButton(withTitle: "Install")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn {
                FirstRun.installSymlinkInteractively()
            }
        }
        if FirstRun.claudeSettingsExists() {
            let alreadyHasVibelight = (try? Data(contentsOf: Paths.claudeSettingsFile))
                .flatMap { String(data: $0, encoding: .utf8) }?
                .contains(HookInstaller.marker) == true
            if !alreadyHasVibelight {
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
            alert.informativeText = "Vibe Light hooks added to ~/.claude/settings.json"
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
