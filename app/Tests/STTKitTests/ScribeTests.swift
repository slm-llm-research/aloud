import AVFoundation
import Foundation
import Testing
@testable import STTKit

@Suite("Scribe wire format")
struct ScribeProtocolTests {
    @Test func urlCarriesManualCommitAndKeyterms() throws {
        let url = ScribeProtocol.url(keyterms: ["Claude Code", "FastAPI"])
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(url.host == "api.elevenlabs.io")
        #expect(items.contains(URLQueryItem(name: "model_id", value: "scribe_v2_realtime")))
        #expect(items.contains(URLQueryItem(name: "commit_strategy", value: "manual")))
        #expect(items.contains(URLQueryItem(name: "audio_format", value: "pcm_16000")))
        #expect(items.filter { $0.name == "keyterms" }.map(\.value) == ["Claude Code", "FastAPI"])
    }

    @Test func keytermsAreCappedAt50() throws {
        let url = ScribeProtocol.url(keyterms: (0..<80).map { "t\($0)" })
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.filter { $0.name == "keyterms" }.count == 50)
    }

    @Test func pcm16IsLittleEndianAndClipped() {
        let d = ScribeProtocol.pcm16([0, 1, -1, 2])
        #expect(d.count == 8)
        let v = d.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }.map { Int16(littleEndian: $0) }
        #expect(v == [0, 32767, -32767, 32767])
    }

    @Test func audioMessageShape() throws {
        let msg = ScribeProtocol.audioMessage([0, 0], commit: true)
        let json = try #require(JSONSerialization.jsonObject(with: Data(msg.utf8)) as? [String: Any])
        #expect(json["message_type"] as? String == "input_audio_chunk")
        #expect(json["commit"] as? Bool == true)
        #expect(json["sample_rate"] as? Int == 16_000)
        #expect(json["audio_base_64"] as? String == "AAAAAA==")
    }

    @Test func parsesServerEvents() {
        #expect(ScribeProtocol.parse(#"{"message_type":"session_started","session_id":"x"}"#) == .started)
        #expect(ScribeProtocol.parse(#"{"message_type":"partial_transcript","text":"hel"}"#) == .partial("hel"))
        #expect(ScribeProtocol.parse(#"{"message_type":"committed_transcript","text":"Hello."}"#) == .committed("Hello."))
        #expect(ScribeProtocol.parse(#"{"message_type":"auth_error","message":"bad key"}"#)
                == .error(type: "auth_error", message: "bad key"))
        #expect(ScribeProtocol.parse(#"{"message_type":"quota_exceeded"}"#) == .error(type: "quota_exceeded", message: ""))
        #expect(ScribeProtocol.parse("not json") == .other("unparseable"))
    }
}

/// ALOUD_INTEGRATION=1 ELEVENLABS_API_KEY=... swift test --filter ScribeLive
@Suite("ScribeLive", .enabled(if: ProcessInfo.processInfo.environment["ALOUD_INTEGRATION"] == "1"
                               && ProcessInfo.processInfo.environment["ELEVENLABS_API_KEY"] != nil))
struct ScribeLiveTests {
    @Test func streamsAtRealTimeAndCommitsOnKeyUp() async throws {
        let audio = try ParakeetIntegrationTests.samples("libri_121-127105-0036.wav")
        let s = ScribeRealtimeSession(apiKey: ProcessInfo.processInfo.environment["ELEVENLABS_API_KEY"]!, keyterms: [])
        // Feed like the mic does: 20 ms chunks at real-time pace.
        for start in stride(from: 0, to: audio.count, by: 320) {
            s.feed(Array(audio[start..<min(start + 320, audio.count)]))
            try await Task.sleep(for: .milliseconds(20))
        }
        let clock = ContinuousClock()
        let t0 = clock.now
        let text = try await s.finish()
        let elapsed = clock.now - t0
        #expect(ParakeetIntegrationTests.words(text) == ParakeetIntegrationTests.words("but was that all her reward one of the ladies asked"))
        #expect(elapsed < .seconds(1), "commit -> final took \(elapsed)")
        print("scribe realtime: commit->final \(elapsed) -> \(text)")
    }

    @Test func badKeyFailsInsteadOfHanging() async throws {
        let s = ScribeRealtimeSession(apiKey: "invalid", keyterms: [])
        s.feed([Float](repeating: 0, count: 3_200))
        await #expect(throws: (any Error).self) {
            try await withThrowingTaskGroup(of: String.self) { g in
                g.addTask { try await s.finish() }
                g.addTask {
                    try await Task.sleep(for: .seconds(5))
                    throw CancellationError()
                }
                let r = try await g.next()!
                g.cancelAll()
                return r
            }
        }
    }
}
