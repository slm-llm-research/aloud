import AVFoundation
import Foundation
import Testing
@testable import STTKit

/// Real-model checks against clips from the M0 benchmark set (bench/data/audio).
/// Run with: ALOUD_INTEGRATION=1 swift test --filter STTKitTests
// Serialized: parallel tests would download/load the same model files at once and corrupt them.
@Suite("Parakeet (integration)", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["ALOUD_INTEGRATION"] == "1"))
struct ParakeetIntegrationTests {
    static let audioDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().appendingPathComponent("../../../bench/data/audio").standardized

    static func samples(_ name: String) throws -> [Float] {
        let file = try AVAudioFile(forReading: audioDir.appendingPathComponent(name))
        let buf = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buf)
        #expect(file.processingFormat.sampleRate == 16_000)
        return Array(UnsafeBufferPointer(start: buf.floatChannelData![0], count: Int(buf.frameLength)))
    }

    static func words(_ s: String) -> [String] {
        s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    @Test func transcribesProseAccuratelyAndFast() async throws {
        let engine = ParakeetTranscriber()
        try await engine.prepare()
        _ = try await engine.transcribe([Float](repeating: 0, count: 16_000))  // warm-up

        // LibriSpeech 121-127105-0036: "but was that all her reward one of the ladies asked"
        let audio = try Self.samples("libri_121-127105-0036.wav")
        let clock = ContinuousClock()
        let start = clock.now
        let text = try await engine.transcribe(audio)
        let elapsed = clock.now - start

        #expect(Self.words(text) == Self.words("but was that all her reward one of the ladies asked"))
        // M0 (MLX/GPU) measured ~175 ms for this clip; leave headroom for a cold ANE.
        #expect(elapsed < .milliseconds(1_000), "took \(elapsed)")
        print("parakeet/fluidaudio: \(elapsed) for \(Double(audio.count) / 16_000) s -> \(text)")
    }

    @Test func technicalSentence() async throws {
        let engine = ParakeetTranscriber()
        let text = try await engine.transcribe(try Self.samples("tech02.wav"))
        // The identifier is the part that matters (M0: MLX Parakeet got "useState" right here).
        #expect(text.contains("useState") || text.lowercased().contains("use state"), "\(text)")
    }
}
