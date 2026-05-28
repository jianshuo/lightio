import AppKit
import CCLightCore

/// Per-state chimes for state transitions. By design, only `.waiting` and
/// `.attention` chime — `.working` transitions are user-initiated (you just
/// typed a prompt) so chiming on them is noise. `.idle` is a slow fade with
/// no urgency, also silent.
enum SoundPlayer {
    private static let prefKey = "cclight.soundsEnabled"

    /// Whether chimes play. UserDefaults-backed; absent key → enabled (so
    /// first-launch users hear the feature). Writes propagate immediately
    /// to the next transition.
    static var enabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: prefKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: prefKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: prefKey) }
    }

    /// Play the chime for a state transition, if appropriate.
    /// No-op when sounds are disabled, when the state didn't actually change,
    /// or when the new state has no chime (`.working` / `.idle`).
    static func play(transition newState: MergedState, from oldState: MergedState) {
        guard enabled, newState != oldState else { return }
        let soundName: NSSound.Name?
        switch newState {
        case .waiting:   soundName = NSSound.Name("Pop")    // gentle "your turn"
        case .attention: soundName = NSSound.Name("Glass")  // attention-grabbing
        case .working, .idle: soundName = nil
        }
        guard let name = soundName else { return }
        NSSound(named: name)?.play()
    }
}
