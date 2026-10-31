import Foundation

/// Thread-safe accumulator for 16 kHz mono Float32 samples. The audio thread appends; the session
/// drains when recording finishes.
public final class SampleBuffer: @unchecked Sendable {
    public static let sampleRate: Double = 16_000

    private let lock = NSLock()
    private var samples: [Float] = []
    private let maxSamples: Int

    /// `maxSeconds` bounds memory if a recording is never finished (e.g. a stuck latch).
    public init(maxSeconds: Double = 20 * 60) {
        maxSamples = Int(maxSeconds * Self.sampleRate)
        samples.reserveCapacity(Int(30 * Self.sampleRate))
    }

    public func append(_ chunk: [Float]) {
        lock.lock()
        defer { lock.unlock() }
        let room = maxSamples - samples.count
        if room <= 0 { return }
        samples.append(contentsOf: chunk.prefix(room))
    }

    /// Returns everything captured so far and empties the buffer.
    public func drain() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        let out = samples
        samples.removeAll(keepingCapacity: true)
        return out
    }

    public func clear() {
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    public var duration: Double {
        lock.lock()
        defer { lock.unlock() }
        return Double(samples.count) / Self.sampleRate
    }
}
