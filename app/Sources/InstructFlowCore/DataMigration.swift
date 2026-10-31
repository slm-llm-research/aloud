import Foundation

/// Carries settings over from the app's old name (Murmur) on first launch as InstructFlow:
/// keys.env, dictionary.txt and agent.json. Runs only when the new folder doesn't exist yet,
/// so it never overwrites anything. Sockets and other non-regular files are skipped.
public enum DataMigration {
    /// Returns the names of the files copied (empty if there was nothing to do).
    @discardableResult
    public static func migrate(from old: URL, to new: URL, fileManager fm: FileManager = .default) throws -> [String] {
        guard !fm.fileExists(atPath: new.path), fm.fileExists(atPath: old.path) else { return [] }
        try fm.createDirectory(at: new, withIntermediateDirectories: true)
        var copied: [String] = []
        for name in try fm.contentsOfDirectory(atPath: old.path).sorted() {
            let src = old.appendingPathComponent(name)
            let attrs = try fm.attributesOfItem(atPath: src.path)
            guard attrs[.type] as? FileAttributeType == .typeRegular else { continue }
            let dst = new.appendingPathComponent(name)
            try fm.copyItem(at: src, to: dst)
            // Keep owner-only files owner-only (keys.env is 0600).
            if let mode = attrs[.posixPermissions] { try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: dst.path) }
            copied.append(name)
        }
        return copied
    }
}
