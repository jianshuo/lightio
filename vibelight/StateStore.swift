import Foundation
import Combine
import CoreServices
import VibelightCore

/// Watches `~/.vibelight/state.json` and publishes the current merged state
/// to subscribers. Owns the 5-minute idle timer.
final class StateStore: ObservableObject {
    /// Currently-published state. NotchOverlay subscribes to this.
    @Published private(set) var currentState: MergedState = .idle

    /// Active session count (for menu display).
    @Published private(set) var sessionCount: Int = 0

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
        let snapshot = (try? StateFile.read()) ?? StateSnapshot()
        let merged = MergedState.merge(snapshot: snapshot)
        sessionCount = snapshot.sessions.count

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
