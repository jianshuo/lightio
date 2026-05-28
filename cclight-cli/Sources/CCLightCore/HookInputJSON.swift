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
