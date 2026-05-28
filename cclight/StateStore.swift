import Foundation
import Darwin
import Combine
import CoreServices
import CCLightCore

/// Watches `~/.cclight/state.json` and publishes the current merged state
/// to subscribers. Owns the 5-minute idle timer.
final class StateStore: ObservableObject {
    /// Merged state across all sessions (priority working > waiting > idle).
    /// MenuBarController uses this for the status dot.
    @Published private(set) var currentState: MergedState = .idle

    /// Active session count (for menu display).
    @Published private(set) var sessionCount: Int = 0

    /// Per-session presentation states (capped at 4 most-recent), sorted by
    /// session_id for stable ordering. Each entry has already been folded with
    /// its `reason` so e.g. `waiting/notification` arrives as `.attention`.
    /// NotchOverlayView and the menu both render from this.
    @Published private(set) var orderedSessionStates: [MergedState] = []

    /// Session IDs parallel to orderedSessionStates, for menu display.
    @Published private(set) var orderedSessionIds: [String] = []

    /// Session working directories parallel to orderedSessionStates. Menu
    /// renders the cwd basename as the session's display name.
    @Published private(set) var orderedSessionCwds: [String?] = []

    private var stream: FSEventStreamRef?
    private var idleTimer: DispatchSourceTimer?
    private let idleTimeout: TimeInterval

    init(idleTimeout: TimeInterval = 5 * 60) {
        self.idleTimeout = idleTimeout
    }

    deinit { stop() }

    func start() {
        // Ensure the directory exists so FSEvents has something to watch.
        try? FileManager.default.createDirectory(
            at: Paths.stateDir, withIntermediateDirectories: true
        )

        reload()  // initial read

        let watched: NSArray = [Paths.stateDir.path]
        var ctx = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { (_, info, _, _, _, _) in
            guard let info = info else { return }
            let store = Unmanaged<StateStore>.fromOpaque(info).takeUnretainedValue()
            DispatchQueue.main.async { store.reload() }
        }
        let flags: UInt32 =
            UInt32(kFSEventStreamCreateFlagFileEvents) |
            UInt32(kFSEventStreamCreateFlagNoDefer)
        let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &ctx,
            watched as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.05,  // 50 ms latency
            flags
        )
        guard let stream = stream else { return }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    func stop() {
        if let stream = stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        idleTimer?.cancel()
        idleTimer = nil
    }

    /// Re-read state.json, recompute merged state, manage idle timer.
    private func reload() {
        let rawSnapshot = (try? StateFile.read()) ?? StateSnapshot()

        // Liveness: for entries with a pid, check `kill(pid, 0)`. Alive →
        // keep regardless of age (long-idle sessions stay visible). Dead →
        // drop instantly (covers `kill -9`, closed terminal, crash). For
        // legacy/manual entries that have no pid, fall back to a short
        // 60-second ts window so test-injected entries don't pile up.
        let manualFallback: TimeInterval = 60
        let cutoff = Int(Date().timeIntervalSince1970 - manualFallback)
        let liveSessions = rawSnapshot.sessions.filter { _, entry in
            if let pid = entry.pid { return Self.processAlive(pid: pid) }
            return entry.ts >= cutoff
        }
        let snapshot = StateSnapshot(version: rawSnapshot.version, sessions: liveSessions)
        let pruned = rawSnapshot.sessions.count - liveSessions.count

        let merged = MergedState.merge(snapshot: snapshot)
        NSLog("cclight: reload — \(snapshot.sessions.count) session(s) (pruned \(pruned)), merged=\(merged)")
        // Cap at 4 most-recently-active sessions for display.
        let topSessions = snapshot.sessions
            .sorted { $0.value.ts > $1.value.ts }  // newest first
            .prefix(4)
        sessionCount = topSessions.count
        let sortedTop = topSessions.sorted { $0.key < $1.key }
        orderedSessionStates = sortedTop.map { MergedState.mergedState(for: $0.value) }
        orderedSessionIds = sortedTop.map { $0.key }
        orderedSessionCwds = sortedTop.map { $0.value.cwd }

        // Cancel any running idle timer; we'll restart if needed.
        idleTimer?.cancel()
        idleTimer = nil

        switch merged {
        case .working:
            currentState = .working
        case .attention:
            // No idle timer: a "Claude needs you" signal should persist until
            // the user actually responds (next hook event clears it) or the
            // session entry ages out (>10min) via the prune above.
            currentState = .attention
        case .waiting:
            currentState = .waiting
            startIdleTimer()
        case .idle:
            currentState = .idle
        }
    }

    /// `kill(pid, 0)` doesn't send a signal — it just runs the permission
    /// check, so success means "this PID exists and we could signal it" and
    /// `ESRCH` means "no such process". `EPERM` (exists but not ours) also
    /// counts as alive — Claude Code spawns the hook as our own child so we
    /// shouldn't see EPERM in practice, but treating it as alive is the
    /// safe default.
    private static func processAlive(pid: Int) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid_t(pid), 0) == 0 { return true }
        return errno == EPERM
    }

    private func startIdleTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + idleTimeout)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            // Only demote from waiting → idle. Working/attention should never
            // be silently downgraded by a timer.
            if self.currentState == .waiting {
                self.currentState = .idle
            }
            self.idleTimer = nil
        }
        idleTimer = timer
        timer.resume()
    }
}
