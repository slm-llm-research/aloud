import Foundation
import Testing
@testable import InstructFlowCore

@Suite("Data migration from Murmur")
struct DataMigrationTests {
    let fm = FileManager.default

    func tempDir() -> URL {
        let url = fm.temporaryDirectory.appendingPathComponent("if-migrate-\(UUID().uuidString)")
        try! fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func copiesFilesAndKeepsKeysPrivate() throws {
        let root = tempDir()
        let old = root.appendingPathComponent("Murmur"), new = root.appendingPathComponent("InstructFlow")
        try fm.createDirectory(at: old, withIntermediateDirectories: true)
        try "GROQ_API_KEY=x\n".write(to: old.appendingPathComponent("keys.env"), atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: old.appendingPathComponent("keys.env").path)
        try "agent d -> agentd\n".write(to: old.appendingPathComponent("dictionary.txt"), atomically: true, encoding: .utf8)

        let copied = try DataMigration.migrate(from: old, to: new)
        #expect(copied == ["dictionary.txt", "keys.env"])
        #expect(try String(contentsOf: new.appendingPathComponent("dictionary.txt"), encoding: .utf8) == "agent d -> agentd\n")
        let mode = try fm.attributesOfItem(atPath: new.appendingPathComponent("keys.env").path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
        #expect(fm.fileExists(atPath: old.appendingPathComponent("keys.env").path))  // old copy left alone
    }

    @Test func neverOverwritesAnExistingNewFolder() throws {
        let root = tempDir()
        let old = root.appendingPathComponent("Murmur"), new = root.appendingPathComponent("InstructFlow")
        try fm.createDirectory(at: old, withIntermediateDirectories: true)
        try fm.createDirectory(at: new, withIntermediateDirectories: true)
        try "old".write(to: old.appendingPathComponent("keys.env"), atomically: true, encoding: .utf8)
        #expect(try DataMigration.migrate(from: old, to: new).isEmpty)
        #expect(!fm.fileExists(atPath: new.appendingPathComponent("keys.env").path))
    }

    @Test func nothingToDoWithoutAnOldFolder() throws {
        let root = tempDir()
        #expect(try DataMigration.migrate(from: root.appendingPathComponent("Murmur"),
                                          to: root.appendingPathComponent("InstructFlow")).isEmpty)
        #expect(!fm.fileExists(atPath: root.appendingPathComponent("InstructFlow").path))
    }

    @Test func skipsSubfolders() throws {
        let root = tempDir()
        let old = root.appendingPathComponent("Murmur"), new = root.appendingPathComponent("InstructFlow")
        try fm.createDirectory(at: old.appendingPathComponent("cache"), withIntermediateDirectories: true)
        try "{}".write(to: old.appendingPathComponent("agent.json"), atomically: true, encoding: .utf8)
        #expect(try DataMigration.migrate(from: old, to: new) == ["agent.json"])
    }
}
