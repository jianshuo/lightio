import XCTest
@testable import VibelightCore

/// Integration tests that spawn the compiled `vibelight` binary.
/// They locate the binary via DerivedBuilds in `.build/`.
final class CLITests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vibelight-cli-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testSetWritesSessionToStateFile() throws {
        let payload = #"{"session_id":"abc-123","cwd":"/tmp/foo"}"#
        let result = try runCLI(args: ["set", "working"], stdin: payload)
        XCTAssertEqual(result.exitCode, 0, "stderr=\(result.stderr)")

        // Read state file from the test's tempDir
        setenv("VIBELIGHT_STATE_DIR", tempDir.path, 1)
        defer { unsetenv("VIBELIGHT_STATE_DIR") }
        let snapshot = try StateFile.read()
        XCTAssertEqual(snapshot.sessions["abc-123"]?.state, .working)
        XCTAssertEqual(snapshot.sessions["abc-123"]?.cwd, "/tmp/foo")
    }

    func testClearRemovesSession() throws {
        _ = try runCLI(args: ["set", "working"], stdin: #"{"session_id":"x"}"#)
        _ = try runCLI(args: ["clear"], stdin: #"{"session_id":"x"}"#)
        setenv("VIBELIGHT_STATE_DIR", tempDir.path, 1)
        defer { unsetenv("VIBELIGHT_STATE_DIR") }
        let snapshot = try StateFile.read()
        XCTAssertNil(snapshot.sessions["x"])
    }

    func testStatusPrintsCurrentSessions() throws {
        _ = try runCLI(args: ["set", "waiting"], stdin: #"{"session_id":"y"}"#)
        let result = try runCLI(args: ["status"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("\"y\""), "stdout=\(result.stdout)")
        XCTAssertTrue(result.stdout.contains("waiting"))
    }

    func testUnknownCommandExitsNonZero() throws {
        let result = try runCLI(args: ["frobnicate"])
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("Usage"))
    }

    func testInstallHooksPatchesSettingsFile() throws {
        let fakeClaudeDir = tempDir.appendingPathComponent("dot-claude")
        try FileManager.default.createDirectory(at: fakeClaudeDir, withIntermediateDirectories: true)
        let settingsURL = fakeClaudeDir.appendingPathComponent("settings.json")

        let result = try runCLI(
            args: ["install-hooks"],
            extraEnv: ["VIBELIGHT_CLAUDE_DIR": fakeClaudeDir.path]
        )
        XCTAssertEqual(result.exitCode, 0, "stderr=\(result.stderr)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: settingsURL.path))

        let data = try Data(contentsOf: settingsURL)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let hooks = json["hooks"] as! [String: Any]
        XCTAssertNotNil(hooks["UserPromptSubmit"])
    }

    func testUninstallHooksRemovesVibelightOnly() throws {
        let fakeClaudeDir = tempDir.appendingPathComponent("dot-claude")
        try FileManager.default.createDirectory(at: fakeClaudeDir, withIntermediateDirectories: true)
        _ = try runCLI(args: ["install-hooks"], extraEnv: ["VIBELIGHT_CLAUDE_DIR": fakeClaudeDir.path])
        _ = try runCLI(args: ["uninstall-hooks"], extraEnv: ["VIBELIGHT_CLAUDE_DIR": fakeClaudeDir.path])

        let settingsURL = fakeClaudeDir.appendingPathComponent("settings.json")
        let data = try Data(contentsOf: settingsURL)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let hooks = json["hooks"] as? [String: Any] ?? [:]
        XCTAssertNil(hooks["UserPromptSubmit"])
    }

    // MARK: - Helpers

    private func cliBinary() -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let pkgRoot = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let debug = pkgRoot.appendingPathComponent(".build/debug/vibelight")
        if FileManager.default.fileExists(atPath: debug.path) { return debug }
        let arches = (try? FileManager.default.contentsOfDirectory(
            atPath: pkgRoot.appendingPathComponent(".build").path)) ?? []
        for arch in arches where arch.contains("apple-macosx") {
            let candidate = pkgRoot.appendingPathComponent(".build/\(arch)/debug/vibelight")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return debug
    }

    private struct RunResult { let exitCode: Int32; let stdout: String; let stderr: String }

    private func runCLI(args: [String], stdin: String? = nil, extraEnv: [String: String] = [:]) throws -> RunResult {
        let proc = Process()
        proc.executableURL = cliBinary()
        proc.arguments = args
        var env: [String: String] = [
            "VIBELIGHT_STATE_DIR": tempDir.path,
            "PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin",
        ]
        for (k, v) in extraEnv { env[k] = v }
        proc.environment = env
        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        try proc.run()
        if let stdin = stdin {
            inPipe.fileHandleForWriting.write(Data(stdin.utf8))
        }
        try inPipe.fileHandleForWriting.close()
        proc.waitUntilExit()
        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return RunResult(exitCode: proc.terminationStatus, stdout: out, stderr: err)
    }
}
