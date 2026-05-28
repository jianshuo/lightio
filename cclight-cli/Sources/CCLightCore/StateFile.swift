import Foundation

/// In-memory representation of `~/.cclight/state.json`.
public struct StateSnapshot: Codable, Equatable, Sendable {
    public var version: Int
    public var sessions: [String: SessionEntry]

    public struct SessionEntry: Codable, Equatable, Sendable {
        public var state: SessionState
        public var ts: Int
        public var cwd: String?
        public var reason: HookReason?

        public init(state: SessionState, ts: Int, cwd: String?, reason: HookReason? = nil) {
            self.state = state
            self.ts = ts
            self.cwd = cwd
            self.reason = reason
        }
    }

    public init(version: Int = 1, sessions: [String: SessionEntry] = [:]) {
        self.version = version
        self.sessions = sessions
    }
}

public enum StateFile {
    /// Read state.json. Missing file → empty snapshot. Malformed → empty + log to stderr.
    public static func read() throws -> StateSnapshot {
        let url = Paths.stateFile
        guard FileManager.default.fileExists(atPath: url.path) else {
            return StateSnapshot()
        }
        do {
            let data = try Data(contentsOf: url)
            if data.isEmpty { return StateSnapshot() }
            return try JSONDecoder().decode(StateSnapshot.self, from: data)
        } catch {
            FileHandle.standardError.write(Data("cclight: malformed state.json: \(error)\n".utf8))
            return StateSnapshot()
        }
    }

    /// Atomic write: write to `state.json.tmp.<pid>` then rename(2) over state.json.
    public static func write(_ snapshot: StateSnapshot) throws {
        try FileManager.default.createDirectory(
            at: Paths.stateDir, withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)

        let tmpURL = Paths.stateFile.appendingPathExtension("tmp.\(ProcessInfo.processInfo.processIdentifier)")
        try data.write(to: tmpURL)
        // `replaceItemAt` does the atomic rename; if the destination doesn't
        // exist it creates it.
        _ = try FileManager.default.replaceItemAt(Paths.stateFile, withItemAt: tmpURL)
    }

    /// Read → mutate → write, in one shot. Note: not safe across multiple
    /// concurrent writers from different processes; the CLI writes are
    /// fast (<10ms) and Claude Code hook bursts are sequential per-session,
    /// so the race window is acceptable for V1.
    public static func update(_ mutate: (inout StateSnapshot) throws -> Void) throws {
        var snapshot = try read()
        try mutate(&snapshot)
        try write(snapshot)
    }
}
