import Foundation

/// Resolves the paths cclight reads/writes. Honors `VIBELIGHT_STATE_DIR`
/// for tests so we never touch the user's real `~/.cclight`.
public enum Paths {
    public static var stateDir: URL {
        if let override = ProcessInfo.processInfo.environment["VIBELIGHT_STATE_DIR"] {
            return URL(fileURLWithPath: override)
        }
        // Hard-code the container path so the unsandboxed CLI and the sandboxed
        // app read/write the same file. Inside the sandbox the app's
        // FileManager automatically redirects .applicationSupportDirectory to
        // this same container path.
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Containers", isDirectory: true)
            .appendingPathComponent("com.wangjianshuo.cclight", isDirectory: true)
            .appendingPathComponent("Data", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
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
