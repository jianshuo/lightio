import Foundation

public enum HookInstaller {
    /// Marker we embed in each command string so uninstall can find our hooks.
    public static let marker = "vibelight"

    /// Hook events vibelight installs.
    static let hookEvents: [(event: String, args: String)] = [
        ("SessionStart",     "set waiting"),
        ("UserPromptSubmit", "set working"),
        ("Stop",             "set waiting"),
        ("Notification",     "set waiting"),
        ("SessionEnd",       "clear"),
    ]

    /// Install vibelight hooks into the given settings.json (creating the file
    /// if missing). Existing non-vibelight hooks are preserved. A one-time
    /// backup is written to `<file>.vibelight-backup`.
    public static func install(settingsURL: URL, binaryPath: String) throws {
        try writeBackupIfNeeded(settingsURL: settingsURL)

        var json = try readSettings(settingsURL)
        var hooks = (json["hooks"] as? [String: Any]) ?? [:]

        for (event, args) in hookEvents {
            var entries = (hooks[event] as? [[String: Any]]) ?? []
            entries.removeAll { isVibelightEntry($0) }
            entries.append([
                "hooks": [[
                    "type": "command",
                    "command": "\(binaryPath) \(args)",
                ]]
            ])
            hooks[event] = entries
        }

        json["hooks"] = hooks
        try writeSettings(json, to: settingsURL)
    }

    /// Remove vibelight hooks. Non-vibelight hooks are preserved.
    public static func uninstall(settingsURL: URL) throws {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return }
        var json = try readSettings(settingsURL)
        guard var hooks = json["hooks"] as? [String: Any] else { return }

        for (event, _) in hookEvents {
            guard var entries = hooks[event] as? [[String: Any]] else { continue }
            entries.removeAll { isVibelightEntry($0) }
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

    private static func isVibelightEntry(_ entry: [String: Any]) -> Bool {
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
        let backup = settingsURL.appendingPathExtension("vibelight-backup")
        guard FileManager.default.fileExists(atPath: settingsURL.path),
              !FileManager.default.fileExists(atPath: backup.path)
        else { return }
        try FileManager.default.copyItem(at: settingsURL, to: backup)
    }
}
