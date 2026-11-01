import Foundation

/// Wire format for ElevenLabs Scribe v2 Realtime (wss://api.elevenlabs.io/v1/speech-to-text/realtime).
/// Pure functions, unit-tested; `ScribeRealtimeSession` does the networking.
public enum ScribeProtocol {
    public static func url(keyterms: [String], language: String = "en") -> URL {
        var c = URLComponents(string: "wss://api.elevenlabs.io/v1/speech-to-text/realtime")!
        c.queryItems = [
            URLQueryItem(name: "model_id", value: "scribe_v2_realtime"),
            URLQueryItem(name: "audio_format", value: "pcm_16000"),
            // Push-to-talk: we decide when the utterance ends (key-up), not server VAD.
            URLQueryItem(name: "commit_strategy", value: "manual"),
            URLQueryItem(name: "language_code", value: language),
            // Scribe's own suppression of non-speech background sound.
            URLQueryItem(name: "filter_background_audio", value: "true"),
        ] + keyterms.prefix(50).map { URLQueryItem(name: "keyterms", value: $0) }
        return c.url!
    }

    /// Float32 [-1, 1] -> little-endian PCM16, the `pcm_16000` format.
    public static func pcm16(_ samples: [Float]) -> Data {
        var data = Data(capacity: samples.count * 2)
        for s in samples {
            let v = Int16(max(-1, min(1, s)) * Float(Int16.max))
            withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }

    public static func audioMessage(_ samples: [Float], commit: Bool) -> String {
        let json: [String: Any] = [
            "message_type": "input_audio_chunk",
            "audio_base_64": pcm16(samples).base64EncodedString(),
            "commit": commit,
            "sample_rate": 16_000,
        ]
        let data = try! JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    public enum ServerEvent: Equatable, Sendable {
        case started
        case partial(String)
        case committed(String)
        case error(type: String, message: String)
        case other(String)
    }

    public static func parse(_ text: String) -> ServerEvent {
        guard let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let type = json["message_type"] as? String
        else { return .other("unparseable") }
        switch type {
        case "session_started": return .started
        case "partial_transcript": return .partial(json["text"] as? String ?? "")
        case "committed_transcript", "committed_transcript_with_timestamps":
            return .committed(json["text"] as? String ?? "")
        case "warning": return .other("warning")
        default:
            if type.contains("error") || ["quota_exceeded", "commit_throttled", "unaccepted_terms", "rate_limited",
                                          "queue_overflow", "resource_exhausted", "session_time_limit_exceeded",
                                          "invalid_request", "chunk_size_exceeded", "insufficient_audio_activity"]
                .contains(type) {
                let msg = (json["message"] as? String) ?? (json["error"] as? String) ?? ""
                return .error(type: type, message: msg)
            }
            return .other(type)
        }
    }
}

public enum ScribeError: Error, Equatable {
    case server(String)
    case closed
    case cancelled
}

/// The transcript side of one Scribe session: collects committed segments and decides when the
/// result is complete. Pure state (no networking) so the commit ordering is unit-tested.
///
/// Scribe can commit segments on its own while the key is held (long dictations are split at
/// pauses even with `commit_strategy=manual`). The result is only complete once the segment for
/// *our* final commit has arrived; returning the earlier segments then drops the last words
/// (BUG-001).
final class ScribeTranscript: @unchecked Sendable {
    private let lock = NSLock()
    private var segments: [String] = []
    private var waiter: CheckedContinuation<String, Error>?
    private var failure: Error?
    private(set) var finished = false
    private var earlyCommits = 0
    private var finalReceived = false
    private var timedOut = false

    var text: String { lock.withLock { joined() } }

    private func joined() -> String {
        segments.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Key-up: no more audio. Throws an earlier failure.
    func markFinished() throws {
        try lock.withLock {
            finished = true
            if let failure { throw failure }
        }
    }

    /// Waits for the segment that follows the final commit.
    func wait(_ cont: CheckedContinuation<String, Error>) {
        lock.lock()
        if let failure {
            lock.unlock()
            cont.resume(throwing: failure)
        } else if finalReceived {
            let t = joined()
            lock.unlock()
            cont.resume(returning: t)
        } else {
            waiter = cont
            lock.unlock()
        }
    }

    /// A `committed_transcript`. Returns true when this completed the result.
    @discardableResult
    func committed(_ segment: String) -> Bool {
        lock.lock()
        segments.append(segment)
        guard finished else {
            earlyCommits += 1
            lock.unlock()
            return false
        }
        finalReceived = true
        let w = waiter
        waiter = nil
        let t = joined()
        lock.unlock()
        w?.resume(returning: t)
        return true
    }

    /// The final segment never came: return what was committed, rather than nothing.
    func timeout() {
        lock.lock()
        guard let w = waiter else { return lock.unlock() }
        waiter = nil
        timedOut = true
        let t = joined()
        lock.unlock()
        if t.isEmpty { w.resume(throwing: ScribeError.closed) } else { w.resume(returning: t) }
    }

    func fail(_ error: Error) {
        lock.lock()
        if failure == nil { failure = error }
        let w = waiter
        waiter = nil
        lock.unlock()
        w?.resume(throwing: error)
    }

    /// For the log: "segments=3 early=2 final=yes".
    var diagnostics: String {
        lock.withLock {
            "segments=\(segments.count) early=\(earlyCommits) final=\(finalReceived ? "yes" : timedOut ? "timeout" : "no")"
        }
    }
}

/// One push-to-talk recognition over a WebSocket. Opened on key-down; audio is fed while the key is
/// held (batched into ~100 ms messages); `finish()` sends the commit and waits for the transcript.
public final class ScribeRealtimeSession: @unchecked Sendable {
    static let chunkSamples = 1_600  // 100 ms at 16 kHz
    /// How long to wait for the final segment after the commit before settling for what we have.
    static let finalSegmentTimeout: Duration = .seconds(3)

    private let task: URLSessionWebSocketTask
    private let lock = NSLock()
    private var pending: [Float] = []
    private let transcript = ScribeTranscript()

    public init(apiKey: String, keyterms: [String], session: URLSession = .shared) {
        var req = URLRequest(url: ScribeProtocol.url(keyterms: keyterms))
        req.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        task = session.webSocketTask(with: req)
        task.resume()
        receive()
    }

    /// For the log: how many segments arrived and whether the final one did.
    public var diagnostics: String { transcript.diagnostics }

    /// Audio thread: buffer and send in 100 ms messages (URLSession queues sends until connected).
    public func feed(_ samples: [Float]) {
        lock.lock()
        pending += samples
        var chunks: [[Float]] = []
        while pending.count >= Self.chunkSamples {
            chunks.append(Array(pending.prefix(Self.chunkSamples)))
            pending.removeFirst(Self.chunkSamples)
        }
        lock.unlock()
        for c in chunks { send(ScribeProtocol.audioMessage(c, commit: false)) }
    }

    /// Returns the not-yet-sent audio (sync: NSLock isn't async-safe).
    private func takeTail() -> [Float] {
        lock.withLock {
            let tail = pending
            pending = []
            return tail
        }
    }

    public func finish() async throws -> String {
        let tail = takeTail()
        try transcript.markFinished()
        // The commit rides on the last audio message; an empty tail still needs one message to carry it.
        send(ScribeProtocol.audioMessage(tail.isEmpty ? [Float](repeating: 0, count: 160) : tail, commit: true))

        let timer = Task { [transcript] in
            try await Task.sleep(for: Self.finalSegmentTimeout)
            transcript.timeout()
        }
        defer { timer.cancel() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
                transcript.wait(cont)
            }
        } onCancel: {
            self.cancel()
        }
    }

    public func cancel() {
        transcript.fail(ScribeError.cancelled)
        task.cancel(with: .goingAway, reason: nil)
    }

    private func send(_ text: String) {
        task.send(.string(text)) { [weak self] error in
            if let error { self?.transcript.fail(error) }
        }
    }

    private func receive() {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.transcript.fail(error)
            case .success(.string(let text)):
                self.handle(ScribeProtocol.parse(text))
                self.receive()
            case .success:
                self.receive()
            }
        }
    }

    private func handle(_ event: ScribeProtocol.ServerEvent) {
        switch event {
        case .committed(let text):
            if transcript.committed(text) { task.cancel(with: .normalClosure, reason: nil) }
        case .error(let type, let message):
            transcript.fail(ScribeError.server("\(type): \(message)"))
        case .started, .partial, .other:
            break
        }
    }
}
