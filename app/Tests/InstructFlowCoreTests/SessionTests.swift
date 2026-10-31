import Foundation
import HotkeyKit
import Testing
@testable import InstructFlowCore

final class FakeAudio: AudioCapturing, @unchecked Sendable {
    var onSamples: (@Sendable ([Float]) -> Void)?
    var began = 0
    var ended: [Bool] = []
    var samples: [Float]
    var failOnBegin = false

    init(seconds: Double = 2) { samples = [Float](repeating: 0.1, count: Int(seconds * 16_000)) }

    func begin() throws {
        if failOnBegin { throw NSError(domain: "mic", code: 1) }
        began += 1
        // Simulate the mic delivering audio while the key is held.
        onSamples?(Array(samples.prefix(1_600)))
    }

    func end(discard: Bool) -> [Float] {
        ended.append(discard)
        return discard ? [] : samples
    }
}

struct FakeTranscriber: Transcribing {
    var text = "hello world"
    var fail = false
    func transcribe(_ samples: [Float]) async throws -> String {
        if fail { throw NSError(domain: "stt", code: 1) }
        return text
    }
}

@MainActor
final class FakeInserter: TextInserting {
    var inserted: [String] = []
    var succeed = true
    func insert(_ text: String) async -> Bool {
        inserted.append(text)
        return succeed
    }
}

@MainActor
final class FakeTasks: TaskSubmitting {
    var submitted: [String] = []
    var accept = true
    func submit(task: String, context: DictationContext) async -> Bool {
        submitted.append(task)
        return accept
    }
}

@MainActor
@Suite("Session flow")
struct SessionTests {
    @Test func holdThenReleaseInsertsTranscript() async {
        let audio = FakeAudio(), ins = FakeInserter()
        let s = Session(audio: audio, transcriber: FakeTranscriber(), inserter: ins)
        s.handle(.armPreroll)
        s.handle(.startRecording(.dictation))
        #expect(s.status == .listening(.dictation))
        await s.handle(.finish(.dictation))?.value
        #expect(ins.inserted == ["hello world"])
        #expect(s.status == .inserted("hello world"))
        #expect(audio.ended == [false])
    }

    @Test func cancelDiscardsAndInsertsNothing() {
        let audio = FakeAudio(), ins = FakeInserter()
        let s = Session(audio: audio, transcriber: FakeTranscriber(), inserter: ins)
        s.handle(.armPreroll)
        s.handle(.cancel)
        #expect(audio.ended == [true])
        #expect(ins.inserted.isEmpty)
        #expect(s.status == .idle)
    }

    @Test func tooShortRecordingIsIgnored() async {
        let ins = FakeInserter()
        let s = Session(audio: FakeAudio(seconds: 0.1), transcriber: FakeTranscriber(), inserter: ins)
        s.handle(.armPreroll)
        await s.handle(.finish(.dictation))?.value
        #expect(ins.inserted.isEmpty)
        #expect(s.status == .idle)
    }

    @Test func blankTranscriptIsNotInserted() async {
        let ins = FakeInserter()
        let s = Session(audio: FakeAudio(), transcriber: FakeTranscriber(text: "  \n"), inserter: ins)
        s.handle(.armPreroll)
        await s.handle(.finish(.dictation))?.value
        #expect(ins.inserted.isEmpty)
    }

    @Test func transcriptionFailureIsReported() async {
        let ins = FakeInserter()
        let s = Session(audio: FakeAudio(), transcriber: FakeTranscriber(fail: true), inserter: ins)
        s.handle(.armPreroll)
        await s.handle(.finish(.dictation))?.value
        #expect(ins.inserted.isEmpty)
        #expect(s.status == .failed("Transcription failed"))
    }

    @Test func micFailureIsReportedAndNothingElseHappens() async {
        let audio = FakeAudio()
        audio.failOnBegin = true
        let ins = FakeInserter()
        let s = Session(audio: audio, transcriber: FakeTranscriber(), inserter: ins)
        s.handle(.armPreroll)
        #expect(s.status == .failed("Microphone unavailable"))
        #expect(s.handle(.finish(.dictation)) == nil)
        #expect(ins.inserted.isEmpty)
    }

    @Test func taskModeGoesToTaskSubmitterNotTheTextField() async {
        let ins = FakeInserter(), tasks = FakeTasks()
        let s = Session(audio: FakeAudio(), transcriber: FakeTranscriber(text: "run the tests"),
                        inserter: ins, tasks: tasks)
        s.handle(.armPreroll)
        s.handle(.startRecording(.task))
        await s.handle(.finish(.task))?.value
        #expect(tasks.submitted == ["run the tests"])
        #expect(ins.inserted.isEmpty)
    }

    @Test func taskModeWithoutAgentNeverTypesTheTask() async {
        let ins = FakeInserter()
        let s = Session(audio: FakeAudio(), transcriber: FakeTranscriber(text: "delete my downloads"), inserter: ins)
        s.handle(.armPreroll)
        await s.handle(.finish(.task))?.value
        #expect(ins.inserted.isEmpty)
        if case .failed = s.status {} else { Issue.record("expected a failure status, got \(s.status)") }
    }

    @Test func pressDuringTranscriptionIsIgnored() async {
        let audio = FakeAudio(), ins = FakeInserter()
        let s = Session(audio: audio, transcriber: FakeTranscriber(), inserter: ins)
        s.handle(.armPreroll)
        let work = s.handle(.finish(.dictation))
        s.handle(.armPreroll)  // second press while the first is still processing
        await work?.value
        #expect(audio.began == 1)
        #expect(ins.inserted.count == 1)
    }

    @Test func completionReportsLatencyAndDuration() async {
        let s = Session(audio: FakeAudio(seconds: 2), transcriber: FakeTranscriber(), inserter: FakeInserter())
        var events: [SessionEvent] = []
        s.onCompleted = { events.append($0) }
        s.handle(.armPreroll)
        await s.handle(.finish(.dictation))?.value
        #expect(events.count == 1)
        #expect(events[0].audioSeconds == 2)
        #expect(events[0].latency < .seconds(1))
    }

    /// The real wiring: HotkeyMachine output drives the session end to end.
    @Test func hotkeyMachineDrivesSession() async {
        var m = HotkeyMachine()
        let ins = FakeInserter()
        let s = Session(audio: FakeAudio(), transcriber: FakeTranscriber(), inserter: ins)
        var work: [Task<Void, Never>] = []
        for input in [HotkeyInput.triggerDown(0), .timer(0.25), .triggerUp(2)] {
            for a in m.handle(input).actions { if let t = s.handle(a) { work.append(t) } }
        }
        for t in work { await t.value }
        #expect(ins.inserted == ["hello world"])
    }
}

final class FakeStream: StreamingSTTSession, @unchecked Sendable {
    var fed = 0
    var cancelled = false
    var result: Result<String, Error>
    var delay: Duration
    init(_ result: Result<String, Error>, delay: Duration = .milliseconds(5)) {
        self.result = result
        self.delay = delay
    }
    func feed(_ samples: [Float]) { fed += samples.count }
    func finish() async throws -> String {
        try await Task.sleep(for: delay)
        return try result.get()
    }
    func cancel() { cancelled = true }
}

final class FakeStreamProvider: StreamingSTTProvider, @unchecked Sendable {
    var opened: [FakeStream] = []
    let make: () -> FakeStream
    init(_ make: @escaping () -> FakeStream) { self.make = make }
    func open() -> StreamingSTTSession? {
        let s = make()
        opened.append(s)
        return s
    }
}

final class FakeCleaner: TextCleaning, @unchecked Sendable {
    var contexts: [DictationContext] = []
    func clean(_ text: String, context: DictationContext) async -> CleanupOutcome {
        contexts.append(context)
        return CleanupOutcome(text: text.replacingOccurrences(of: "um ", with: ""), via: "fake")
    }
}

@MainActor
@Suite("Session with streaming and cleanup")
struct StreamingSessionTests {
    @Test func cloudTranscriptWinsAndAudioWasStreamed() async {
        let provider = FakeStreamProvider { FakeStream(.success("from the cloud")) }
        let ins = FakeInserter()
        var events: [SessionEvent] = []
        let s = Session(audio: FakeAudio(), transcriber: FakeTranscriber(text: "from local"), inserter: ins,
                        streaming: provider)
        s.onCompleted = { events.append($0) }
        s.handle(.armPreroll)
        await s.handle(.finish(.dictation))?.value
        #expect(ins.inserted == ["from the cloud"])
        #expect(provider.opened.first?.fed == 1_600)
        #expect(events.first?.sttSource == .cloud)
    }

    @Test func cloudFailureStillInsertsLocalText() async {
        let provider = FakeStreamProvider { FakeStream(.failure(NSError(domain: "net", code: 1))) }
        let ins = FakeInserter()
        let s = Session(audio: FakeAudio(), transcriber: FakeTranscriber(text: "from local"), inserter: ins,
                        streaming: provider)
        s.handle(.armPreroll)
        await s.handle(.finish(.dictation))?.value
        #expect(ins.inserted == ["from local"])
    }

    @Test func cancelClosesTheCloudStream() {
        let provider = FakeStreamProvider { FakeStream(.success("x")) }
        let s = Session(audio: FakeAudio(), transcriber: FakeTranscriber(), inserter: FakeInserter(), streaming: provider)
        s.handle(.armPreroll)
        s.handle(.cancel)
        #expect(provider.opened.first?.cancelled == true)
    }

    @Test func tooShortRecordingCancelsTheCloudStream() async {
        let provider = FakeStreamProvider { FakeStream(.success("x")) }
        let s = Session(audio: FakeAudio(seconds: 0.1), transcriber: FakeTranscriber(), inserter: FakeInserter(),
                        streaming: provider)
        s.handle(.armPreroll)
        await s.handle(.finish(.dictation))?.value
        #expect(provider.opened.first?.cancelled == true)
    }

    @Test func cleanerOutputIsWhatGetsTyped() async {
        let ins = FakeInserter()
        var events: [SessionEvent] = []
        let s = Session(audio: FakeAudio(), transcriber: FakeTranscriber(text: "um hello"), inserter: ins,
                        cleaner: FakeCleaner())
        s.onCompleted = { events.append($0) }
        s.handle(.armPreroll)
        await s.handle(.finish(.dictation))?.value
        #expect(ins.inserted == ["hello"])
        #expect(events.first?.rawTranscript == "um hello")
        #expect(events.first?.cleanupVia == "fake")
    }

    @Test func eachRecordingGetsItsOwnStream() async {
        let provider = FakeStreamProvider { FakeStream(.success("x")) }
        let s = Session(audio: FakeAudio(), transcriber: FakeTranscriber(), inserter: FakeInserter(), streaming: provider)
        s.handle(.armPreroll)
        await s.handle(.finish(.dictation))?.value
        s.handle(.armPreroll)
        await s.handle(.finish(.dictation))?.value
        #expect(provider.opened.count == 2)
        #expect(provider.opened[1].fed == 1_600)
    }

    @Test func focusedAppIsCapturedAtKeyUpAndPassedToCleanup() async {
        let cleaner = FakeCleaner()
        final class Front: @unchecked Sendable { var ctx = DictationContext(bundleID: "com.apple.Notes") }
        let front = Front()
        let s = Session(audio: FakeAudio(), transcriber: FakeTranscriber(), inserter: FakeInserter(),
                        cleaner: cleaner, contextProvider: { front.ctx })
        s.handle(.armPreroll)
        front.ctx = DictationContext(bundleID: "com.todesktop.230313mzl4w4u92", windowTitle: "auth.ts — api")
        await s.handle(.finish(.dictation))?.value
        #expect(cleaner.contexts == [DictationContext(bundleID: "com.todesktop.230313mzl4w4u92", windowTitle: "auth.ts — api")])
    }

    @Test func taskRejectedByAgentIsReported() async {
        let tasks = FakeTasks()
        tasks.accept = false
        let s = Session(audio: FakeAudio(), transcriber: FakeTranscriber(text: "run the tests"), inserter: FakeInserter(),
                        tasks: tasks)
        s.handle(.armPreroll)
        await s.handle(.finish(.task))?.value
        #expect(s.status == .failed("Agent isn't running (see the InstructFlow menu)"))
    }
}
