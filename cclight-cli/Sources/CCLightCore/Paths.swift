import Foundation

/// Resolves the paths cclight reads/writes. Honors `VIBELIGHT_STATE_DIR`
/// for tests so we never touch the user's real `~/.cclight`.
public enum Paths {
    /// App Group identifier shared by the sandboxed app and the sandboxed CLI.
    /// Both binaries get redirected by the OS to the same Group Container
    /// at `~/Library/Group Containers/<id>/`.
    public static let appGroupID = "group.com.wangjianshuo.lightio"

    public static var stateDir: URL {
        if let override = ProcessInfo.processInfo.environment["VIBELIGHT_STATE_DIR"] {
            return URL(fileURLWithPath: override)
        }
        // Preferred path: ask the OS for the App Group container. Works inside
        // both the app's sandbox and the CLI's sandbox (when both have the
        // matching app-group entitlement).
        if let group = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) {
            return group.appendingPathComponent("Library/Application Support", isDirectory: true)
        }
        // Fallback for unsandboxed invocations (dev builds, manual swift run).
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library/Group Containers/\(appGroupID)/Library/Application Support",
                                   isDirectory: true)
    }

    public static var stateFile: URL {
        stateDir.appendingPathComponent("state.json")
    }

    public static var claudeSettingsFile: URL {
        if let override = ProcessInfo.processInfo.environment["VIBELIGHT_CLAUDE_DIR"] {
            return URL(fileURLWithPath: override).appendingPathComponent("settings.json")
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".claude/settings.json")
    }
}
