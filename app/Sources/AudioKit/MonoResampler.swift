import AVFoundation

/// Converts whatever the input device delivers (often 48 kHz, sometimes stereo) into 16 kHz mono
/// Float32, the format every STT engine here expects.
public final class MonoResampler {
    public let inputFormat: AVAudioFormat
    public let outputFormat: AVAudioFormat
    private let converter: AVAudioConverter

    public init?(inputFormat: AVAudioFormat) {
        guard let out = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: SampleBuffer.sampleRate,
                                      channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inputFormat, to: out)
        else { return nil }
        self.inputFormat = inputFormat
        self.outputFormat = out
        self.converter = converter
    }

    public func convert(_ buffer: AVAudioPCMBuffer) -> [Float] {
        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return [] }

        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            // Hand the converter exactly one input buffer per call; it keeps its own filter state
            // between calls, so chunk boundaries don't click.
            if fed {
                status.pointee = .noDataNow
                return nil
            }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let data = out.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(out.frameLength)))
    }
}
