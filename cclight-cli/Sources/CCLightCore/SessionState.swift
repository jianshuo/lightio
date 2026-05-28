import Foundation

/// Per-session state written by the CLI to state.json.
/// IDLE is intentionally absent here — it's a presentation-layer concept
/// derived from a timer in the app, never serialized.
public enum SessionState: String, Codable, Sendable, Equatable {
    case working
    case waiting
}

/// Why the most recent state change fired, threaded from the Claude Code hook
/// event name. Lets the overlay distinguish e.g. `Stop` (Claude just finished,
/// no action needed) from `Notification` (Claude paused for your input).
public enum HookReason: String, Codable, Sendable, Equatable {
    case sessionStart   = "session-start"
    case userPrompt     = "user-prompt"
    case stop
    case notification
}

/// The visible overlay state, derived from the union of all session states.
public enum MergedState: String, Sendable, Equatable {
    case working
    case waiting
    case attention
    case idle

    public var priority: Int {
        switch self {
        case .attention: return 3
        case .working:   return 2
        case .waiting:   return 1
        case .idle:      return 0
        }
    }

    /// Map a single session entry to its presentation state. `waiting +
    /// reason=notification` is promoted to `.attention` so the overlay can
    /// signal "Claude needs you" separately from a quiet "done" state.
    public static func mergedState(for entry: StateSnapshot.SessionEntry) -> MergedState {
        if entry.state == .working { return .working }
        if entry.reason == .notification { return .attention }
        return .waiting
    }

    /// Highest-priority state across the given sessions; empty → .idle.
    public static func merge(_ states: [SessionState]) -> MergedState {
        states.reduce(MergedState.idle) { acc, s in
            let candidate: MergedState = (s == .working) ? .working : .waiting
            return candidate.priority > acc.priority ? candidate : acc
        }
    }

    /// Entry-aware merge: considers `reason` so notifications surface as
    /// `.attention` even when other sessions are quiet.
    public static func merge(entries: [StateSnapshot.SessionEntry]) -> MergedState {
        entries.reduce(MergedState.idle) { acc, entry in
            let candidate = mergedState(for: entry)
            return candidate.priority > acc.priority ? candidate : acc
        }
    }

    /// Convenience: derive the merged state directly from a state.json snapshot.
    public static func merge(snapshot: StateSnapshot) -> MergedState {
        merge(entries: Array(snapshot.sessions.values))
    }
}
