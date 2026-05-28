import XCTest
@testable import CCLightCore

final class SessionStateTests: XCTestCase {
    func testRawValuesAreStable() {
        XCTAssertEqual(SessionState.working.rawValue, "working")
        XCTAssertEqual(SessionState.waiting.rawValue, "waiting")
    }

    func testDecodableFromJSONString() throws {
        let json = #""working""#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SessionState.self, from: json)
        XCTAssertEqual(decoded, .working)
    }

    func testMergedStatePicksHighestPriority() {
        XCTAssertEqual(MergedState.merge([.working, .waiting]), .working)
        XCTAssertEqual(MergedState.merge([.waiting, .waiting]), .waiting)
        XCTAssertEqual(MergedState.merge([]), .idle)
    }

    func testMergedStatePriorityOrdering() {
        // attention outranks working so a "needs you" signal isn't drowned out
        // by another session still running.
        XCTAssertGreaterThan(MergedState.attention.priority, MergedState.working.priority)
        XCTAssertGreaterThan(MergedState.working.priority, MergedState.waiting.priority)
        XCTAssertGreaterThan(MergedState.waiting.priority, MergedState.idle.priority)
    }

    func testMergeFromSnapshot() {
        let snapshot = StateSnapshot(sessions: [
            "a": .init(state: .working, ts: 1, cwd: nil),
            "b": .init(state: .waiting, ts: 2, cwd: nil),
        ])
        XCTAssertEqual(MergedState.merge(snapshot: snapshot), .working)

        let onlyWaiting = StateSnapshot(sessions: [
            "x": .init(state: .waiting, ts: 1, cwd: nil)
        ])
        XCTAssertEqual(MergedState.merge(snapshot: onlyWaiting), .waiting)

        let empty = StateSnapshot()
        XCTAssertEqual(MergedState.merge(snapshot: empty), .idle)
    }

    func testHookReasonRawValuesAreStable() {
        XCTAssertEqual(HookReason.sessionStart.rawValue, "session-start")
        XCTAssertEqual(HookReason.userPrompt.rawValue, "user-prompt")
        XCTAssertEqual(HookReason.stop.rawValue, "stop")
        XCTAssertEqual(HookReason.notification.rawValue, "notification")
    }

    func testMergedStateForEntryPromotesNotificationToAttention() {
        let waitingStop = StateSnapshot.SessionEntry(state: .waiting, ts: 1, cwd: nil, reason: .stop)
        XCTAssertEqual(MergedState.mergedState(for: waitingStop), .waiting)

        let waitingNotif = StateSnapshot.SessionEntry(state: .waiting, ts: 1, cwd: nil, reason: .notification)
        XCTAssertEqual(MergedState.mergedState(for: waitingNotif), .attention)

        // working ignores reason entirely.
        let workingNotif = StateSnapshot.SessionEntry(state: .working, ts: 1, cwd: nil, reason: .notification)
        XCTAssertEqual(MergedState.mergedState(for: workingNotif), .working)
    }

    func testMergeFromSnapshotWithNotificationYieldsAttention() {
        let snapshot = StateSnapshot(sessions: [
            "a": .init(state: .working, ts: 1, cwd: nil, reason: .userPrompt),
            "b": .init(state: .waiting, ts: 2, cwd: nil, reason: .notification),
        ])
        // Attention outranks working — Claude paused for input takes priority.
        XCTAssertEqual(MergedState.merge(snapshot: snapshot), .attention)
    }
}
