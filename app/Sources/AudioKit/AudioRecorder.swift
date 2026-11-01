import AVFoundation

public enum AudioRecorderError: Error {
    case noInputDevice
    case unsupportedFormat
}

/// Captures the default input device into a `SampleBuffer`.
///
/// The engine is started on `begin()` (when the trigger is first pressed, i.e. pre-roll) and stopped
/// on `end()`, so the macOS mic indicator is only on while you might be talking.
public final class AudioRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let buffer = SampleBuffer()
    private var resampler: MonoResampler?
    private let lock = NSLock()
    private var running = false
    /// Each converted chunk, on the audio thread, as it arrives (feeds streaming STT).
    public var onSamples: (@Sendable ([Float]) -> Void)?
    /// Live loudness while recording (the listening indicator's waveform).
    public let meter = LevelMeter()

    public init() {}

    public func begin() throws {
        lock.lock()
        defer { lock.unlock() }
        if running { return }
        buffer.clear()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw AudioRecorderError.noInputDevice }
        guard let resampler = MonoResampler(inputFormat: format) else { throw AudioRecorderError.unsupportedFormat }
        self.resampler = resampler
        // ~20 ms taps at 48 kHz keep the tail latency at key-up small.
        let onSamples = self.onSamples
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [buffer, meter] pcm, _ in
            let samples = resampler.convert(pcm)
            buffer.append(samples)
            meter.push(samples)
            onSamples?(samples)
        }
        engine.prepare()
        try engine.start()
        running = true
    }

    /// Stops capture and returns the recorded 16 kHz mono samples (empty if `discard`).
    @discardableResult
    public func end(discard: Bool = false) -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        guard running else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        meter.reset()
        running = false
        let samples = buffer.drain()
        return discard ? [] : samples
    }
}
