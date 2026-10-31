import AVFoundation
import Testing
@testable import AudioKit

@Suite("SampleBuffer")
struct SampleBufferTests {
    @Test func appendAndDrain() {
        let b = SampleBuffer()
        b.append([1, 2, 3])
        b.append([4])
        #expect(b.drain() == [1, 2, 3, 4])
        #expect(b.drain().isEmpty)
    }

    @Test func durationIsInSeconds() {
        let b = SampleBuffer()
        b.append([Float](repeating: 0, count: 8_000))
        #expect(b.duration == 0.5)
    }

    @Test func capsAtMaxSeconds() {
        let b = SampleBuffer(maxSeconds: 1)
        b.append([Float](repeating: 0, count: 10_000))
        b.append([Float](repeating: 0, count: 10_000))
        #expect(b.drain().count == 16_000)
    }

    @Test func concurrentAppendsAreNotLost() async {
        let b = SampleBuffer()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<50 {
                group.addTask { b.append([Float](repeating: 1, count: 100)) }
            }
        }
        #expect(b.drain().count == 5_000)
    }
}

@Suite("MonoResampler")
struct MonoResamplerTests {
    /// A 48 kHz stereo sine, like a typical built-in mic delivers.
    func sine(seconds: Double, rate: Double = 48_000, channels: AVAudioChannelCount = 2,
              hz: Double = 440) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels)!
        let frames = AVAudioFrameCount(seconds * rate)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buf.frameLength = frames
        for ch in 0..<Int(channels) {
            for i in 0..<Int(frames) {
                buf.floatChannelData![ch][i] = Float(sin(2 * .pi * hz * Double(i) / rate)) * 0.5
            }
        }
        return buf
    }

    @Test func downsamples48kStereoTo16kMono() throws {
        let input = sine(seconds: 1)
        let r = try #require(MonoResampler(inputFormat: input.format))
        var out: [Float] = []
        // Feed in 1024-frame chunks, the way the input tap does.
        let chunk: AVAudioFrameCount = 1024
        var offset: AVAudioFrameCount = 0
        while offset < input.frameLength {
            let n = min(chunk, input.frameLength - offset)
            let part = AVAudioPCMBuffer(pcmFormat: input.format, frameCapacity: n)!
            part.frameLength = n
            for ch in 0..<2 {
                part.floatChannelData![ch].update(from: input.floatChannelData![ch] + Int(offset), count: Int(n))
            }
            out += r.convert(part)
            offset += n
        }
        #expect(r.outputFormat.sampleRate == 16_000)
        #expect(r.outputFormat.channelCount == 1)
        // One second in -> about 16,000 samples out (converter latency may hold back a few).
        #expect(abs(out.count - 16_000) < 200)
        // Signal survives: RMS of a 0.5-amplitude sine is ~0.35.
        let rms = sqrt(out.dropFirst(100).map { $0 * $0 }.reduce(0, +) / Float(out.count - 100))
        #expect(rms > 0.3 && rms < 0.4)
    }
}
