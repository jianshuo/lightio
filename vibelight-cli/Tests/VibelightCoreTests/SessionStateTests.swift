import XCTest
@testable import VibelightCore

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

    func testMergedStateOrderingIsWorkingGreaterThanWaitingGreaterThanIdle() {
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
}
