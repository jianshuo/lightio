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

        if let screen = NSScreen.main,
           let notchRect = NotchGeometry.notchRect(for: screen) {
            let frame = NotchGeometry.overlayWindowFrame(notchRect: notchRect, glowPadding: 40)
            overlayWindow = NotchOverlayWindow(contentRect: frame)
            overlayView = NotchOverlayView(notchSizeInWindow: notchRect.size)
            overlayWindow.contentView = overlayView
            overlayWindow.orderFrontRegardless()
            overlayView.bind(store.$currentState)
        } else {
            NSLog("vibelight: no notch detected; overlay disabled")
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
        if !FirstRun.isSymlinkInstalled() {
            let alert = NSAlert()
            alert.messageText = "Install vibelight CLI?"
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
            alert.informativeText = "vibelight hooks added to ~/.claude/settings.json"
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
