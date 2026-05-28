import Foundation

/// Per-session state written by the CLI to state.json.
/// IDLE is intentionally absent here — it's a presentation-layer concept
/// derived from a timer in the app, never serialized.
public enum SessionState: String, Codable, Sendable, Equatable {
    case working
    case waiting
}

/// The visible overlay state, derived from the union of all session states.
public enum MergedState: String, Sendable, Equatable {
    case working
    case waiting
    case idle

    public var priority: Int {
        switch self {
        case .working: return 2
        case .waiting: return 1
        case .idle:    return 0
        }
    }

    /// Highest-priority state across the given sessions; empty → .idle.
    public static func merge(_ states: [SessionState]) -> MergedState {
        states.reduce(MergedState.idle) { acc, s in
            let candidate: MergedState = (s == .working) ? .working : .waiting
            return candidate.priority > acc.priority ? candidate : acc
        }
    }
}
