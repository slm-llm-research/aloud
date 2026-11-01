import Foundation

/// Plain-text log at ~/Library/Logs/Aloud/aloud.log, so problems can be diagnosed with `tail`
/// (unified-log `info` messages aren't persisted). Local only; includes transcripts, which helps
/// fix misrecognized words. Rotated at 2 MB.
final class DiagLog: @unchecked Sendable {
    static let shared = DiagLog()

    let url: URL
    private let queue = DispatchQueue(label: "aloud.diaglog")
    private let formatter: ISO8601DateFormatter

    private init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Aloud")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("aloud.log")
        formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func write(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(message)\n"
        queue.async { [url] in
            if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int,
               size > 2_000_000 {
                try? FileManager.default.removeItem(at: url.appendingPathExtension("old"))
                try? FileManager.default.moveItem(at: url, to: url.appendingPathExtension("old"))
            }
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile()
                h.write(Data(line.utf8))
                try? h.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }
}

func dlog(_ message: String) { DiagLog.shared.write(message) }

/// One JSON line per dictation at ~/Library/Logs/Aloud/dictations.jsonl: what was heard, what
/// was typed, where, and how long it took. The scenario eval harness (bench/scenario_eval.py) reads it;
/// local only, same contents as the "heard/typed" lines in the log. Rotated at 5 MB.
enum DictationRecord {
    static let url = DiagLog.shared.url.deletingLastPathComponent().appendingPathComponent("dictations.jsonl")
    private static let queue = DispatchQueue(label: "aloud.dictations")

    static func append(_ fields: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]) else { return }
        queue.async {
            if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int, size > 5_000_000 {
                try? FileManager.default.removeItem(at: url.appendingPathExtension("old"))
                try? FileManager.default.moveItem(at: url, to: url.appendingPathExtension("old"))
            }
            let line = data + Data("\n".utf8)
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile()
                h.write(line)
                try? h.close()
            } else {
                try? line.write(to: url)
            }
        }
    }
}
