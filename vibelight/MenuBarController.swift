import AppKit
import Combine
import VibelightCore

/// Owns the menu-bar status item: a tinted dot whose color tracks the merged
/// state, and a menu with the install/uninstall hooks actions.
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private weak var store: StateStore?
    private var subs: Set<AnyCancellable> = []

    var onInstallHooks: (() -> Void)?
    var onUninstallHooks: (() -> Void)?
    var onToggleLaunchAtLogin: (() -> Void)?
    var isLaunchAtLoginOn: () -> Bool = { false }

    init(store: StateStore) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.store = store
        super.init()

        setupButtonIcon(state: .idle)
        setupMenu()

        store.$currentState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.setupButtonIcon(state: state) }
            .store(in: &subs)

        store.$sessionCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshMenu() }
            .store(in: &subs)
    }

    private func setupButtonIcon(state: MergedState) {
        guard let button = statusItem.button else { return }
        let size = NSSize(width: 14, height: 14)
        let image = NSImage(size: size, flipped: false) { rect in
            let dotRect = NSRect(x: 3, y: 3, width: 8, height: 8)
            switch state {
            case .working: NSColor(red: 95/255, green: 207/255, blue: 122/255, alpha: 1).setFill()
            case .waiting: NSColor(red: 245/255, green: 166/255, blue: 35/255, alpha: 1).setFill()
            case .idle:    NSColor(white: 0.6, alpha: 1).setFill()
            }
            NSBezierPath(ovalIn: dotRect).fill()
            return true
        }
        image.isTemplate = false
        button.image = image
    }

    private func setupMenu() {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        refreshMenu()
    }

    private func refreshMenu() {
        guard let menu = statusItem.menu else { return }
        menu.removeAllItems()

        let stateLine = NSMenuItem(
            title: stateMenuTitle(),
            action: nil, keyEquivalent: ""
        )
        stateLine.isEnabled = false
        menu.addItem(stateLine)
        menu.addItem(.separator())

        let installItem = NSMenuItem(
            title: "Install Claude Code Hooks",
            action: #selector(installHooks),
            keyEquivalent: ""
        )
        installItem.target = self
        menu.addItem(installItem)

        let uninstallItem = NSMenuItem(
            title: "Uninstall Claude Code Hooks",
            action: #selector(uninstallHooks),
            keyEquivalent: ""
        )
        uninstallItem.target = self
        menu.addItem(uninstallItem)

        menu.addItem(.separator())

        let launchItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchItem.target = self
        launchItem.state = isLaunchAtLoginOn() ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(.separator())

        let about = NSMenuItem(title: "About vibelight", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func stateMenuTitle() -> String {
        guard let store = store else { return "vibelight" }
        let stateLabel: String
        switch store.currentState {
        case .working: stateLabel = "WORKING"
        case .waiting: stateLabel = "WAITING"
        case .idle:    stateLabel = "IDLE"
        }
        return "状态: \(stateLabel) (\(store.sessionCount) session\(store.sessionCount == 1 ? "" : "s"))"
    }

    // MARK: - Actions

    @objc private func installHooks() { onInstallHooks?() }
    @objc private func uninstallHooks() { onUninstallHooks?() }
    @objc private func toggleLaunchAtLogin() { onToggleLaunchAtLogin?() }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) { refreshMenu() }
}
