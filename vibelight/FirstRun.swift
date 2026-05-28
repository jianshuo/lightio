import AppKit
import ServiceManagement
import VibelightCore

/// Handles one-time install steps on first launch and exposes "Install Hooks"
/// as a re-runnable action.
enum FirstRun {
    static let symlinkPath = "/usr/local/bin/vibelight"

    /// Path to the CLI bundled inside this .app.
    static var bundledCLIPath: String {
        Bundle.main.resourcePath.map { "\($0)/vibelight" }
            ?? "/Applications/VibeLight.app/Contents/Resources/vibelight"
    }

    // MARK: - Symlink

    static func isSymlinkInstalled() -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: symlinkPath) else { return false }
        // Verify it's a symlink pointing to *our* bundled CLI
        let attrs = try? fm.attributesOfItem(atPath: symlinkPath)
        if attrs?[.type] as? FileAttributeType == .typeSymbolicLink {
            let dest = try? fm.destinationOfSymbolicLink(atPath: symlinkPath)
            return dest == bundledCLIPath
        }
        return false
    }

    /// Asks for admin password and creates the symlink. Returns true on success.
    @discardableResult
    static func installSymlinkInteractively() -> Bool {
        let escaped = bundledCLIPath.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        do shell script "mkdir -p /usr/local/bin && ln -sf \\"\(escaped)\\" /usr/local/bin/vibelight" with administrator privileges
        """
        var errorInfo: NSDictionary?
        let runner = NSAppleScript(source: script)
        _ = runner?.executeAndReturnError(&errorInfo)
        if let error = errorInfo {
            NSLog("vibelight symlink install failed: \(error)")
            return false
        }
        return isSymlinkInstalled()
    }

    // MARK: - Hooks dialog

    static func claudeSettingsExists() -> Bool {
        FileManager.default.fileExists(atPath: Paths.claudeSettingsFile.path)
    }

    /// Shows a modal dialog asking the user to install hooks. Returns whether
    /// the user agreed *and* the install succeeded.
    @discardableResult
    static func offerHooksInstall() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Install Claude Code Hooks?"
        alert.informativeText = """
        检测到 Claude Code (~/.claude/settings.json)。
        是否将 vibelight 的 hooks 加入其中？
        原文件会备份到 settings.json.vibelight-backup。
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Not Now")
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return false }
        return installHooks()
    }

    /// Patch ~/.claude/settings.json. Returns success.
    @discardableResult
    static func installHooks() -> Bool {
        do {
            try HookInstaller.install(
                settingsURL: Paths.claudeSettingsFile,
                binaryPath: symlinkPath
            )
            return true
        } catch {
            NSLog("vibelight installHooks failed: \(error)")
            return false
        }
    }

    @discardableResult
    static func uninstallHooks() -> Bool {
        do {
            try HookInstaller.uninstall(settingsURL: Paths.claudeSettingsFile)
            return true
        } catch {
            NSLog("vibelight uninstallHooks failed: \(error)")
            return false
        }
    }

    // MARK: - Launch at Login

    static var isLaunchAtLoginEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    static func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("vibelight setLaunchAtLogin failed: \(error)")
            }
        }
    }
}
