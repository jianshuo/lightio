# Lightio V1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship V1 of lightio — a macOS menu-bar app that turns the MacBook notch into an ambient Claude Code status indicator, plus a `lightio` CLI that Claude Code hooks call to drive the state.

**Architecture:** Two artifacts in one repo. A SwiftPM package `lightio-cli/` produces both a shared `LightioCore` library (state file I/O, hook payload parsing, hook installer) and the `lightio` CLI binary. The existing `lightio.xcodeproj` Xcode app target depends on `LightioCore` as a local SwiftPM package, embeds the CLI binary in its `Contents/Resources/`, runs as a menu-bar agent (LSUIElement), watches `~/.lightio/state.json` via FSEvents, and renders a transparent borderless `NSWindow` under the notch.

**Tech Stack:** Swift 5.9+, SwiftUI scaffold + AppKit (NSWindow, NSStatusItem, CALayer, CoreServices/FSEvents), Foundation, XCTest, SwiftPM. Target macOS 14 (Sonoma).

**Spec:** [docs/superpowers/specs/2026-05-28-lightio-design.md](../specs/2026-05-28-lightio-design.md)

---

## File Structure

```
lightio/
├── lightio.xcodeproj/           (existing, will reference local package)
├── lightio/                     (app target sources, auto-synced)
│   ├── lightioApp.swift         (modify — switch to AppDelegate adaptor)
│   ├── ContentView.swift          (delete — no main window)
│   ├── AppDelegate.swift          (new — owns top-level controllers)
│   ├── StateStore.swift           (new — FSEvents + merge + idle timer)
│   ├── NotchGeometry.swift        (new — derive notch rect from NSScreen)
│   ├── NotchOverlayWindow.swift   (new — borderless NSWindow setup)
│   ├── NotchOverlayView.swift     (new — CALayer rendering)
│   ├── MenuBarController.swift    (new — NSStatusItem + menu)
│   └── FirstRun.swift             (new — symlink + hooks + login-item dialogs)
├── lightio-cli/                 (new SwiftPM package)
│   ├── Package.swift
│   ├── Sources/
│   │   ├── LightioCore/
│   │   │   ├── SessionState.swift
│   │   │   ├── StateFile.swift
│   │   │   ├── HookInputJSON.swift
│   │   │   ├── HookInstaller.swift
│   │   │   └── Paths.swift
│   │   └── lightio/             (CLI executable)
│   │       └── main.swift
│   └── Tests/
│       └── LightioCoreTests/
│           ├── StateFileTests.swift
│           ├── HookInputJSONTests.swift
│           ├── HookInstallerTests.swift
│           └── CLITests.swift
└── docs/superpowers/{specs,plans}/...
```

**Why split this way:** The CLI must be invokable independently (Claude Code hooks call it from any cwd), so it lives in SwiftPM where it builds and tests as a standalone command. The app depends on the same `LightioCore` library for shared types (`SessionState`, file IO) so the two halves of the system can never drift out of sync.

---

## Task 1: Project setup — SwiftPM package, Xcode dependency, build phase

**Files:**
- Create: `lightio-cli/Package.swift`
- Create: `lightio-cli/Sources/LightioCore/.gitkeep`
- Create: `lightio-cli/Sources/lightio/main.swift`
- Create: `lightio-cli/Tests/LightioCoreTests/SmokeTest.swift`
- Modify: `.gitignore`
- Manual Xcode work: add local package dep, add Run Script build phase

- [ ] **Step 1: Create the SwiftPM manifest**

Create `lightio-cli/Package.swift`:

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "lightio-cli",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LightioCore", targets: ["LightioCore"]),
        .executable(name: "lightio", targets: ["lightio"]),
    ],
    targets: [
        .target(
            name: "LightioCore",
            path: "Sources/LightioCore"
        ),
        .executableTarget(
            name: "lightio",
            dependencies: ["LightioCore"],
            path: "Sources/lightio"
        ),
        .testTarget(
            name: "LightioCoreTests",
            dependencies: ["LightioCore"],
            path: "Tests/LightioCoreTests"
        ),
    ]
)
```

- [ ] **Step 2: Create placeholder CLI entry**

Create `lightio-cli/Sources/lightio/main.swift`:

```swift
import Foundation

print("lightio (stub)")
exit(0)
```

Create `lightio-cli/Sources/LightioCore/.gitkeep` (empty file — SwiftPM needs the directory to exist).

- [ ] **Step 3: Create a smoke test so the test target compiles**

Create `lightio-cli/Tests/LightioCoreTests/SmokeTest.swift`:

```swift
import XCTest
@testable import LightioCore

final class SmokeTest: XCTestCase {
    func testCanImportModule() {
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 4: Verify SwiftPM builds and tests pass**

Run:
```bash
cd /Users/jianshuo/code/lightio/lightio-cli
swift build
swift test
```

Expected:
- `swift build` succeeds and produces `.build/debug/lightio`.
- `swift test` reports `1 test passed`.

- [ ] **Step 5: Extend .gitignore for SwiftPM and Xcode build artifacts**

Edit `/Users/jianshuo/code/lightio/.gitignore`. After existing contents, append:

```
# SwiftPM
lightio-cli/.build/
lightio-cli/.swiftpm/
lightio-cli/Package.resolved
```

- [ ] **Step 6: Add the local SwiftPM package as an Xcode dependency**

This is Xcode UI work, no code to write. Open `lightio.xcodeproj` in Xcode, then:

1. Select the project root in the navigator → `lightio` project (not the target) → "Package Dependencies" tab → click `+`.
2. In the dialog click "Add Local..." (bottom-left button).
3. Choose the folder `lightio-cli` and click "Add Package".
4. In the next dialog, ensure the `LightioCore` library is added to the `lightio` app target. Click "Add Package".
5. Build the app target (⌘B). It should still build the SwiftUI scaffold but now linked against `LightioCore`.

If Xcode complains about Package.resolved, that file is auto-generated and was intentionally gitignored in Step 5.

- [ ] **Step 7: Add a Run Script build phase to embed the CLI**

Still in Xcode:

1. Select `lightio` target → "Build Phases" tab.
2. Click `+` (top-left of the Build Phases pane) → "New Run Script Phase".
3. Rename the new phase to "Embed lightio CLI" (double-click the title).
4. Drag the phase to be **after** "Copy Bundle Resources" but before any "Sign" phase.
5. Uncheck "Based on dependency analysis" (we want this to always run).
6. Paste this script into the body:

```bash
set -euo pipefail
CLI_DIR="$SRCROOT/lightio-cli"

cd "$CLI_DIR"
swift build -c release --arch arm64 --disable-sandbox

DEST="$TARGET_BUILD_DIR/$PRODUCT_NAME.app/Contents/Resources"
mkdir -p "$DEST"
cp ".build/arm64-apple-macosx/release/lightio" "$DEST/lightio"
chmod +x "$DEST/lightio"
echo "Embedded lightio CLI → $DEST/lightio"
```

- [ ] **Step 8: Build the app to verify the CLI gets embedded**

In Xcode, ⌘B to build the app target. The build log should show "Embedded lightio CLI → …".

Then inspect:
```bash
ls -l ~/Library/Developer/Xcode/DerivedData/lightio-*/Build/Products/Debug/lightio.app/Contents/Resources/lightio
```

Expected: the file exists and is executable (~3 MB Swift binary).

- [ ] **Step 9: Commit**

```bash
cd /Users/jianshuo/code/lightio
git add lightio-cli .gitignore lightio.xcodeproj
git commit -m "Scaffold SwiftPM CLI package and embed-on-build phase"
```

Note: `lightio.xcodeproj` changed because Xcode wrote package-reference and build-phase entries into `project.pbxproj`. That's expected.

---

## Task 2: SessionState model + Paths helper

**Files:**
- Create: `lightio-cli/Sources/LightioCore/SessionState.swift`
- Create: `lightio-cli/Sources/LightioCore/Paths.swift`
- Create: `lightio-cli/Tests/LightioCoreTests/SessionStateTests.swift`

- [ ] **Step 1: Write the failing test for SessionState codable round-trip and merge**

Create `lightio-cli/Tests/LightioCoreTests/SessionStateTests.swift`:

```swift
import XCTest
@testable import LightioCore

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
```

- [ ] **Step 2: Run the test to confirm it fails to compile**

```bash
cd /Users/jianshuo/code/lightio/lightio-cli
swift test --filter SessionStateTests
```

Expected: build error — `SessionState`, `MergedState` not defined.

- [ ] **Step 3: Implement SessionState and MergedState**

Create `lightio-cli/Sources/LightioCore/SessionState.swift`:

```swift
import Foundation

/// Per-session state written by the CLI to state.json.
/// IDLE is intentionally absent here — it's a presentation-layer concept
/// derived from a timer in the app, never serialized.
public enum SessionState: String, Codable, Sendable, Equatable {
    case working
    case waiting
}

/// The visible overlay state, derived from the union of all session states.
public enum MergedState: String, Sendable, Equatable {
    case working
    case waiting
    case idle

    public var priority: Int {
        switch self {
        case .working: return 2
        case .waiting: return 1
        case .idle:    return 0
        }
    }

    /// Highest-priority state across the given sessions; empty → .idle.
    public static func merge(_ states: [SessionState]) -> MergedState {
        states.reduce(MergedState.idle) { acc, s in
            let candidate: MergedState = (s == .working) ? .working : .waiting
            return candidate.priority > acc.priority ? candidate : acc
        }
    }
}
```

- [ ] **Step 4: Run the test to confirm it passes**

```bash
swift test --filter SessionStateTests
```

Expected: all 4 tests pass.

- [ ] **Step 5: Implement Paths helper**

Create `lightio-cli/Sources/LightioCore/Paths.swift`:

```swift
import Foundation

/// Resolves the paths lightio reads/writes. Honors `VIBELIGHT_STATE_DIR`
/// for tests so we never touch the user's real `~/.lightio`.
public enum Paths {
    public static var stateDir: URL {
        if let override = ProcessInfo.processInfo.environment["VIBELIGHT_STATE_DIR"] {
            return URL(fileURLWithPath: override)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".lightio", isDirectory: true)
    }

    public static var stateFile: URL {
        stateDir.appendingPathComponent("state.json")
    }

    public static var claudeSettingsFile: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".claude/settings.json")
    }
}
```

- [ ] **Step 6: Commit**

```bash
git add lightio-cli/Sources/LightioCore/SessionState.swift \
        lightio-cli/Sources/LightioCore/Paths.swift \
        lightio-cli/Tests/LightioCoreTests/SessionStateTests.swift
git commit -m "Add SessionState + MergedState + Paths"
```

---

## Task 3: StateFile — atomic JSON read/write

**Files:**
- Create: `lightio-cli/Sources/LightioCore/StateFile.swift`
- Create: `lightio-cli/Tests/LightioCoreTests/StateFileTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `lightio-cli/Tests/LightioCoreTests/StateFileTests.swift`:

```swift
import XCTest
@testable import LightioCore

final class StateFileTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lightio-tests-\(UUID().uuidString)")
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

    func testWriteIsAtomic() throws {
        // Write a valid snapshot, then verify no leftover .tmp files
        let snapshot = StateSnapshot(sessions: [
            "x": StateSnapshot.SessionEntry(state: .working, ts: 1, cwd: nil)
        ])
        try StateFile.write(snapshot)
        let entries = try FileManager.default.contentsOfDirectory(atPath: Paths.stateDir.path)
        XCTAssertEqual(entries.filter { $0.hasSuffix(".tmp") }, [])
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
```

- [ ] **Step 2: Run tests to confirm they fail to compile**

```bash
swift test --filter StateFileTests
```

Expected: build error — `StateSnapshot`, `StateFile` not defined.

- [ ] **Step 3: Implement StateSnapshot + StateFile**

Create `lightio-cli/Sources/LightioCore/StateFile.swift`:

```swift
import Foundation

/// In-memory representation of `~/.lightio/state.json`.
public struct StateSnapshot: Codable, Equatable, Sendable {
    public var version: Int
    public var sessions: [String: SessionEntry]

    public struct SessionEntry: Codable, Equatable, Sendable {
        public var state: SessionState
        public var ts: Int
        public var cwd: String?

        public init(state: SessionState, ts: Int, cwd: String?) {
            self.state = state
            self.ts = ts
            self.cwd = cwd
        }
    }

    public init(version: Int = 1, sessions: [String: SessionEntry] = [:]) {
        self.version = version
        self.sessions = sessions
    }
}

public enum StateFile {
    /// Read state.json. Missing file → empty snapshot. Malformed → empty + log to stderr.
    public static func read() throws -> StateSnapshot {
        let url = Paths.stateFile
        guard FileManager.default.fileExists(atPath: url.path) else {
            return StateSnapshot()
        }
        do {
            let data = try Data(contentsOf: url)
            if data.isEmpty { return StateSnapshot() }
            return try JSONDecoder().decode(StateSnapshot.self, from: data)
        } catch {
            FileHandle.standardError.write(Data("lightio: malformed state.json: \(error)\n".utf8))
            return StateSnapshot()
        }
    }

    /// Atomic write: write to `state.json.tmp.<pid>` then rename(2) over state.json.
    public static func write(_ snapshot: StateSnapshot) throws {
        try FileManager.default.createDirectory(
            at: Paths.stateDir, withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)

        let tmpURL = Paths.stateFile.appendingPathExtension("tmp.\(ProcessInfo.processInfo.processIdentifier)")
        try data.write(to: tmpURL, options: .atomic)
        // `replaceItemAt` does the rename; if the destination doesn't exist
        // it creates it.
        _ = try FileManager.default.replaceItemAt(Paths.stateFile, withItemAt: tmpURL)
    }

    /// Read → mutate → write, in one shot. Note: not safe across multiple
    /// concurrent writers from different processes; the CLI writes are
    /// fast (<10ms) and Claude Code hook bursts are sequential per-session,
    /// so the race window is acceptable for V1.
    public static func update(_ mutate: (inout StateSnapshot) throws -> Void) throws {
        var snapshot = try read()
        try mutate(&snapshot)
        try write(snapshot)
    }
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
swift test --filter StateFileTests
```

Expected: all 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lightio-cli/Sources/LightioCore/StateFile.swift \
        lightio-cli/Tests/LightioCoreTests/StateFileTests.swift
git commit -m "Add StateFile with atomic write and tests"
```

---

## Task 4: HookInputJSON — parse Claude Code's stdin payload

**Files:**
- Create: `lightio-cli/Sources/LightioCore/HookInputJSON.swift`
- Create: `lightio-cli/Tests/LightioCoreTests/HookInputJSONTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `lightio-cli/Tests/LightioCoreTests/HookInputJSONTests.swift`:

```swift
import XCTest
@testable import LightioCore

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
```

- [ ] **Step 2: Run tests to confirm they fail to compile**

```bash
swift test --filter HookInputJSONTests
```

Expected: build error.

- [ ] **Step 3: Implement HookInputJSON**

Create `lightio-cli/Sources/LightioCore/HookInputJSON.swift`:

```swift
import Foundation

public struct HookInputJSON: Equatable {
    public let sessionId: String
    public let cwd: String?

    public static let defaultSessionId = "default"

    /// Permissive parse: empty input or malformed JSON returns a fallback
    /// `defaultSessionId` so dev-testing the CLI without piping JSON still works.
    public static func parse(_ data: Data) throws -> HookInputJSON {
        guard !data.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return HookInputJSON(sessionId: defaultSessionId, cwd: nil)
        }
        let sessionId = (obj["session_id"] as? String).flatMap {
            $0.isEmpty ? nil : $0
        } ?? defaultSessionId
        let cwd = obj["cwd"] as? String
        return HookInputJSON(sessionId: sessionId, cwd: cwd)
    }
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
swift test --filter HookInputJSONTests
```

Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lightio-cli/Sources/LightioCore/HookInputJSON.swift \
        lightio-cli/Tests/LightioCoreTests/HookInputJSONTests.swift
git commit -m "Add permissive HookInputJSON parser"
```

---

## Task 5: CLI commands `set` / `clear` / `status`

**Files:**
- Modify: `lightio-cli/Sources/lightio/main.swift`
- Create: `lightio-cli/Tests/LightioCoreTests/CLITests.swift`

- [ ] **Step 1: Write the failing CLI integration tests**

Create `lightio-cli/Tests/LightioCoreTests/CLITests.swift`:

```swift
import XCTest
@testable import LightioCore

/// Integration tests that spawn the compiled `lightio` binary.
/// They locate the binary via DerivedBuilds in `.build/`.
final class CLITests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lightio-cli-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testSetWritesSessionToStateFile() throws {
        let payload = #"{"session_id":"abc-123","cwd":"/tmp/foo"}"#
        let result = try runCLI(args: ["set", "working"], stdin: payload)
        XCTAssertEqual(result.exitCode, 0, "stderr=\(result.stderr)")

        let snapshot = try StateFile.read()
        XCTAssertEqual(snapshot.sessions["abc-123"]?.state, .working)
        XCTAssertEqual(snapshot.sessions["abc-123"]?.cwd, "/tmp/foo")
    }

    func testClearRemovesSession() throws {
        _ = try runCLI(args: ["set", "working"], stdin: #"{"session_id":"x"}"#)
        _ = try runCLI(args: ["clear"], stdin: #"{"session_id":"x"}"#)
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

    // MARK: - Helpers

    private func cliBinary() -> URL {
        // SwiftPM puts the executable at .build/{arch}-apple-macosx/debug/lightio.
        // Tests run from the package root, but we resolve relative to this file.
        let here = URL(fileURLWithPath: #filePath)
        let pkgRoot = here.deletingLastPathComponent()  // LightioCoreTests
            .deletingLastPathComponent()                 // Tests
            .deletingLastPathComponent()                 // lightio-cli
        let debug = pkgRoot.appendingPathComponent(".build/debug/lightio")
        if FileManager.default.fileExists(atPath: debug.path) { return debug }
        // Fallback: search the arch-specific dir
        let arches = (try? FileManager.default.contentsOfDirectory(
            atPath: pkgRoot.appendingPathComponent(".build").path)) ?? []
        for arch in arches where arch.contains("apple-macosx") {
            let candidate = pkgRoot.appendingPathComponent(".build/\(arch)/debug/lightio")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return debug
    }

    private struct RunResult { let exitCode: Int32; let stdout: String; let stderr: String }

    private func runCLI(args: [String], stdin: String? = nil) throws -> RunResult {
        let proc = Process()
        proc.executableURL = cliBinary()
        proc.arguments = args
        proc.environment = [
            "VIBELIGHT_STATE_DIR": tempDir.path,
            "PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin",
        ]
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
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd /Users/jianshuo/code/lightio/lightio-cli
swift build  # ensures the binary exists for the integration test
swift test --filter CLITests
```

Expected: all 4 tests fail — `lightio set` prints "lightio (stub)" and exits 0 without writing state.

- [ ] **Step 3: Implement CLI dispatch**

Replace `lightio-cli/Sources/lightio/main.swift`:

```swift
import Foundation
import LightioCore

@main
struct LightioCLI {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        let exitCode = run(args)
        exit(exitCode)
    }

    static func run(_ args: [String]) -> Int32 {
        guard let command = args.first else {
            printUsage()
            return 2
        }
        do {
            switch command {
            case "set":
                guard args.count >= 2,
                      let state = SessionState(rawValue: args[1])
                else {
                    FileHandle.standardError.write(Data("Usage: lightio set <working|waiting>\n".utf8))
                    return 2
                }
                let input = try HookInputJSON.parse(readStdin())
                try StateFile.update { snapshot in
                    snapshot.sessions[input.sessionId] = StateSnapshot.SessionEntry(
                        state: state,
                        ts: Int(Date().timeIntervalSince1970),
                        cwd: input.cwd
                    )
                }
                return 0

            case "clear":
                let input = try HookInputJSON.parse(readStdin())
                try StateFile.update { snapshot in
                    snapshot.sessions.removeValue(forKey: input.sessionId)
                }
                return 0

            case "status":
                let snapshot = try StateFile.read()
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(snapshot)
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
                return 0

            default:
                FileHandle.standardError.write(Data("Usage: lightio <set|clear|status|install-hooks|uninstall-hooks>\n".utf8))
                return 2
            }
        } catch {
            FileHandle.standardError.write(Data("lightio: \(error)\n".utf8))
            return 1
        }
    }

    static func readStdin() -> Data {
        // Read all of stdin until EOF. Returns empty Data if stdin is not piped.
        var buf = Data()
        let handle = FileHandle.standardInput
        // Use availableData in a loop so we never block forever if no pipe.
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            buf.append(chunk)
        }
        return buf
    }

    static func printUsage() {
        let msg = """
        Usage: lightio <command>
          set <working|waiting>    Update this session's state (reads hook JSON from stdin)
          clear                    Remove this session (reads hook JSON from stdin)
          status                   Print current state.json
          install-hooks            Install lightio hooks into ~/.claude/settings.json
          uninstall-hooks          Remove lightio hooks from ~/.claude/settings.json
        """
        FileHandle.standardError.write(Data((msg + "\n").utf8))
    }
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
swift build
swift test --filter CLITests
```

Expected: all 4 CLITests pass. (`install-hooks` / `uninstall-hooks` will hit the "Usage" branch for now — that's the unknown-command test.)

- [ ] **Step 5: Commit**

```bash
git add lightio-cli/Sources/lightio/main.swift \
        lightio-cli/Tests/LightioCoreTests/CLITests.swift
git commit -m "Implement lightio set/clear/status commands"
```

---

## Task 6: HookInstaller — patch `~/.claude/settings.json`

**Files:**
- Create: `lightio-cli/Sources/LightioCore/HookInstaller.swift`
- Create: `lightio-cli/Tests/LightioCoreTests/HookInstallerTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `lightio-cli/Tests/LightioCoreTests/HookInstallerTests.swift`:

```swift
import XCTest
@testable import LightioCore

final class HookInstallerTests: XCTestCase {
    var tempHome: URL!

    override func setUpWithError() throws {
        tempHome = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lightio-hookinstaller-\(UUID().uuidString)")
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
        try HookInstaller.install(settingsURL: settingsURL, binaryPath: "/usr/local/bin/lightio")

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

        try HookInstaller.install(settingsURL: settingsURL, binaryPath: "/usr/local/bin/lightio")

        let data = try Data(contentsOf: settingsURL)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["otherKey"] as? Int, 42)
        let hooks = json["hooks"] as! [String: Any]
        XCTAssertNotNil(hooks["PreToolUse"], "existing hook should be preserved")
        XCTAssertNotNil(hooks["UserPromptSubmit"], "lightio hook should be installed")
    }

    func testInstallIsIdempotent() throws {
        try HookInstaller.install(settingsURL: settingsURL, binaryPath: "/usr/local/bin/lightio")
        try HookInstaller.install(settingsURL: settingsURL, binaryPath: "/usr/local/bin/lightio")

        let data = try Data(contentsOf: settingsURL)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let hooks = json["hooks"] as! [String: Any]
        let userPrompt = hooks["UserPromptSubmit"] as! [[String: Any]]
        XCTAssertEqual(userPrompt.count, 1, "should not duplicate on repeat install")
    }

    func testInstallCreatesBackupOnce() throws {
        let existing = #"{"hooks":{}}"#
        try existing.data(using: .utf8)!.write(to: settingsURL)

        try HookInstaller.install(settingsURL: settingsURL, binaryPath: "/usr/local/bin/lightio")
        let backupURL = settingsURL.appendingPathExtension("lightio-backup")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
        let backupData = try String(contentsOf: backupURL)
        XCTAssertEqual(backupData, existing)

        // Second install must NOT overwrite the backup (which would lose original)
        try HookInstaller.install(settingsURL: settingsURL, binaryPath: "/usr/local/bin/lightio")
        let backupDataAfter = try String(contentsOf: backupURL)
        XCTAssertEqual(backupDataAfter, existing, "backup must remain the original")
    }

    func testUninstallRemovesLightioHooksKeepsOthers() throws {
        let existing = """
        {
          "hooks": {
            "PreToolUse": [{"hooks": [{"type":"command","command":"echo hi"}]}]
          }
        }
        """
        try existing.data(using: .utf8)!.write(to: settingsURL)

        try HookInstaller.install(settingsURL: settingsURL, binaryPath: "/usr/local/bin/lightio")
        try HookInstaller.uninstall(settingsURL: settingsURL)

        let data = try Data(contentsOf: settingsURL)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let hooks = json["hooks"] as! [String: Any]
        XCTAssertNotNil(hooks["PreToolUse"], "non-lightio hook preserved")
        XCTAssertNil(hooks["UserPromptSubmit"], "lightio hook removed")
    }
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
swift test --filter HookInstallerTests
```

Expected: build error — `HookInstaller` not defined.

- [ ] **Step 3: Implement HookInstaller**

Create `lightio-cli/Sources/LightioCore/HookInstaller.swift`:

```swift
import Foundation

public enum HookInstaller {
    /// Marker we embed in each command string so uninstall can find our hooks.
    public static let marker = "lightio"

    /// Hook events lightio installs.
    static let hookEvents: [(event: String, args: String)] = [
        ("SessionStart",     "set waiting"),
        ("UserPromptSubmit", "set working"),
        ("Stop",             "set waiting"),
        ("Notification",     "set waiting"),
        ("SessionEnd",       "clear"),
    ]

    /// Install lightio hooks into the given settings.json (creating the file
    /// if missing). Existing non-lightio hooks are preserved. A one-time
    /// backup is written to `<file>.lightio-backup`.
    public static func install(settingsURL: URL, binaryPath: String) throws {
        try writeBackupIfNeeded(settingsURL: settingsURL)

        var json = try readSettings(settingsURL)
        var hooks = (json["hooks"] as? [String: Any]) ?? [:]

        for (event, args) in hookEvents {
            var entries = (hooks[event] as? [[String: Any]]) ?? []
            entries.removeAll { isLightioEntry($0) }
            entries.append([
                "hooks": [[
                    "type": "command",
                    "command": "\(binaryPath) \(args)",
                ]]
            ])
            hooks[event] = entries
        }

        json["hooks"] = hooks
        try writeSettings(json, to: settingsURL)
    }

    /// Remove lightio hooks. Non-lightio hooks are preserved.
    public static func uninstall(settingsURL: URL) throws {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return }
        var json = try readSettings(settingsURL)
        guard var hooks = json["hooks"] as? [String: Any] else { return }

        for (event, _) in hookEvents {
            guard var entries = hooks[event] as? [[String: Any]] else { continue }
            entries.removeAll { isLightioEntry($0) }
            if entries.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = entries
            }
        }
        json["hooks"] = hooks
        try writeSettings(json, to: settingsURL)
    }

    // MARK: - Helpers

    private static func isLightioEntry(_ entry: [String: Any]) -> Bool {
        guard let inner = entry["hooks"] as? [[String: Any]] else { return false }
        return inner.contains { ($0["command"] as? String)?.contains(marker) == true }
    }

    private static func readSettings(_ url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        if data.isEmpty { return [:] }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private static func writeSettings(_ json: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        )
        let tmp = url.appendingPathExtension("tmp.\(ProcessInfo.processInfo.processIdentifier)")
        try data.write(to: tmp, options: .atomic)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
    }

    private static func writeBackupIfNeeded(settingsURL: URL) throws {
        let backup = settingsURL.appendingPathExtension("lightio-backup")
        guard FileManager.default.fileExists(atPath: settingsURL.path),
              !FileManager.default.fileExists(atPath: backup.path)
        else { return }
        try FileManager.default.copyItem(at: settingsURL, to: backup)
    }
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
swift test --filter HookInstallerTests
```

Expected: all 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lightio-cli/Sources/LightioCore/HookInstaller.swift \
        lightio-cli/Tests/LightioCoreTests/HookInstallerTests.swift
git commit -m "Add HookInstaller: install/uninstall lightio hooks"
```

---

## Task 7: CLI `install-hooks` / `uninstall-hooks` commands

**Files:**
- Modify: `lightio-cli/Sources/lightio/main.swift`
- Modify: `lightio-cli/Tests/LightioCoreTests/CLITests.swift`

- [ ] **Step 1: Add failing CLI tests for the new commands**

Append to `lightio-cli/Tests/LightioCoreTests/CLITests.swift` inside the test class:

```swift
    func testInstallHooksPatchesSettingsFile() throws {
        let fakeHome = tempDir.appendingPathComponent("home")
        try FileManager.default.createDirectory(
            at: fakeHome.appendingPathComponent(".claude"),
            withIntermediateDirectories: true
        )
        let settingsURL = fakeHome.appendingPathComponent(".claude/settings.json")

        let result = try runCLI(
            args: ["install-hooks"],
            extraEnv: ["HOME": fakeHome.path]
        )
        XCTAssertEqual(result.exitCode, 0, "stderr=\(result.stderr)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: settingsURL.path))

        let data = try Data(contentsOf: settingsURL)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let hooks = json["hooks"] as! [String: Any]
        XCTAssertNotNil(hooks["UserPromptSubmit"])
    }

    func testUninstallHooksRemovesLightioOnly() throws {
        let fakeHome = tempDir.appendingPathComponent("home")
        try FileManager.default.createDirectory(
            at: fakeHome.appendingPathComponent(".claude"),
            withIntermediateDirectories: true
        )
        _ = try runCLI(args: ["install-hooks"], extraEnv: ["HOME": fakeHome.path])
        _ = try runCLI(args: ["uninstall-hooks"], extraEnv: ["HOME": fakeHome.path])

        let settingsURL = fakeHome.appendingPathComponent(".claude/settings.json")
        let data = try Data(contentsOf: settingsURL)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let hooks = json["hooks"] as? [String: Any] ?? [:]
        XCTAssertNil(hooks["UserPromptSubmit"])
    }
```

Update the `runCLI` helper signature to accept extra env vars. Replace the existing helper with:

```swift
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
```

- [ ] **Step 2: Run tests to confirm new tests fail**

```bash
swift test --filter CLITests/testInstallHooksPatchesSettingsFile
swift test --filter CLITests/testUninstallHooksRemovesLightioOnly
```

Expected: both fail because main.swift still hits the "Usage" branch.

- [ ] **Step 3: Wire install-hooks / uninstall-hooks in main.swift**

In `lightio-cli/Sources/lightio/main.swift`, replace the `default:` case in the switch statement with:

```swift
            case "install-hooks":
                let binaryPath = "/usr/local/bin/lightio"
                try HookInstaller.install(settingsURL: Paths.claudeSettingsFile, binaryPath: binaryPath)
                FileHandle.standardOutput.write(Data("Installed lightio hooks at \(Paths.claudeSettingsFile.path)\n".utf8))
                return 0

            case "uninstall-hooks":
                try HookInstaller.uninstall(settingsURL: Paths.claudeSettingsFile)
                FileHandle.standardOutput.write(Data("Removed lightio hooks from \(Paths.claudeSettingsFile.path)\n".utf8))
                return 0

            default:
                FileHandle.standardError.write(Data("Usage: lightio <set|clear|status|install-hooks|uninstall-hooks>\n".utf8))
                return 2
```

The HookInstaller path resolves through `Paths.claudeSettingsFile`, which uses `FileManager.default.homeDirectoryForCurrentUser`. That honors the `HOME` env var passed by tests.

- [ ] **Step 4: Run all CLITests**

```bash
swift build
swift test --filter CLITests
```

Expected: all 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lightio-cli/Sources/lightio/main.swift \
        lightio-cli/Tests/LightioCoreTests/CLITests.swift
git commit -m "Wire install-hooks/uninstall-hooks into CLI"
```

---

## Task 8: StateStore — merge function (pure, in app target)

**Files:**
- Create: `lightio/StateStore.swift`
- Create: `lightio/StateStoreMergeTests.swift` (will need a test target later — for now we test via the SwiftPM tests since the merge function will live in LightioCore)

**Note:** Since the app target doesn't have a test target yet, push the pure merge logic into `LightioCore`. The `MergedState.merge(_:)` from Task 2 already accepts `[SessionState]`. We add a higher-level wrapper that takes the full `StateSnapshot`.

- [ ] **Step 1: Write the failing test**

Append to `lightio-cli/Tests/LightioCoreTests/SessionStateTests.swift` inside the class:

```swift
    func testMergeFromSnapshot() {
        let snapshot = StateSnapshot(sessions: [
            "a": .init(state: .working, ts: 1, cwd: nil),
            "b": .init(state: .waiting, ts: 2, cwd: nil),
        ])
        XCTAssertEqual(MergedState.merge(snapshot: snapshot), .working)

        let only_waiting = StateSnapshot(sessions: [
            "x": .init(state: .waiting, ts: 1, cwd: nil)
        ])
        XCTAssertEqual(MergedState.merge(snapshot: only_waiting), .waiting)

        let empty = StateSnapshot()
        XCTAssertEqual(MergedState.merge(snapshot: empty), .idle)
    }
```

- [ ] **Step 2: Run the test to confirm it fails**

```bash
swift test --filter SessionStateTests/testMergeFromSnapshot
```

Expected: build error — no overload for `merge(snapshot:)`.

- [ ] **Step 3: Add the snapshot overload**

In `lightio-cli/Sources/LightioCore/SessionState.swift`, append inside the `MergedState` enum after the existing `merge(_:)` method:

```swift
    /// Convenience: derive the merged state directly from a state.json snapshot.
    public static func merge(snapshot: StateSnapshot) -> MergedState {
        merge(snapshot.sessions.values.map { $0.state })
    }
```

- [ ] **Step 4: Run the test to confirm it passes**

```bash
swift test --filter SessionStateTests/testMergeFromSnapshot
```

Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add lightio-cli/Sources/LightioCore/SessionState.swift \
        lightio-cli/Tests/LightioCoreTests/SessionStateTests.swift
git commit -m "Add MergedState.merge(snapshot:) convenience"
```

---

## Task 9: StateStore — FSEvents wiring + publisher in the app

**Files:**
- Create: `lightio/StateStore.swift`

**Note:** This is in the Xcode app target. There's no app-target unit-test target in V1 (per spec's "minimal" stance), so we verify by manual smoke test in Task 16 plus the integration test added at the end of this task.

- [ ] **Step 1: Implement StateStore**

Create `lightio/StateStore.swift`:

```swift
import Foundation
import Combine
import CoreServices
import LightioCore

/// Watches `~/.lightio/state.json` and publishes the current merged state
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
```

- [ ] **Step 2: Smoke-test in isolation (Xcode build only)**

In Xcode, ⌘B. Expected: app target builds. We can't run it yet (no AppDelegate wired) — Task 12 handles that.

- [ ] **Step 3: Commit**

```bash
git add lightio/StateStore.swift
git commit -m "Add StateStore: FSEvents watcher + idle timer"
```

---

## Task 10: NotchGeometry — pure rect computation

**Files:**
- Create: `lightio/NotchGeometry.swift`
- Append: `lightio-cli/Tests/LightioCoreTests/SessionStateTests.swift` (test goes in the SwiftPM package since the geometry math is pure and we want tests, but we keep the file in the app target for runtime access)

**Note:** We duplicate the simple math logic in a way both contexts can use. The pure function takes screen size and notch dimensions as inputs, so it's easy to test with synthetic values.

Actually — to keep DRY, we put the pure function in `LightioCore` and the app calls it.

- Create: `lightio-cli/Sources/LightioCore/NotchGeometry.swift`
- Delete the plan to put it in the app target; replace the import with `import LightioCore`.

- [ ] **Step 1: Write the failing test**

Create `lightio-cli/Tests/LightioCoreTests/NotchGeometryTests.swift`:

```swift
import XCTest
@testable import LightioCore
import CoreGraphics

final class NotchGeometryTests: XCTestCase {
    func testCenteredNotchRectOnM4MacBookPro14() {
        // M4 MBP 14" logical points: 1512 wide. Notch is roughly 200 pt wide × 32 pt tall.
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let notch = NotchGeometry.notchRect(
            screenFrame: screen,
            notchSize: CGSize(width: 200, height: 32),
            menuBarHeight: 32
        )
        XCTAssertEqual(notch.width, 200, accuracy: 0.01)
        XCTAssertEqual(notch.height, 32, accuracy: 0.01)
        XCTAssertEqual(notch.midX, screen.midX, accuracy: 0.01)
        // Notch sits at the very top of the screen (origin.y == screen.maxY - height)
        XCTAssertEqual(notch.maxY, screen.maxY, accuracy: 0.01)
    }

    func testWindowFrameAddsPaddingForGlow() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let notch = NotchGeometry.notchRect(
            screenFrame: screen,
            notchSize: CGSize(width: 200, height: 32),
            menuBarHeight: 32
        )
        let window = NotchGeometry.overlayWindowFrame(notchRect: notch, glowPadding: 40)
        XCTAssertEqual(window.width, 280, accuracy: 0.01)
        XCTAssertEqual(window.height, 112, accuracy: 0.01)
        XCTAssertEqual(window.midX, notch.midX, accuracy: 0.01)
    }
}
```

- [ ] **Step 2: Run test to confirm it fails to compile**

```bash
swift test --filter NotchGeometryTests
```

Expected: build error — `NotchGeometry` not defined.

- [ ] **Step 3: Implement NotchGeometry**

Create `lightio-cli/Sources/LightioCore/NotchGeometry.swift`:

```swift
import CoreGraphics
import Foundation

public enum NotchGeometry {
    /// Compute the on-screen rect of the physical notch (in screen-space points).
    /// `screenFrame` is in the same coordinate system used by `NSScreen.frame`
    /// (origin at bottom-left, y grows upward).
    public static func notchRect(screenFrame: CGRect, notchSize: CGSize, menuBarHeight: CGFloat) -> CGRect {
        let originX = screenFrame.midX - notchSize.width / 2
        let originY = screenFrame.maxY - notchSize.height
        return CGRect(origin: CGPoint(x: originX, y: originY), size: notchSize)
    }

    /// Expand the notch rect by `glowPadding` on all sides — the resulting rect
    /// is where the borderless NSWindow is placed so the glow has room to bleed.
    public static func overlayWindowFrame(notchRect: CGRect, glowPadding: CGFloat) -> CGRect {
        notchRect.insetBy(dx: -glowPadding, dy: -glowPadding)
    }
}
```

- [ ] **Step 4: Run test to confirm it passes**

```bash
swift test --filter NotchGeometryTests
```

Expected: both tests pass.

- [ ] **Step 5: Add an app-side helper that pulls real values from NSScreen**

Create `lightio/NotchGeometry+NSScreen.swift`:

```swift
import AppKit
import LightioCore

extension NotchGeometry {
    /// Best-effort: read the notch dimensions from `NSScreen.safeAreaInsets`
    /// when present (macOS 12+ on notched Macs), falling back to
    /// `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` (the lateral rects
    /// flanking the notch). Returns nil if the screen has no notch.
    static func notchRect(for screen: NSScreen) -> CGRect? {
        let insets = screen.safeAreaInsets
        guard insets.top > 0 else { return nil }

        let menuBarHeight = NSStatusBar.system.thickness  // ~24pt
        let notchHeight = insets.top

        // Estimate notch width from auxiliaryTopLeftArea (the rect to the LEFT of the notch).
        // If it exists, screen width - left.maxX - rightArea.width gives notch width.
        let left = screen.auxiliaryTopLeftArea
        let right = screen.auxiliaryTopRightArea
        let notchWidth: CGFloat
        if let left = left, let right = right {
            notchWidth = screen.frame.maxX - left.maxX - right.width
        } else {
            // Fallback default; M4 14" notch is ~200pt.
            notchWidth = 200
        }

        return notchRect(
            screenFrame: screen.frame,
            notchSize: CGSize(width: notchWidth, height: notchHeight),
            menuBarHeight: menuBarHeight
        )
    }
}
```

- [ ] **Step 6: Commit**

```bash
git add lightio-cli/Sources/LightioCore/NotchGeometry.swift \
        lightio-cli/Tests/LightioCoreTests/NotchGeometryTests.swift \
        lightio/NotchGeometry+NSScreen.swift
git commit -m "Add NotchGeometry pure function + NSScreen helper"
```

---

## Task 11: NotchOverlayWindow — borderless transparent window

**Files:**
- Create: `lightio/NotchOverlayWindow.swift`

- [ ] **Step 1: Implement the window**

Create `lightio/NotchOverlayWindow.swift`:

```swift
import AppKit

/// Borderless, transparent, click-through window that sits exactly under the
/// notch. Belongs to all Spaces, stays above the menu bar, never steals focus.
final class NotchOverlayWindow: NSWindow {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.level = NSWindow.Level(Int(CGShieldingWindowLevel()) + 1)
        self.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]
        // Never become key/main — we don't accept any input.
        self.acceptsMouseMovedEvents = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
```

- [ ] **Step 2: Build to verify no compile errors**

```bash
xcodebuild -project /Users/jianshuo/code/lightio/lightio.xcodeproj -scheme lightio -destination 'platform=macOS' build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add lightio/NotchOverlayWindow.swift
git commit -m "Add NotchOverlayWindow: borderless transparent click-through"
```

---

## Task 12: NotchOverlayView — CALayer glow rendering

**Files:**
- Create: `lightio/NotchOverlayView.swift`

- [ ] **Step 1: Implement the view**

Create `lightio/NotchOverlayView.swift`:

```swift
import AppKit
import Combine
import QuartzCore
import LightioCore

/// Renders the glow underneath the notch. Driven by a published `MergedState`.
final class NotchOverlayView: NSView {
    private let glowLayer = CALayer()
    private let outerGlowLayer = CALayer()
    private let lineLayer = CALayer()
    private var subs: Set<AnyCancellable> = []
    private var currentState: MergedState = .idle

    init(notchSizeInWindow: CGSize) {
        super.init(frame: .zero)
        wantsLayer = true
        layer = CALayer()
        layer?.masksToBounds = false
        setupSublayers(notchSize: notchSizeInWindow)
        applyState(.idle, animated: false)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Subscribe to a MergedState publisher (e.g. StateStore.$currentState).
    func bind<P: Publisher>(_ publisher: P) where P.Output == MergedState, P.Failure == Never {
        publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.applyState(state, animated: true) }
            .store(in: &subs)
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        layoutSublayers()
    }

    private func setupSublayers(notchSize: CGSize) {
        // The notch occupies the top-center of the window. The line and glow
        // hug the *bottom edge* of that notch.
        layer?.addSublayer(outerGlowLayer)
        layer?.addSublayer(glowLayer)
        layer?.addSublayer(lineLayer)

        outerGlowLayer.shadowOpacity = 0.4
        outerGlowLayer.shadowRadius = 32
        outerGlowLayer.shadowOffset = .zero
        outerGlowLayer.backgroundColor = NSColor.clear.cgColor

        glowLayer.shadowOpacity = 0.85
        glowLayer.shadowRadius = 18
        glowLayer.shadowOffset = .zero
        glowLayer.backgroundColor = NSColor.clear.cgColor

        lineLayer.cornerRadius = 1
    }

    private func layoutSublayers() {
        let b = bounds
        // Notch rect, centered horizontally, at the top of the window.
        // The window frame was inset by `glowPadding` on all sides, so the
        // notch sits `glowPadding` from the top.
        let pad: CGFloat = 40
        let notchWidth = b.width - pad * 2
        let notchHeight: CGFloat = 32
        let notchRect = CGRect(
            x: pad,
            y: b.height - pad - notchHeight,
            width: notchWidth,
            height: notchHeight
        )

        // Line: 1pt strip at the BOTTOM edge of the notch.
        lineLayer.frame = CGRect(
            x: notchRect.minX + 6,
            y: notchRect.minY,
            width: notchRect.width - 12,
            height: 1.5
        )

        // Glow source: the shape of the line, but with bigger shadow radii.
        for shadow in [glowLayer, outerGlowLayer] {
            shadow.frame = lineLayer.frame
            shadow.shadowPath = CGPath(rect: shadow.bounds, transform: nil)
        }
    }

    // MARK: - State

    private func applyState(_ state: MergedState, animated: Bool) {
        let color = Self.cgColor(for: state)
        let lineOpacity: Float = (state == .idle) ? 0.15 : 1.0

        currentState = state

        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? 0.30 : 0)
        glowLayer.shadowColor = color
        outerGlowLayer.shadowColor = color
        lineLayer.backgroundColor = color
        lineLayer.opacity = lineOpacity
        glowLayer.opacity = lineOpacity
        outerGlowLayer.opacity = lineOpacity
        CATransaction.commit()
    }

    static func cgColor(for state: MergedState) -> CGColor {
        switch state {
        case .working:
            return NSColor(red: 95/255.0, green: 207/255.0, blue: 122/255.0, alpha: 1).cgColor
        case .waiting:
            return NSColor(red: 245/255.0, green: 166/255.0, blue: 35/255.0, alpha: 1).cgColor
        case .idle:
            return NSColor(white: 0.85, alpha: 1).cgColor
        }
    }
}
```

- [ ] **Step 2: Build to verify no compile errors**

```bash
xcodebuild -project /Users/jianshuo/code/lightio/lightio.xcodeproj -scheme lightio -destination 'platform=macOS' build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add lightio/NotchOverlayView.swift
git commit -m "Add NotchOverlayView: CALayer glow rendering"
```

---

## Task 13: Ding pulse animation on state change

**Files:**
- Modify: `lightio/NotchOverlayView.swift`

- [ ] **Step 1: Add the pulse animation**

Replace the `applyState(_:animated:)` method in `lightio/NotchOverlayView.swift` with:

```swift
    private func applyState(_ state: MergedState, animated: Bool) {
        let newColor = Self.cgColor(for: state)
        let newOpacity: Float = (state == .idle) ? 0.15 : 1.0
        let previousState = currentState
        currentState = state

        // Reduce-motion users get an instant swap.
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let shouldPulse = animated && !reduceMotion && state != previousState

        if !shouldPulse {
            CATransaction.begin()
            CATransaction.setAnimationDuration(animated ? 0.05 : 0)
            glowLayer.shadowColor = newColor
            outerGlowLayer.shadowColor = newColor
            lineLayer.backgroundColor = newColor
            glowLayer.opacity = newOpacity
            outerGlowLayer.opacity = newOpacity
            lineLayer.opacity = newOpacity
            CATransaction.commit()
            return
        }

        // Ding pulse: 0ms current → 150ms white → 350ms new color.
        let whiteColor = NSColor.white.cgColor
        for layer in [glowLayer, outerGlowLayer, lineLayer] {
            let key = "ding-pulse"
            layer.removeAnimation(forKey: key)

            let property = (layer === lineLayer) ? "backgroundColor" : "shadowColor"
            let anim = CAKeyframeAnimation(keyPath: property)
            anim.duration = 0.35
            anim.values = [
                layer.presentation()?.value(forKeyPath: property) as Any,
                whiteColor,
                newColor as Any,
            ]
            anim.keyTimes = [0.0, 0.42, 1.0]
            anim.timingFunctions = [
                CAMediaTimingFunction(name: .easeOut),
                CAMediaTimingFunction(name: .easeIn),
            ]
            anim.isRemovedOnCompletion = true
            layer.add(anim, forKey: key)
            layer.setValue(newColor, forKeyPath: property)
        }

        // Opacity transitions in parallel — fade-in of the new color over 350ms.
        let opacityAnim = CABasicAnimation(keyPath: "opacity")
        opacityAnim.duration = 0.35
        opacityAnim.fromValue = max(glowLayer.opacity, 0.5)
        opacityAnim.toValue = newOpacity
        for layer in [glowLayer, outerGlowLayer, lineLayer] {
            layer.opacity = newOpacity
            layer.add(opacityAnim, forKey: "ding-opacity")
        }
    }
```

- [ ] **Step 2: Build to verify no compile errors**

```bash
xcodebuild -project /Users/jianshuo/code/lightio/lightio.xcodeproj -scheme lightio build 2>&1 | tail -5
```

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add lightio/NotchOverlayView.swift
git commit -m "Add ding-pulse animation on state change"
```

---

## Task 14: MenuBarController — NSStatusItem + menu

**Files:**
- Create: `lightio/MenuBarController.swift`

- [ ] **Step 1: Implement the controller**

Create `lightio/MenuBarController.swift`:

```swift
import AppKit
import Combine
import LightioCore

/// Owns the menu-bar status item: a tinted dot whose color tracks the merged
/// state, and a menu with the install/uninstall hooks actions.
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private weak var store: StateStore?
    private var subs: Set<AnyCancellable> = []

    var onInstallHooks: (() -> Void)?
    var onUninstallHooks: (() -> Void)?
    var onToggleLaunchAtLogin: (() -> Void)?
    var isLaunchAtLoginOn: () -> Bool = { false }

    init(store: StateStore) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.store = store
        super.init()

        setupButtonIcon(state: .idle)
        setupMenu()

        store.$currentState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.setupButtonIcon(state: state) }
            .store(in: &subs)

        store.$sessionCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshMenu() }
            .store(in: &subs)
    }

    private func setupButtonIcon(state: MergedState) {
        guard let button = statusItem.button else { return }
        let size = NSSize(width: 14, height: 14)
        let image = NSImage(size: size, flipped: false) { rect in
            let dotRect = NSRect(x: 3, y: 3, width: 8, height: 8)
            switch state {
            case .working: NSColor(red: 95/255, green: 207/255, blue: 122/255, alpha: 1).setFill()
            case .waiting: NSColor(red: 245/255, green: 166/255, blue: 35/255, alpha: 1).setFill()
            case .idle:    NSColor(white: 0.6, alpha: 1).setFill()
            }
            NSBezierPath(ovalIn: dotRect).fill()
            return true
        }
        image.isTemplate = false
        button.image = image
    }

    private func setupMenu() {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        refreshMenu()
    }

    private func refreshMenu() {
        guard let menu = statusItem.menu else { return }
        menu.removeAllItems()

        let stateLine = NSMenuItem(
            title: stateMenuTitle(),
            action: nil, keyEquivalent: ""
        )
        stateLine.isEnabled = false
        menu.addItem(stateLine)
        menu.addItem(.separator())

        let installItem = NSMenuItem(
            title: "Install Claude Code Hooks",
            action: #selector(installHooks),
            keyEquivalent: ""
        )
        installItem.target = self
        menu.addItem(installItem)

        let uninstallItem = NSMenuItem(
            title: "Uninstall Claude Code Hooks",
            action: #selector(uninstallHooks),
            keyEquivalent: ""
        )
        uninstallItem.target = self
        menu.addItem(uninstallItem)

        menu.addItem(.separator())

        let launchItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchItem.target = self
        launchItem.state = isLaunchAtLoginOn() ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(.separator())

        let about = NSMenuItem(title: "About lightio", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func stateMenuTitle() -> String {
        guard let store = store else { return "lightio" }
        let stateLabel: String
        switch store.currentState {
        case .working: stateLabel = "WORKING"
        case .waiting: stateLabel = "WAITING"
        case .idle:    stateLabel = "IDLE"
        }
        return "状态: \(stateLabel) (\(store.sessionCount) session\(store.sessionCount == 1 ? "" : "s"))"
    }

    // MARK: - Actions

    @objc private func installHooks() { onInstallHooks?() }
    @objc private func uninstallHooks() { onUninstallHooks?() }
    @objc private func toggleLaunchAtLogin() { onToggleLaunchAtLogin?() }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) { refreshMenu() }
}
```

- [ ] **Step 2: Build to verify no compile errors**

```bash
xcodebuild -project /Users/jianshuo/code/lightio/lightio.xcodeproj -scheme lightio build 2>&1 | tail -5
```

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add lightio/MenuBarController.swift
git commit -m "Add MenuBarController: status item dot + menu"
```

---

## Task 15: FirstRun — symlink install, hook install dialog, launch-at-login

**Files:**
- Create: `lightio/FirstRun.swift`

- [ ] **Step 1: Implement FirstRun**

Create `lightio/FirstRun.swift`:

```swift
import AppKit
import ServiceManagement
import LightioCore

/// Handles one-time install steps on first launch and exposes "Install Hooks"
/// as a re-runnable action.
enum FirstRun {
    static let symlinkPath = "/usr/local/bin/lightio"

    /// Path to the CLI bundled inside this .app.
    static var bundledCLIPath: String {
        Bundle.main.resourcePath.map { "\($0)/lightio" }
            ?? "/Applications/lightio.app/Contents/Resources/lightio"
    }

    // MARK: - Symlink

    static func isSymlinkInstalled() -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: symlinkPath) else { return false }
        // Verify it's a symlink pointing to *our* bundled CLI
        let attrs = try? fm.attributesOfItem(atPath: symlinkPath)
        if attrs?[.type] as? FileAttributeType == .typeSymbolicLink {
            let dest = try? fm.destinationOfSymbolicLink(atPath: symlinkPath)
            return dest == bundledCLIPath
        }
        return false
    }

    /// Asks for admin password and creates the symlink. Returns true on success.
    @discardableResult
    static func installSymlinkInteractively() -> Bool {
        let escaped = bundledCLIPath.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        do shell script "mkdir -p /usr/local/bin && ln -sf \\"\(escaped)\\" /usr/local/bin/lightio" with administrator privileges
        """
        var errorInfo: NSDictionary?
        let runner = NSAppleScript(source: script)
        _ = runner?.executeAndReturnError(&errorInfo)
        if let error = errorInfo {
            NSLog("lightio symlink install failed: \(error)")
            return false
        }
        return isSymlinkInstalled()
    }

    // MARK: - Hooks dialog

    static func claudeSettingsExists() -> Bool {
        FileManager.default.fileExists(atPath: Paths.claudeSettingsFile.path)
    }

    /// Shows a modal dialog asking the user to install hooks. Returns whether
    /// the user agreed *and* the install succeeded.
    @discardableResult
    static func offerHooksInstall() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Install Claude Code Hooks?"
        alert.informativeText = """
        检测到 Claude Code (~/.claude/settings.json)。
        是否将 lightio 的 hooks 加入其中？
        原文件会备份到 settings.json.lightio-backup。
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Not Now")
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return false }
        return installHooks()
    }

    /// Patch ~/.claude/settings.json. Returns success.
    @discardableResult
    static func installHooks() -> Bool {
        do {
            try HookInstaller.install(
                settingsURL: Paths.claudeSettingsFile,
                binaryPath: symlinkPath
            )
            return true
        } catch {
            NSLog("lightio installHooks failed: \(error)")
            return false
        }
    }

    @discardableResult
    static func uninstallHooks() -> Bool {
        do {
            try HookInstaller.uninstall(settingsURL: Paths.claudeSettingsFile)
            return true
        } catch {
            NSLog("lightio uninstallHooks failed: \(error)")
            return false
        }
    }

    // MARK: - Launch at Login

    static var isLaunchAtLoginEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    static func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("lightio setLaunchAtLogin failed: \(error)")
            }
        }
    }
}
```

- [ ] **Step 2: Build to verify no compile errors**

```bash
xcodebuild -project /Users/jianshuo/code/lightio/lightio.xcodeproj -scheme lightio build 2>&1 | tail -5
```

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add lightio/FirstRun.swift
git commit -m "Add FirstRun: symlink, hooks dialog, launch-at-login"
```

---

## Task 16: AppDelegate — wire everything together

**Files:**
- Create: `lightio/AppDelegate.swift`
- Modify: `lightio/lightioApp.swift`
- Delete: `lightio/ContentView.swift`
- Configure: Info.plist (via Xcode UI, `LSUIElement = YES`)

- [ ] **Step 1: Write the AppDelegate**

Create `lightio/AppDelegate.swift`:

```swift
import AppKit
import SwiftUI
import LightioCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: StateStore!
    private var overlayWindow: NotchOverlayWindow!
    private var overlayView: NotchOverlayView!
    private var menuBar: MenuBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Start state store
        store = StateStore()
        store.start()

        // 2. Build overlay window + view
        if let screen = NSScreen.main,
           let notchRect = NotchGeometry.notchRect(for: screen) {
            let frame = NotchGeometry.overlayWindowFrame(notchRect: notchRect, glowPadding: 40)
            overlayWindow = NotchOverlayWindow(contentRect: frame)
            overlayView = NotchOverlayView(notchSizeInWindow: notchRect.size)
            overlayWindow.contentView = overlayView
            overlayWindow.orderFrontRegardless()
            overlayView.bind(store.$currentState)
        } else {
            NSLog("lightio: no notch detected; overlay disabled")
        }

        // 3. Build menu bar
        menuBar = MenuBarController(store: store)
        menuBar.isLaunchAtLoginOn = { FirstRun.isLaunchAtLoginEnabled }
        menuBar.onInstallHooks = { [weak self] in self?.handleInstallHooks() }
        menuBar.onUninstallHooks = { [weak self] in self?.handleUninstallHooks() }
        menuBar.onToggleLaunchAtLogin = {
            FirstRun.setLaunchAtLogin(!FirstRun.isLaunchAtLoginEnabled)
        }

        // 4. Run first-run flow if needed (do AFTER UI is up so dialogs show on top)
        DispatchQueue.main.async { [weak self] in self?.runFirstRunIfNeeded() }

        // 5. Self-test glow: flash green for 1s then transition
        flashSelfTest()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store?.stop()
    }

    // MARK: - First-run

    private func runFirstRunIfNeeded() {
        // Symlink
        if !FirstRun.isSymlinkInstalled() {
            let alert = NSAlert()
            alert.messageText = "Install lightio CLI?"
            alert.informativeText = """
            需要把 CLI 安装到 /usr/local/bin/lightio，
            这一步需要管理员密码（一次性）。
            """
            alert.addButton(withTitle: "Install")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn {
                FirstRun.installSymlinkInteractively()
            }
        }
        // Hooks
        if FirstRun.claudeSettingsExists() {
            // Only offer if lightio hooks aren't already there.
            if (try? Data(contentsOf: Paths.claudeSettingsFile))
                .flatMap({ String(data: $0, encoding: .utf8) })?
                .contains(HookInstaller.marker) != true {
                FirstRun.offerHooksInstall()
            }
        }
        // Launch at login (auto-enable on first run)
        if !FirstRun.isLaunchAtLoginEnabled {
            FirstRun.setLaunchAtLogin(true)
        }
    }

    private func handleInstallHooks() {
        if FirstRun.installHooks() {
            let alert = NSAlert()
            alert.messageText = "Hooks installed"
            alert.informativeText = "lightio hooks added to ~/.claude/settings.json"
            alert.runModal()
        } else {
            let alert = NSAlert()
            alert.messageText = "Could not install hooks"
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    private func handleUninstallHooks() {
        _ = FirstRun.uninstallHooks()
    }

    // MARK: - Self-test

    private func flashSelfTest() {
        // The store starts in .idle. Briefly nudge currentState through .working
        // so the user sees the app is alive. We bypass StateStore.reload() by
        // poking the view directly (StateStore's published state is read-only
        // outside the class).
        guard let overlayView = overlayView else { return }
        overlayView.previewState(.working)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.overlayView?.previewState(self?.store.currentState ?? .idle)
        }
    }
}
```

- [ ] **Step 2: Expose `previewState` on NotchOverlayView**

Append to `lightio/NotchOverlayView.swift` inside the class:

```swift
    /// Force the view to a specific state without going through the publisher.
    /// Used only for the startup self-test flash.
    func previewState(_ state: MergedState) {
        applyState(state, animated: true)
    }
```

- [ ] **Step 3: Replace the SwiftUI App entry to use AppDelegate**

Edit `lightio/lightioApp.swift` to be:

```swift
import SwiftUI

@main
struct lightioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Required so SwiftUI has a Scene; never visible because we set
        // LSUIElement = YES in Info.plist.
        Settings { EmptyView() }
    }
}
```

- [ ] **Step 4: Delete the obsolete ContentView**

```bash
rm /Users/jianshuo/code/lightio/lightio/ContentView.swift
```

- [ ] **Step 5: Set LSUIElement in Info.plist (via Xcode UI)**

In Xcode:
1. Select the `lightio` target → "Info" tab (or open the Info.plist editor in the project navigator).
2. Add a new key: `Application is agent (UIElement)` (raw key: `LSUIElement`), type Boolean, value `YES`.
3. Save.

This hides the Dock icon and turns the app into a menu-bar-only agent.

- [ ] **Step 6: Build the app**

```bash
xcodebuild -project /Users/jianshuo/code/lightio/lightio.xcodeproj -scheme lightio build 2>&1 | tail -10
```

Expected: build succeeds.

- [ ] **Step 7: Manual smoke test — launch and observe**

```bash
xcodebuild -project /Users/jianshuo/code/lightio/lightio.xcodeproj -scheme lightio build
APP=$(find ~/Library/Developer/Xcode/DerivedData/lightio-*/Build/Products/Debug/lightio.app -maxdepth 0 -type d | head -1)
open "$APP"
```

Manually verify:
- Dock has NO lightio icon
- Menu bar shows a small dim circle (lightio)
- The notch glows green for ~1s then dims
- Clicking the menu bar item shows the menu with "Install Claude Code Hooks" etc.
- "Quit" exits the app cleanly

Document any issues in a scratch note for later. If a critical failure (no notch glow, crashes) — diagnose before continuing.

- [ ] **Step 8: Commit**

```bash
git add lightio/AppDelegate.swift \
        lightio/lightioApp.swift \
        lightio/NotchOverlayView.swift \
        lightio.xcodeproj
git rm lightio/ContentView.swift
git commit -m "Wire AppDelegate: overlay + menu bar + first-run + LSUIElement"
```

---

## Task 17: End-to-end manual verification with Claude Code

**Files:** No code changes — verification only.

- [ ] **Step 1: Build a fresh debug build**

```bash
xcodebuild -project /Users/jianshuo/code/lightio/lightio.xcodeproj -scheme lightio build
```

- [ ] **Step 2: Locate, copy and launch the .app**

```bash
APP=$(find ~/Library/Developer/Xcode/DerivedData/lightio-*/Build/Products/Debug/lightio.app -maxdepth 0 -type d | head -1)
cp -R "$APP" /Applications/
open /Applications/lightio.app
```

- [ ] **Step 3: Walk through first-run flow**

When the symlink dialog appears → "Install" → enter admin password.
When the hooks dialog appears → "Install".

Verify:
```bash
ls -l /usr/local/bin/lightio
cat ~/.claude/settings.json | python3 -m json.tool | head -40
```

Expected:
- `/usr/local/bin/lightio` is a symlink to the bundled binary
- `~/.claude/settings.json` has 5 hook events with commands containing `lightio`

- [ ] **Step 4: Run a real Claude Code session and observe**

In a new terminal:

```bash
cd ~/code/some-project   # any directory
claude   # start a session
```

Then in Claude Code, type a prompt (e.g., "list files") and watch the notch:

- **WORKING (green)** as Claude responds
- **WAITING (amber)** after Claude finishes
- **Ding pulse** (brief white flash) on each transition
- After 5 minutes of waiting → **IDLE (dim)**

If any state doesn't show: check
```bash
cat ~/.lightio/state.json
lightio status
```

- [ ] **Step 5: Test uninstall flow**

```bash
lightio uninstall-hooks
cat ~/.claude/settings.json | python3 -m json.tool | grep -i lightio
```

Expected: no lightio commands in settings.json.

Reinstall via menu bar → "Install Claude Code Hooks". Verify it comes back.

- [ ] **Step 6: Verify state.json schema**

```bash
cat ~/.lightio/state.json | python3 -m json.tool
```

Expected: matches the schema in the spec — `version: 1`, `sessions` map with `state`, `ts`, optional `cwd` per entry.

- [ ] **Step 7: Document any issues and fix small ones inline**

Open a temporary note (NOT committed) summarizing what worked, what didn't. For each issue:
- If small (typo, label, color tweak) — fix in code, commit a follow-up.
- If structural — capture as a known-issue line in `docs/superpowers/specs/2026-05-28-lightio-design.md` under "Section 10. Risks & open questions".

- [ ] **Step 8: Final commit (if any fixups)**

```bash
git add -p   # cherry-pick fixes
git commit -m "Post-E2E verification fixups"
```

- [ ] **Step 9: Tag V1**

```bash
git tag v0.1.0 -m "lightio V1 — local install"
```

V1 ship complete.

---

## Self-Review

I checked the plan against the spec section by section:

- **Section 1 "What we're building"**: Covered by Task 16 (LSUIElement, overlay), Task 14 (menu bar), Task 17 (manual verify).
- **Section 2 "Three states"**: Tasks 2, 8 (state enums + merge), Task 9 (idle timer), Task 12 (visual representation per state).
- **Section 3 "Visual spec"**: Task 11 (window), Task 12 (CALayer glow + palette), Task 13 (ding pulse + reduce motion).
- **Section 4 "Architecture"**: Task 1 (project structure), Tasks 3-7 (CLI components), Task 9 (StateStore), Tasks 11-14 (UI components).
- **Section 5 "Data formats"**: Task 3 (state.json), Task 6 (settings.json patcher).
- **Section 6 "First-run UX"**: Task 15 (FirstRun), Task 16 (AppDelegate hookup), Task 17 (manual walk-through).
- **Section 7 "Build & ship V1"**: Task 1 build phase, Task 17 manual install.
- **Section 8 "Out of scope"**: respected — no color customization, no per-session split, no notifications, no sandbox.
- **Section 9 "V2"**: explicitly deferred — no tasks for GPT image, App Store, etc.
- **Section 10 "Risks"**: Task 10 step 5 includes the auxiliaryTopLeftArea/Right fallback for notch geometry; Task 15 step 1 documents the `--no-symlink` alternative path via `Bundle.main.resourcePath`.

Placeholders/TODOs: scanned — none.

Type consistency: `SessionState` (`.working`, `.waiting`), `MergedState` (`.working`, `.waiting`, `.idle`), `StateSnapshot.SessionEntry { state, ts, cwd }`, `MergedState.merge([SessionState]) -> MergedState`, `MergedState.merge(snapshot:)`, `StateFile.read/write/update`, `HookInstaller.install/uninstall`, `Paths.stateFile/stateDir/claudeSettingsFile`, `NotchGeometry.notchRect/overlayWindowFrame` — all consistent across tasks.

One follow-up I'll handle as a minor edit-in-task rather than a new task: Task 9's `idleTimer` should also cancel itself when the file disappears (no sessions → IDLE) — handled by the existing `switch merged` block setting `currentState = .idle` without arming the timer. Good.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-28-lightio-v1.md`.

Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration with the main session protected from accumulated context noise.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints for your review.

Which approach?
