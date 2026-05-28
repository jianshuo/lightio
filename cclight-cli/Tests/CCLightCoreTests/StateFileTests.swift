import XCTest
@testable import CCLightCore

final class StateFileTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cclight-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        setenv("VIBELIGHT_STATE_DIR", tempDir.path, 1)
    }

    override func tearDownWithError() throws {
        unsetenv("VIBELIGHT_STATE_DIR")
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testReadMissingFileReturnsEmpty() throws {
        let snapshot = try StateFile.read()
        XCTAssertEqual(snapshot.version, 1)
        XCTAssertTrue(snapshot.sessions.isEmpty)
    }

    func testRoundTripPreservesSessions() throws {
        let original = StateSnapshot(sessions: [
            "sess-a": StateSnapshot.SessionEntry(state: .working, ts: 1_700_000_000, cwd: "/tmp/a"),
            "sess-b": StateSnapshot.SessionEntry(state: .waiting, ts: 1_700_000_100, cwd: nil),
        ])
        try StateFile.write(original)

        let reloaded = try StateFile.read()
        XCTAssertEqual(reloaded.sessions.count, 2)
        XCTAssertEqual(reloaded.sessions["sess-a"]?.state, .working)
        XCTAssertEqual(reloaded.sessions["sess-a"]?.cwd, "/tmp/a")
        XCTAssertEqual(reloaded.sessions["sess-b"]?.state, .waiting)
        XCTAssertNil(reloaded.sessions["sess-b"]?.cwd)
    }

    func testMalformedJSONReturnsEmptySnapshot() throws {
        try FileManager.default.createDirectory(at: Paths.stateDir, withIntermediateDirectories: true)
        try "this is not json".data(using: .utf8)!.write(to: Paths.stateFile)

        let snapshot = try StateFile.read()
        XCTAssertTrue(snapshot.sessions.isEmpty)
    }

    func testWriteLeavesNoTmpFiles() throws {
        let snapshot = StateSnapshot(sessions: [
            "x": StateSnapshot.SessionEntry(state: .working, ts: 1, cwd: nil)
        ])
        try StateFile.write(snapshot)
        let entries = try FileManager.default.contentsOfDirectory(atPath: Paths.stateDir.path)
        XCTAssertEqual(entries.filter { $0.contains(".tmp") }, [])
    }

    func testUpdateAtomicallyMergesSessions() throws {
        try StateFile.write(StateSnapshot(sessions: [
            "a": StateSnapshot.SessionEntry(state: .working, ts: 1, cwd: nil)
        ]))
        try StateFile.update { snapshot in
            snapshot.sessions["b"] = StateSnapshot.SessionEntry(state: .waiting, ts: 2, cwd: nil)
        }
        let reloaded = try StateFile.read()
        XCTAssertEqual(reloaded.sessions.count, 2)
        XCTAssertEqual(reloaded.sessions["a"]?.state, .working)
        XCTAssertEqual(reloaded.sessions["b"]?.state, .waiting)
    }
}
