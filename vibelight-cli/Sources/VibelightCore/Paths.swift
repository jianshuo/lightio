import Foundation

/// Resolves the paths vibelight reads/writes. Honors `VIBELIGHT_STATE_DIR`
/// for tests so we never touch the user's real `~/.vibelight`.
public enum Paths {
    public static var stateDir: URL {
        if let override = ProcessInfo.processInfo.environment["VIBELIGHT_STATE_DIR"] {
            return URL(fileURLWithPath: override)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".vibelight", isDirectory: true)
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
