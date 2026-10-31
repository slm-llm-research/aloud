import FluidAudio
import Foundation

/// Local, offline speech-to-text: NVIDIA Parakeet TDT 0.6B v2 (English) on the Apple Neural Engine
/// via FluidAudio. M0 measured the same model at ~206 ms p50 / 1.4% WER on this Mac (MLX/GPU path).
///
/// The first `prepare()` downloads the CoreML model (~600 MB) to
/// ~/Library/Application Support/FluidAudio; later launches load it from disk.
public actor ParakeetTranscriber {
    private var manager: AsrManager?

    public init() {}

    public var isReady: Bool { manager != nil }

    public func prepare() async throws {
        if manager != nil { return }
        let models = try await AsrModels.downloadAndLoad(version: .v2)
        let m = AsrManager(config: .default)
        try await m.loadModels(models)
        manager = m
    }

    /// `samples`: 16 kHz mono Float32.
    public func transcribe(_ samples: [Float]) async throws -> String {
        if manager == nil { try await prepare() }
        guard let manager else { return "" }
        // Fresh decoder state per utterance: dictations are independent.
        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let result = try await manager.transcribe(samples, decoderState: &state)
        return result.text
    }
}
