import XCTest
@testable import CCLightCore

final class HookInstallerTests: XCTestCase {
    var tempHome: URL!

    override func setUpWithError() throws {
        tempHome = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cclight-hookinstaller-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempHome.appendingPathComponent(".claude"),
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempHome)
    }

    private var settingsURL: URL { tempHome.appendingPathComponent(".claude/settings.json") }

    func testInstallIntoMissingSettingsCreatesFile() throws {
        try HookInstaller.install(settingsURL: settingsURL, binaryPath: "/usr/local/bin/cclight")

        let data = try Data(contentsOf: settingsURL)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let hooks = json["hooks"] as! [String: Any]
        XCTAssertNotNil(hooks["SessionStart"])
        XCTAssertNotNil(hooks["UserPromptSubmit"])
        XCTAssertNotNil(hooks["Stop"])
        XCTAssertNotNil(hooks["Notification"])
        XCTAssertNotNil(hooks["SessionEnd"])
    }

    func testInstallIntoExistingSettingsPreservesOtherKeys() throws {
        let existing = #"{"otherKey": 42, "hooks": {"PreToolUse": [{"hooks": [{"type": "command", "command": "echo hi"}]}]}}"#
        try existing.data(using: .utf8)!.write(to: settingsURL)

        try HookInstaller.install(settingsURL: settingsURL, binaryPath: "/usr/local/bin/cclight")

        let data = try Data(contentsOf: settingsURL)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["otherKey"] as? Int, 42)
        let hooks = json["hooks"] as! [String: Any]
        XCTAssertNotNil(hooks["PreToolUse"], "existing hook should be preserved")
        XCTAssertNotNil(hooks["UserPromptSubmit"], "cclight hook should be installed")
    }

    func testInstallIsIdempotent() throws {
        try HookInstaller.install(settingsURL: settingsURL, binaryPath: "/usr/local/bin/cclight")
        try HookInstaller.install(settingsURL: settingsURL, binaryPath: "/usr/local/bin/cclight")

        let data = try Data(contentsOf: settingsURL)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let hooks = json["hooks"] as! [String: Any]
        let userPrompt = hooks["UserPromptSubmit"] as! [[String: Any]]
        XCTAssertEqual(userPrompt.count, 1, "should not duplicate on repeat install")
    }

    func testInstallCreatesBackupOnce() throws {
        let existing = #"{"hooks":{}}"#
        try existing.data(using: .utf8)!.write(to: settingsURL)

        try HookInstaller.install(settingsURL: settingsURL, binaryPath: "/usr/local/bin/cclight")
        let backupURL = settingsURL.appendingPathExtension("cclight-backup")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
        let backupData = try String(contentsOf: backupURL)
        XCTAssertEqual(backupData, existing)

        // Second install must NOT overwrite the backup
        try HookInstaller.install(settingsURL: settingsURL, binaryPath: "/usr/local/bin/cclight")
        let backupDataAfter = try String(contentsOf: backupURL)
        XCTAssertEqual(backupDataAfter, existing, "backup must remain the original")
    }

    func testInstalledCommandIsWrappedForMissingBinary() throws {
        try HookInstaller.install(settingsURL: settingsURL, binaryPath: "/nonexistent/cclight")

        let data = try Data(contentsOf: settingsURL)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let hooks = json["hooks"] as! [String: Any]
        let sessionEnd = hooks["SessionEnd"] as! [[String: Any]]
        let inner = sessionEnd[0]["hooks"] as! [[String: Any]]
        let command = inner[0]["command"] as! String

        XCTAssertTrue(command.hasPrefix("/bin/sh -c "), "command must be wrapped: \(command)")
        XCTAssertTrue(command.contains("[ -x "), "command must guard with -x test: \(command)")
        XCTAssertTrue(command.contains("exit 0"), "command must end with exit 0: \(command)")

        // The real proof: actually run it. With a missing binary the hook
        // must exit 0 so Claude Code never surfaces a SessionEnd error.
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", command]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        try proc.run()
        proc.waitUntilExit()
        XCTAssertEqual(proc.terminationStatus, 0, "missing-binary hook must no-op cleanly")
    }

    func testInstalledCommandTagsEachEventWithReason() throws {
        try HookInstaller.install(settingsURL: settingsURL, binaryPath: "/usr/local/bin/cclight")

        let data = try Data(contentsOf: settingsURL)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let hooks = json["hooks"] as! [String: Any]

        func command(forEvent event: String) -> String {
            let entries = hooks[event] as! [[String: Any]]
            let inner = entries[0]["hooks"] as! [[String: Any]]
            return inner[0]["command"] as! String
        }

        XCTAssertTrue(command(forEvent: "SessionStart").contains("--reason session-start"))
        XCTAssertTrue(command(forEvent: "UserPromptSubmit").contains("--reason user-prompt"))
        XCTAssertTrue(command(forEvent: "Stop").contains("--reason stop"))
        XCTAssertTrue(command(forEvent: "Notification").contains("--reason notification"))
        // SessionEnd is `clear` — no reason needed.
        XCTAssertFalse(command(forEvent: "SessionEnd").contains("--reason"))
    }

    func testInstalledSetCommandsContainOwnerPid() throws {
        try HookInstaller.install(settingsURL: settingsURL, binaryPath: "/usr/local/bin/cclight")

        let data = try Data(contentsOf: settingsURL)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let hooks = json["hooks"] as! [String: Any]

        func command(forEvent event: String) -> String {
            let entries = hooks[event] as! [[String: Any]]
            let inner = entries[0]["hooks"] as! [[String: Any]]
            return inner[0]["command"] as! String
        }

        // Every `set` event must pass --owner-pid $PPID so the app can detect
        // a dead Claude Code process via kill(pid, 0).
        for event in ["SessionStart", "UserPromptSubmit", "Stop", "Notification"] {
            XCTAssertTrue(
                command(forEvent: event).contains("--owner-pid $PPID"),
                "\(event) must include --owner-pid $PPID, got: \(command(forEvent: event))"
            )
        }
        // SessionEnd is `clear`, no pid needed.
        XCTAssertFalse(command(forEvent: "SessionEnd").contains("--owner-pid"))
    }

    func testInstalledSetCommandExpandsPPIDAtRuntime() throws {
        // The hook wraps `--owner-pid $PPID` inside a sh -c '...' string.
        // The inner sh must expand $PPID to its parent's pid — which in the
        // real install is the Claude Code CLI invoking the hook. We can't
        // simulate that exactly, but we can prove the variable expands at all
        // and yields a numeric pid (≠ literal "$PPID").
        try HookInstaller.install(settingsURL: settingsURL, binaryPath: "/usr/bin/printenv")
        let data = try Data(contentsOf: settingsURL)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let hooks = json["hooks"] as! [String: Any]
        let sessionStart = (hooks["SessionStart"] as! [[String: Any]])
        let inner = (sessionStart[0]["hooks"] as! [[String: Any]])
        let originalCommand = inner[0]["command"] as! String

        // Replace the real binary call with `echo` so we can observe the
        // expanded args. The wrapper structure (sh -c '...') is the same.
        let echoCommand = originalCommand
            .replacingOccurrences(of: "[ -x \"/usr/bin/printenv\" ] && \"/usr/bin/printenv\"",
                                  with: "echo")

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", echoCommand]
        let outPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = Pipe()
        try proc.run()
        proc.waitUntilExit()
        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        XCTAssertFalse(out.contains("$PPID"), "literal $PPID leaked unexpanded: \(out)")
        // After `--owner-pid` there must be a numeric pid (split on any
        // whitespace so a trailing newline doesn't get glued to the pid).
        let parts = out.split(whereSeparator: { $0.isWhitespace })
        guard let idx = parts.firstIndex(of: "--owner-pid"), idx + 1 < parts.count else {
            return XCTFail("--owner-pid arg missing in: \(out)")
        }
        XCTAssertNotNil(Int(parts[idx + 1]), "expected numeric pid after --owner-pid, got: \(parts[idx + 1])")
    }

    func testUninstallRemovesCCLightHooksKeepsOthers() throws {
        let existing = """
        {
          "hooks": {
            "PreToolUse": [{"hooks": [{"type":"command","command":"echo hi"}]}]
          }
        }
        """
        try existing.data(using: .utf8)!.write(to: settingsURL)

        try HookInstaller.install(settingsURL: settingsURL, binaryPath: "/usr/local/bin/cclight")
        try HookInstaller.uninstall(settingsURL: settingsURL)

        let data = try Data(contentsOf: settingsURL)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let hooks = json["hooks"] as! [String: Any]
        XCTAssertNotNil(hooks["PreToolUse"], "non-cclight hook preserved")
        XCTAssertNil(hooks["UserPromptSubmit"], "cclight hook removed")
    }
}
