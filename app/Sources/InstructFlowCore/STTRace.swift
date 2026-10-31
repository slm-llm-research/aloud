import Foundation

public enum TranscriptSource: String, Equatable, Sendable {
    case cloud, local
}

/// Picks between streaming cloud STT and local STT after key-up (PLAN.md §3.2).
///
/// Both start at key-up. The cloud result wins if it arrives within `window` (M0: Scribe Realtime
/// p95 = 203 ms, so 250 ms); otherwise local wins. Each side is the other's fallback on error or empty
/// text, so a dead network never loses a dictation and a local failure still gets the cloud answer.
public enum STTRace {
    public struct Outcome: Equatable, Sendable {
        public var text: String
        public var source: TranscriptSource
    }

    public enum RaceError: Error, Equatable {
        case bothFailed
    }

    public static func run(
        cloud: (@Sendable () async throws -> String)?,
        local: @escaping @Sendable () async throws -> String,
        window: Duration
    ) async throws -> Outcome {
        guard let cloud else {
            let text = try await local()
            return Outcome(text: text, source: .local)
        }

        let cloudTask = Task { try await cloud() }
        let localTask = Task { try await local() }

        // 1. Give the cloud `window` to answer. Not a task group: a group waits for *all* children,
        // and awaiting `cloudTask.result` can't be cancelled, so a slow cloud would stall us.
        let first: First = await withCheckedContinuation { cont in
            let once = Once()
            Task {
                let r = await cloudTask.result
                if once.claim() { cont.resume(returning: .cloud(r)) }
            }
            Task {
                try? await Task.sleep(for: window)
                if once.claim() { cont.resume(returning: .timeout) }
            }
        }
        if case .cloud(.success(let text)) = first, !isBlank(text) {
            localTask.cancel()
            return Outcome(text: text, source: .cloud)
        }

        // 2. Cloud was slow, failed, or empty: use local.
        if case .success(let text) = await localTask.result, !isBlank(text) {
            cloudTask.cancel()
            return Outcome(text: text, source: .local)
        }

        // 3. Local failed or was empty: take whatever the cloud eventually says.
        if case .success(let text) = await cloudTask.result {
            return Outcome(text: text, source: .cloud)
        }
        throw RaceError.bothFailed
    }

    static func isBlank(_ s: String) -> Bool {
        s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private enum First: Sendable {
        case cloud(Result<String, Error>)
        case timeout
    }

    /// Lets exactly one of several racers resume a continuation.
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var claimed = false
        func claim() -> Bool {
            lock.withLock {
                if claimed { return false }
                claimed = true
                return true
            }
        }
    }
}
