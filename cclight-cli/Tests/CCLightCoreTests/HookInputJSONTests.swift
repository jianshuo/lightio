import XCTest
@testable import CCLightCore

final class HookInputJSONTests: XCTestCase {
    func testParsesFullPayload() throws {
        let json = """
        {
          "session_id": "abc-123",
          "transcript_path": "/Users/x/.claude/projects/x/abc-123.jsonl",
          "cwd": "/Users/x/code/foo",
          "hook_event_name": "UserPromptSubmit"
        }
        """
        let parsed = try HookInputJSON.parse(Data(json.utf8))
        XCTAssertEqual(parsed.sessionId, "abc-123")
        XCTAssertEqual(parsed.cwd, "/Users/x/code/foo")
    }

    func testEmptyInputYieldsDefaultSession() throws {
        let parsed = try HookInputJSON.parse(Data())
        XCTAssertEqual(parsed.sessionId, "default")
        XCTAssertNil(parsed.cwd)
    }

    func testMalformedJSONYieldsDefaultSession() throws {
        let parsed = try HookInputJSON.parse(Data("nonsense".utf8))
        XCTAssertEqual(parsed.sessionId, "default")
        XCTAssertNil(parsed.cwd)
    }

    func testIgnoresUnknownFields() throws {
        let json = """
        {"session_id": "x", "tool_name": "Bash", "future_field": 42}
        """
        let parsed = try HookInputJSON.parse(Data(json.utf8))
        XCTAssertEqual(parsed.sessionId, "x")
    }
}
