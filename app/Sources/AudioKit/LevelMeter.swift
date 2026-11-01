import Foundation

/// The microphone's current loudness, 0 (silence) to 1 (loud speech), for the listening indicator.
/// The audio thread writes it once per tap; the UI reads it every frame.
public final class LevelMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Float = 0

    public init() {}

    public var value: Float {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    public func push(_ samples: [Float]) {
        let v = Self.normalized(samples)
        lock.lock()
        current = v
        lock.unlock()
    }

    public func reset() {
        lock.lock()
        current = 0
        lock.unlock()
    }

    /// RMS in dBFS mapped so -55 dB (room noise) is 0 and -12 dB (close, loud speech) is 1.
    public static func normalized(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for s in samples { sum += s * s }
        let rms = (sum / Float(samples.count)).squareRoot()
        guard rms > 0 else { return 0 }
        let db = 20 * log10(rms)
        return min(1, max(0, (db + 55) / 43))
    }
}
