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

/// One push-to-talk recognition over a WebSocket. Opened on key-down; audio is fed while the key is
/// held (batched into ~100 ms messages); `finish()` sends the commit and waits for the transcript.
public final class ScribeRealtimeSession: @unchecked Sendable {
    static let chunkSamples = 1_600  // 100 ms at 16 kHz

    private let task: URLSessionWebSocketTask
    private let lock = NSLock()
    private var pending: [Float] = []
    private var committed: [String] = []
    private var waiter: CheckedContinuation<String, Error>?
    private var failure: Error?
    private var finished = false

    public init(apiKey: String, keyterms: [String], session: URLSession = .shared) {
        var req = URLRequest(url: ScribeProtocol.url(keyterms: keyterms))
        req.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        task = session.webSocketTask(with: req)
        task.resume()
        receive()
    }

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

    /// Marks the session finished and returns the not-yet-sent audio (sync: NSLock isn't async-safe).
    private func takeTail() throws -> [Float] {
        try lock.withLock {
            let tail = pending
            pending = []
            finished = true
            if let failure { throw failure }
            return tail
        }
    }

    public func finish() async throws -> String {
        let tail = try takeTail()
        // The commit rides on the last audio message; an empty tail still needs one message to carry it.
        send(ScribeProtocol.audioMessage(tail.isEmpty ? [Float](repeating: 0, count: 160) : tail, commit: true))

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
                lock.lock()
                if let failure {
                    lock.unlock()
                    cont.resume(throwing: failure)
                } else if !committed.isEmpty {
                    let text = committed.joined(separator: " ")
                    lock.unlock()
                    cont.resume(returning: text)
                } else {
                    waiter = cont
                    lock.unlock()
                }
            }
        } onCancel: {
            self.cancel()
        }
    }

    public func cancel() {
        fail(ScribeError.cancelled)
        task.cancel(with: .goingAway, reason: nil)
    }

    private func send(_ text: String) {
        task.send(.string(text)) { [weak self] error in
            if let error { self?.fail(error) }
        }
    }

    private func receive() {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.fail(error)
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
            lock.lock()
            committed.append(text)
            let w = finished ? waiter : nil
            if w != nil { waiter = nil }
            let all = committed.joined(separator: " ")
            lock.unlock()
            if let w {
                w.resume(returning: all)
                task.cancel(with: .normalClosure, reason: nil)
            }
        case .error(let type, let message):
            fail(ScribeError.server("\(type): \(message)"))
        case .started, .partial, .other:
            break
        }
    }

    private func fail(_ error: Error) {
        lock.lock()
        if failure == nil { failure = error }
        let w = waiter
        waiter = nil
        lock.unlock()
        w?.resume(throwing: error)
    }
}
