import CleanupKit
import Foundation

/// API keys in a private file: ~/Library/Application Support/Aloud/keys.env, readable only by you
/// (mode 0600), like ~/.aws/credentials.
///
/// Why not the Keychain: with a self-signed app, macOS asks for your login password every time a
/// rebuilt Aloud reads a Keychain item, which makes it unusable during development.
enum KeyStore {
    static let names = ["ELEVENLABS_API_KEY", "GROQ_API_KEY", "ANTHROPIC_API_KEY"]
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Aloud/keys.env")

    private static func load() -> [String: String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        return EnvFile.parse(text)
    }

    static func get(_ name: String) -> String? {
        load()[name]
    }

    /// Merges `values` into the file and keeps it private.
    @discardableResult
    static func set(_ values: [String: String]) -> Bool {
        var all = load()
        for (k, v) in values where names.contains(k) { all[k] = v }
        let text = names.compactMap { n in all[n].map { "\(n)=\($0)" } }.joined(separator: "\n") + "\n"
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Create with 0600 before writing so the keys are never briefly world-readable.
            if !fm.fileExists(atPath: url.path) {
                fm.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
            }
            try text.write(to: url, atomically: false, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return true
        } catch {
            return false
        }
    }

    static var summary: String {
        let all = load()
        return names.map { "\($0.replacingOccurrences(of: "_API_KEY", with: "").capitalized): \(all[$0] == nil ? "✗" : "✓")" }
            .joined(separator: "  ")
    }
}
