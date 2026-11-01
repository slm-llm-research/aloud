import Foundation
import HotkeyKit

// The pieces a session drives. Real implementations live in AudioKit / STTKit / InsertKit /
// CleanupKit and are adapted in the app target; tests use fakes.

public protocol AudioCapturing: AnyObject, Sendable {
    /// Called on the audio thread with each new chunk of 16 kHz mono samples while capturing.
    var onSamples: (@Sendable ([Float]) -> Void)? { get set }
    func begin() throws
    /// Returns 16 kHz mono samples (empty when discarding).
    @discardableResult
    func end(discard: Bool) -> [Float]
}

/// Batch (whole-clip) speech-to-text, e.g. local Parakeet.
public protocol Transcribing: Sendable {
    func transcribe(_ samples: [Float]) async throws -> String
}

/// One streaming cloud recognition, opened when the key goes down.
public protocol StreamingSTTSession: AnyObject, Sendable {
    /// Audio-thread safe.
    func feed(_ samples: [Float])
    /// Key-up: flush, commit, and return the final transcript.
    func finish() async throws -> String
    func cancel()
    /// One line for the log after `finish()` (segments received, whether the final one arrived).
    var diagnostics: String { get }
}

extension StreamingSTTSession {
    public var diagnostics: String { "" }
}

public protocol StreamingSTTProvider: Sendable {
    /// nil when streaming is unavailable (no key, offline mode).
    func open() -> StreamingSTTSession?
}

public struct CleanupOutcome: Equatable, Sendable {
    public var text: String
    /// "skipped", "groq", "haiku", "fallback", ... for the log.
    public var via: String
    public init(text: String, via: String) {
        self.text = text
        self.via = via
    }
}

/// The app the text is going to, captured at key-up.
public struct DictationContext: Equatable, Sendable {
    public var bundleID: String?
    public var appName: String?
    public var windowTitle: String?
    public init(bundleID: String? = nil, appName: String? = nil, windowTitle: String? = nil) {
        self.bundleID = bundleID
        self.appName = appName
        self.windowTitle = windowTitle
    }
}

public protocol TextCleaning: Sendable {
    func clean(_ text: String, context: DictationContext) async -> CleanupOutcome
}

@MainActor
public protocol TextInserting: AnyObject {
    func insert(_ text: String) async -> Bool
}

/// Where task-mode utterances go. The agent daemon (M6) will implement this; until then the app
/// just reports that task mode isn't available yet.
@MainActor
public protocol TaskSubmitting: AnyObject {
    /// Returns false if the agent couldn't take the task (not running).
    func submit(task: String, context: DictationContext) async -> Bool
}

/// What the HUD shows.
public enum SessionStatus: Equatable, Sendable {
    case idle
    case listening(RecordingMode)
    case transcribing
    case inserted(String)
    case failed(String)
}

public struct SessionEvent: Equatable, Sendable {
    public var mode: RecordingMode
    public var audioSeconds: Double
    public var rawTranscript: String
    public var transcript: String
    public var sttSource: TranscriptSource
    public var cleanupVia: String
    public var context: DictationContext
    /// Key-up to final transcript.
    public var sttLatency: Duration
    /// Key-up to text handed to the target app (before clipboard restore).
    public var latency: Duration
    /// Cloud stream details for the log ("segments=3 early=2 final=yes"); empty without a stream.
    public var sttNotes: String = ""
}

/// The cloud session for the recording in progress, shared with the audio thread.
private final class StreamSlot: @unchecked Sendable {
    private let lock = NSLock()
    private var session: StreamingSTTSession?

    func set(_ s: StreamingSTTSession?) {
        lock.lock()
        session = s
        lock.unlock()
    }

    func take() -> StreamingSTTSession? {
        lock.lock()
        defer { lock.unlock() }
        let s = session
        session = nil
        return s
    }

    func feed(_ samples: [Float]) {
        lock.lock()
        let s = session
        lock.unlock()
        s?.feed(samples)
    }
}

/// Turns hotkey actions into record -> transcribe (cloud/local race) -> clean -> insert
/// (PLAN.md §1). One session at a time: a press while the previous one is still processing is
/// ignored rather than interleaved.
@MainActor
public final class Session {
    /// Recordings shorter than this are almost always accidental presses; don't transcribe them.
    public static let minimumAudioSeconds = 0.3
    /// Extra cloud wait per second of audio beyond 10 s, capped: the final segment of a long
    /// dictation takes longer, and losing the race there means the local engine's long-clip output.
    nonisolated static func raceWindow(base: Duration, audioSeconds: Double) -> Duration {
        base + .milliseconds(Int(min(350, max(0, (audioSeconds - 10) * 10))))
    }

    private let audio: AudioCapturing
    private let transcriber: Transcribing
    private let inserter: TextInserting
    private let streaming: StreamingSTTProvider?
    private let cleaner: TextCleaning?
    private let tasks: TaskSubmitting?
    private let raceWindow: Duration
    /// Keep recording this long after key-up: the last word is often still being said, and the tap
    /// and hardware buffers hold ~20-100 ms that stopping the engine would discard (BUG-001 H4).
    private let tailPad: Duration
    /// Reads the focused app (main actor, at key-up). Nil in tests that don't care.
    private let contextProvider: (@MainActor () -> DictationContext)?
    private let clock = ContinuousClock()
    private let slot = StreamSlot()

    public private(set) var status: SessionStatus = .idle {
        didSet { onStatus?(status) }
    }
    public var onStatus: ((SessionStatus) -> Void)?
    public var onCompleted: ((SessionEvent) -> Void)?

    private var capturing = false
    private var busy = false
    private(set) var mode: RecordingMode = .dictation

    public init(audio: AudioCapturing, transcriber: Transcribing, inserter: TextInserting,
                streaming: StreamingSTTProvider? = nil, cleaner: TextCleaning? = nil,
                tasks: TaskSubmitting? = nil, raceWindow: Duration = .milliseconds(250),
                tailPad: Duration = .milliseconds(120),
                contextProvider: (@MainActor () -> DictationContext)? = nil) {
        self.audio = audio
        self.transcriber = transcriber
        self.inserter = inserter
        self.streaming = streaming
        self.cleaner = cleaner
        self.tasks = tasks
        self.raceWindow = raceWindow
        self.tailPad = tailPad
        self.contextProvider = contextProvider
        audio.onSamples = { [slot] samples in slot.feed(samples) }
    }

    /// Feed every `HotkeyAction` here, on the main actor. Returns the work started by `.finish` so
    /// callers (and tests) can await it.
    @discardableResult
    public func handle(_ action: HotkeyAction) -> Task<Void, Never>? {
        switch action {
        case .armPreroll:
            guard !busy, !capturing else { return nil }
            // Open the cloud stream first so it is connecting while the user starts to speak.
            slot.set(streaming?.open())
            do {
                try audio.begin()
                capturing = true
            } catch {
                slot.take()?.cancel()
                status = .failed("Microphone unavailable")
            }
            return nil
        case .startRecording(let m), .changeMode(let m):
            guard capturing else { return nil }
            mode = m
            status = .listening(m)
            return nil
        case .cancel:
            guard capturing else { return nil }
            audio.end(discard: true)
            slot.take()?.cancel()
            capturing = false
            status = .idle
            return nil
        case .finish(let m):
            guard capturing else { return nil }
            let keyUp = clock.now
            // Where the text will go: read now, while the target app is surely still in front.
            let context = contextProvider?() ?? DictationContext()
            capturing = false
            busy = true
            return Task {
                if self.tailPad > .zero { try? await Task.sleep(for: self.tailPad) }
                let samples = self.audio.end(discard: false)
                let cloud = self.slot.take()
                await self.process(samples, cloud: cloud, mode: m, context: context, keyUp: keyUp)
            }
        }
    }

    private func process(_ samples: [Float], cloud: StreamingSTTSession?, mode: RecordingMode,
                         context: DictationContext, keyUp: ContinuousClock.Instant) async {
        defer { busy = false }
        let seconds = Double(samples.count) / 16_000
        guard seconds >= Self.minimumAudioSeconds else {
            cloud?.cancel()
            status = .idle
            return
        }
        status = .transcribing

        let outcome: STTRace.Outcome
        do {
            let transcriber = self.transcriber
            var cloudFinish: (@Sendable () async throws -> String)?
            if let cloud { cloudFinish = { try await cloud.finish() } }
            outcome = try await STTRace.run(
                cloud: cloudFinish,
                local: { try await transcriber.transcribe(samples) },
                window: Self.raceWindow(base: raceWindow, audioSeconds: seconds))
        } catch {
            status = .failed("Transcription failed")
            return
        }
        let sttLatency = clock.now - keyUp
        let raw = outcome.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            status = .idle
            return
        }

        let cleaned = await cleaner?.clean(raw, context: context) ?? CleanupOutcome(text: raw, via: "none")
        let text = cleaned.text.isEmpty ? raw : cleaned.text

        var insertedAt = clock.now
        switch mode {
        case .dictation, .command:
            // Command mode (edit selection) arrives in M5; until then it dictates.
            let ok = await inserter.insert(text)
            insertedAt = clock.now
            status = ok ? .inserted(text) : .failed("Couldn't type into this app; text is on the clipboard")
        case .task:
            if let tasks {
                let accepted = await tasks.submit(task: text, context: context)
                status = accepted ? .idle : .failed("Agent isn't running (see the InstructFlow menu)")
            } else {
                status = .failed("Task mode isn't built yet (milestone 6)")
            }
            insertedAt = clock.now
        }
        onCompleted?(SessionEvent(mode: mode, audioSeconds: seconds, rawTranscript: raw, transcript: text,
                                  sttSource: outcome.source, cleanupVia: cleaned.via, context: context,
                                  sttLatency: sttLatency, latency: insertedAt - keyUp,
                                  sttNotes: cloud?.diagnostics ?? ""))
    }
}
