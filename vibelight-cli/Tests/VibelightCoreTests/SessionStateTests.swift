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
}
