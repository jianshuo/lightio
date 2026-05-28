import Foundation

public enum HookInstaller {
    /// Marker we embed in each command string so uninstall can find our hooks.
    public static let marker = "cclight"

    /// Hook events cclight installs. Each `set` call tags itself with
    /// `--reason <event>` so the overlay can tell *why* a state changed —
    /// e.g. `waiting/notification` (Claude paused for input) renders as
    /// "attention" while `waiting/stop` is a quiet "done".
    static let hookEvents: [(event: String, args: String)] = [
        ("SessionStart",     "set waiting --reason \(HookReason.sessionStart.rawValue)"),
        ("UserPromptSubmit", "set working --reason \(HookReason.userPrompt.rawValue)"),
        ("Stop",             "set waiting --reason \(HookReason.stop.rawValue)"),
        ("Notification",     "set waiting --reason \(HookReason.notification.rawValue)"),
        ("SessionEnd",       "clear"),
    ]

    /// Install cclight hooks into the given settings.json (creating the file
    /// if missing). Existing non-cclight hooks are preserved. A one-time
    /// backup is written to `<file>.cclight-backup`.
    public static func install(settingsURL: URL, binaryPath: String) throws {
        try writeBackupIfNeeded(settingsURL: settingsURL)

        var json = try readSettings(settingsURL)
        var hooks = (json["hooks"] as? [String: Any]) ?? [:]

        for (event, args) in hookEvents {
            var entries = (hooks[event] as? [[String: Any]]) ?? []
            entries.removeAll { isCCLightEntry($0) }
            entries.append([
                "hooks": [[
                    "type": "command",
                    "command": wrappedCommand(binaryPath: binaryPath, args: args),
                ]]
            ])
            hooks[event] = entries
        }

        json["hooks"] = hooks
        try writeSettings(json, to: settingsURL)
    }

    /// Remove cclight hooks. Non-cclight hooks are preserved.
    public static func uninstall(settingsURL: URL) throws {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return }
        var json = try readSettings(settingsURL)
        guard var hooks = json["hooks"] as? [String: Any] else { return }

        for (event, _) in hookEvents {
            guard var entries = hooks[event] as? [[String: Any]] else { continue }
            entries.removeAll { isCCLightEntry($0) }
            if entries.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = entries
            }
        }
        json["hooks"] = hooks
        try writeSettings(json, to: settingsURL)
    }

    // MARK: - Helpers

    /// Wrap the binary call so a missing or broken binary never fails the
    /// Claude Code session. Pattern: existence check + run + `exit 0`.
    /// Mirrors vibe-island's defensive hook shape.
    static func wrappedCommand(binaryPath: String, args: String) -> String {
        let escaped = binaryPath.replacingOccurrences(of: "'", with: "'\\''")
        return "/bin/sh -c '[ -x \"\(escaped)\" ] && \"\(escaped)\" \(args); exit 0'"
    }

    private static func isCCLightEntry(_ entry: [String: Any]) -> Bool {
        guard let inner = entry["hooks"] as? [[String: Any]] else { return false }
        return inner.contains { ($0["command"] as? String)?.contains(marker) == true }
    }

    private static func readSettings(_ url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        if data.isEmpty { return [:] }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private static func writeSettings(_ json: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        )
        let tmp = url.appendingPathExtension("tmp.\(ProcessInfo.processInfo.processIdentifier)")
        try data.write(to: tmp)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
    }

    private static func writeBackupIfNeeded(settingsURL: URL) throws {
        let backup = settingsURL.appendingPathExtension("cclight-backup")
        guard FileManager.default.fileExists(atPath: settingsURL.path),
              !FileManager.default.fileExists(atPath: backup.path)
        else { return }
        try FileManager.default.copyItem(at: settingsURL, to: backup)
    }
}
