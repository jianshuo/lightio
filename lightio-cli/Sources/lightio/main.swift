import Foundation
import LightioCore

let args = Array(CommandLine.arguments.dropFirst())
let exitCode = run(args)
exit(exitCode)

func run(_ args: [String]) -> Int32 {
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

        case "install-hooks":
            let binaryPath = "/Applications/Lightio.app/Contents/Resources/lightio"
            try HookInstaller.install(settingsURL: Paths.claudeSettingsFile, binaryPath: binaryPath)
            FileHandle.standardOutput.write(Data("Installed lightio hooks at \(Paths.claudeSettingsFile.path)\n".utf8))
            return 0

        case "uninstall-hooks":
            try HookInstaller.uninstall(settingsURL: Paths.claudeSettingsFile)
            FileHandle.standardOutput.write(Data("Removed lightio hooks from \(Paths.claudeSettingsFile.path)\n".utf8))
            return 0

        default:
            FileHandle.standardError.write(
                Data("Usage: lightio <set|clear|status|install-hooks|uninstall-hooks>\n".utf8)
            )
            return 2
        }
    } catch {
        FileHandle.standardError.write(Data("lightio: \(error)\n".utf8))
        return 1
    }
}

func readStdin() -> Data {
    var buf = Data()
    let handle = FileHandle.standardInput
    while true {
        let chunk = handle.availableData
        if chunk.isEmpty { break }
        buf.append(chunk)
    }
    return buf
}

func printUsage() {
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
