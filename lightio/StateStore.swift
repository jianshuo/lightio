import Foundation
import Combine
import CoreServices
import LightioCore

/// Watches `~/.lightio/state.json` and publishes the current merged state
/// to subscribers. Owns the 5-minute idle timer.
final class StateStore: ObservableObject {
    /// Merged state across all sessions (priority working > waiting > idle).
    /// MenuBarController uses this for the status dot.
    @Published private(set) var currentState: MergedState = .idle

    /// Active session count (for menu display).
    @Published private(set) var sessionCount: Int = 0

    /// Per-session states (capped at 4 most-recent), sorted by session_id for
    /// stable ordering. NotchOverlayView uses this to render one halo per session.
    @Published private(set) var orderedSessionStates: [SessionState] = []

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

        // Prune stale sessions: anything not updated in the last 10 minutes
        // is treated as dead (covers Claude Code sessions killed without
        // firing SessionEnd).
        let staleAfter: TimeInterval = 10 * 60
        let cutoff = Int(Date().timeIntervalSince1970 - staleAfter)
        let liveSessions = rawSnapshot.sessions.filter { $0.value.ts >= cutoff }
        let snapshot = StateSnapshot(version: rawSnapshot.version, sessions: liveSessions)
        let pruned = rawSnapshot.sessions.count - liveSessions.count

        let merged = MergedState.merge(snapshot: snapshot)
        NSLog("lightio: reload — \(snapshot.sessions.count) session(s) (pruned \(pruned)), merged=\(merged)")
        // Cap at 4 most-recently-active sessions for display.
        let topSessions = snapshot.sessions
            .sorted { $0.value.ts > $1.value.ts }  // newest first
            .prefix(4)
        sessionCount = topSessions.count
        let sortedTop = topSessions.sorted { $0.key < $1.key }
        orderedSessionStates = sortedTop.map { $0.value.state }
        orderedSessionIds = sortedTop.map { $0.key }
        orderedSessionCwds = sortedTop.map { $0.value.cwd }

        // Cancel any running idle timer; we'll restart if needed.
        idleTimer?.cancel()
        idleTimer = nil

        switch merged {
        case .working:
            currentState = .working
        case .waiting:
            currentState = .waiting
            startIdleTimer()
        case .idle:
            currentState = .idle
        }
    }

    private func startIdleTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + idleTimeout)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            if self.currentState == .waiting {
                self.currentState = .idle
            }
            self.idleTimer = nil
        }
        idleTimer = timer
        timer.resume()
    }
}
