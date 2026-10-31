import AppKit
import AudioKit
import CleanupKit
import Foundation
import InsertKit
import InstructFlowCore
import STTKit

// Connect the real implementations to InstructFlowCore's protocols.

extension AudioRecorder: AudioCapturing {}

struct ParakeetAdapter: Transcribing {
    let engine: ParakeetTranscriber
    func transcribe(_ samples: [Float]) async throws -> String {
        try await engine.transcribe(samples)
    }
}

extension ScribeRealtimeSession: StreamingSTTSession {}

/// Opens a Scribe Realtime session per recording, unless offline or no key.
final class ScribeProvider: StreamingSTTProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var apiKey: String?
    private var keyterms: [String] = []
    private var enabled = true

    func configure(apiKey: String?, keyterms: [String], enabled: Bool) {
        lock.lock()
        self.apiKey = apiKey
        self.keyterms = keyterms
        self.enabled = enabled
        lock.unlock()
    }

    func open() -> StreamingSTTSession? {
        lock.lock()
        defer { lock.unlock() }
        guard enabled, let apiKey, !apiKey.isEmpty else { return nil }
        // The app is known when recording starts; chat apps add slang keyterms ("lol").
        let extra = ModeRouter.sttKeyterms(bundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        let terms = Array((keyterms + extra.filter { !keyterms.contains($0) }).prefix(50))
        return ScribeRealtimeSession(apiKey: apiKey, keyterms: terms)
    }
}

/// Holds the current Cleaner (rebuilt when keys, dictionary or offline mode change).
final class CleanerBox: TextCleaning, @unchecked Sendable {
    private let lock = NSLock()
    private var cleaner = Cleaner(chain: [])

    func set(_ c: Cleaner) {
        lock.lock()
        cleaner = c
        lock.unlock()
    }

    func clean(_ text: String, context: DictationContext) async -> CleanupOutcome {
        let c = lock.withLock { cleaner }
        let r = await c.clean(text, context: AppContext(bundleID: context.bundleID, appName: context.appName,
                                                        windowTitle: context.windowTitle))
        var tags: [String] = []
        if r.restructured { tags.append("restructured") }
        tags += r.notes
        return CleanupOutcome(text: r.text, via: r.via + " [" + tags.joined(separator: "; ") + "]")
    }
}

extension TextInserter: TextInserting {
    public func insert(_ text: String) async -> Bool {
        switch await insert(text) as InsertionResult {
        case .inserted, .empty: return true
        case .copiedToClipboard: return false
        }
    }
}
