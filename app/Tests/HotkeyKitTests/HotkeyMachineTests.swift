import Testing
@testable import HotkeyKit

/// Feeds a sequence of inputs and collects every action and disposition.
private struct Run {
    var machine = HotkeyMachine()
    var actions: [HotkeyAction] = []
    var dispositions: [KeyDisposition] = []

    init(_ config: HotkeyConfig = HotkeyConfig()) {
        machine = HotkeyMachine(config: config)
    }

    mutating func send(_ inputs: HotkeyInput...) {
        for input in inputs {
            let out = machine.handle(input)
            actions += out.actions
            dispositions.append(out.disposition)
        }
    }

    var started: Bool { actions.contains { if case .startRecording = $0 { true } else { false } } }
}

@Suite("Hold to talk")
struct HoldTests {
    @Test func holdPastMinHoldStartsAndReleaseFinishes() {
        var r = Run()
        r.send(.triggerDown(0), .timer(0.25), .triggerUp(3.0))
        #expect(r.actions == [.armPreroll, .startRecording(.dictation), .finish(.dictation)])
        #expect(r.machine.state == .idle)
    }

    @Test func earlyTimerDoesNothing() {
        var r = Run()
        r.send(.triggerDown(0), .timer(0.1))
        #expect(r.actions == [.armPreroll])
        #expect(r.machine.state == .armed(downAt: 0))
    }

    @Test func lateTimerStillCountsAsHold() {
        var r = Run()
        r.send(.triggerDown(0), .triggerUp(0.4))
        #expect(r.actions == [.armPreroll, .startRecording(.dictation), .finish(.dictation)])
    }

    @Test func deadlineIsMinHoldAfterPress() {
        var r = Run()
        r.send(.triggerDown(10))
        #expect(r.machine.nextDeadline == 10.25)
    }

    @Test func escapeCancelsAndIsConsumed() {
        var r = Run()
        r.send(.triggerDown(0), .timer(0.3), .keyDown(.escape, 1))
        #expect(r.actions.last == .cancel)
        #expect(r.dispositions.last == .consume)
        #expect(r.machine.state == .idle)
    }
}

@Suite("Shift still types capitals")
struct TypingTests {
    @Test func shiftLetterIsPassedThroughAndNeverRecords() {
        var r = Run()
        r.send(.triggerDown(0), .keyDown(.other, 0.08), .keyUp(.other, 0.12), .triggerUp(0.15))
        #expect(!r.started)
        #expect(r.dispositions.allSatisfy { $0 == .passThrough })
        #expect(r.machine.state == .idle)
    }

    @Test func slowShiftLetterAfterMinHoldCancelsAndPassesLetter() {
        var r = Run()
        r.send(.triggerDown(0), .timer(0.25), .keyDown(.other, 0.4))
        #expect(r.actions.last == .cancel)
        #expect(r.dispositions.last == .passThrough)
        #expect(r.machine.state == .idle)
    }

    @Test func releasingAfterTypedCapitalDoesNotFinish() {
        var r = Run()
        r.send(.triggerDown(0), .timer(0.3), .keyDown(.other, 0.4), .triggerUp(0.5))
        #expect(!r.actions.contains(.finish(.dictation)))
    }

    /// Simulates typing a paragraph where every capital uses the trigger Shift, with realistic jitter.
    /// No interleaving of Shift + letter must ever start a recording.
    @Test func randomTypingNeverStartsRecording() {
        var rng = SplitMix(seed: 42)
        var r = Run()
        var t = 0.0
        for _ in 0..<5_000 {
            if rng.unit() < 0.15 {
                // Capital: Shift down, letter within 30-240 ms, Shift up shortly after.
                r.send(.triggerDown(t))
                t += 0.03 + rng.unit() * 0.21
                r.send(.timer(t - 0.001), .keyDown(.other, t), .keyUp(.other, t + 0.04))
                t += 0.05 + rng.unit() * 0.1
                r.send(.triggerUp(t))
            } else {
                r.send(.keyDown(.other, t), .keyUp(.other, t + 0.05))
            }
            t += 0.08 + rng.unit() * 0.2
            r.send(.timer(t))
        }
        #expect(!r.started)
        #expect(r.dispositions.allSatisfy { $0 == .passThrough })
    }
}

@Suite("Double-tap latch")
struct LatchTests {
    @Test func doubleTapLatchesThenSingleTapFinishes() {
        var r = Run()
        r.send(.triggerDown(0), .triggerUp(0.1),   // tap 1
               .triggerDown(0.3), .triggerUp(0.4)) // tap 2 within window -> latched
        #expect(r.machine.state == .latched(startedAt: 0.3))
        #expect(r.machine.isRecording)
        r.send(.triggerDown(5), .triggerUp(5.1))
        #expect(r.actions == [.armPreroll, .cancel, .armPreroll, .startRecording(.dictation), .finish(.dictation)])
        #expect(r.machine.state == .idle)
    }

    @Test func secondTapOutsideWindowIsJustANewPress() {
        var r = Run()
        r.send(.triggerDown(0), .triggerUp(0.1), .triggerDown(0.5))
        #expect(r.machine.state == .armed(downAt: 0.5))
    }

    @Test func tapPendingExpires() {
        var r = Run()
        r.send(.triggerDown(0), .triggerUp(0.1), .timer(0.41))
        #expect(r.machine.state == .idle)
    }

    @Test func typingWhileLatchedKeepsRecordingAndPassesKeys() {
        var r = Run()
        r.send(.triggerDown(0), .triggerUp(0.1), .triggerDown(0.3), .triggerUp(0.4),
               .keyDown(.other, 1), .keyUp(.other, 1.05),
               .triggerDown(2), .keyDown(.other, 2.1), .triggerUp(2.2)) // capital while latched
        #expect(r.machine.state == .latched(startedAt: 0.3))
        #expect(!r.actions.contains(.finish(.dictation)))
        #expect(r.dispositions.allSatisfy { $0 == .passThrough })
    }

    @Test func escapeCancelsLatched() {
        var r = Run()
        r.send(.triggerDown(0), .triggerUp(0.1), .triggerDown(0.3), .triggerUp(0.4), .keyDown(.escape, 3))
        #expect(r.actions.last == .cancel)
        #expect(r.dispositions.last == .consume)
    }

    @Test func latchedSessionTimesOut() {
        var r = Run(HotkeyConfig(maxLatched: 60))
        r.send(.triggerDown(0), .triggerUp(0.1), .triggerDown(0.3), .triggerUp(0.4))
        #expect(r.machine.nextDeadline == 60.3)
        r.send(.timer(60.3))
        #expect(r.actions.last == .finish(.dictation))
    }

    @Test func doubleTapThenLetterWasTyping() {
        var r = Run()
        r.send(.triggerDown(0), .triggerUp(0.1), .triggerDown(0.3), .keyDown(.other, 0.35))
        #expect(r.actions.last == .cancel)
        #expect(r.dispositions.last == .passThrough)
        #expect(r.machine.state == .idle)
    }
}

@Suite("Right Shift + Right Command task mode")
struct TaskModeTests {
    @Test func rightCommandWhileArmedStartsTaskAndNothingIsConsumed() {
        var r = Run()
        r.send(.triggerDown(0), .keyDown(.taskModifier, 0.1), .triggerUp(4))
        #expect(r.actions == [.armPreroll, .startRecording(.task), .finish(.task)])
        #expect(r.dispositions == [.passThrough, .passThrough, .passThrough])
    }

    @Test func rightCommandDuringDictationSwitchesToTask() {
        var r = Run()
        r.send(.triggerDown(0), .timer(0.25), .keyDown(.taskModifier, 1), .triggerUp(3))
        #expect(r.actions == [.armPreroll, .startRecording(.dictation), .changeMode(.task), .finish(.task)])
    }

    @Test func escapeCancelsATask() {
        var r = Run()
        r.send(.triggerDown(0), .keyDown(.taskModifier, 0.1), .keyDown(.escape, 1))
        #expect(r.actions == [.armPreroll, .startRecording(.task), .cancel])
        #expect(r.dispositions.last == .consume)
        #expect(r.machine.state == .idle)
    }

    @Test func pressingRightCommandAgainChangesNothing() {
        var r = Run()
        r.send(.triggerDown(0), .keyDown(.taskModifier, 0.1), .keyDown(.taskModifier, 0.5), .triggerUp(2))
        #expect(r.actions == [.armPreroll, .startRecording(.task), .finish(.task)])
    }

    @Test func shiftTabIsTypingNotATask() {
        var r = Run()
        r.send(.triggerDown(0), .keyDown(.other, 0.1), .triggerUp(0.2))
        #expect(r.actions == [.armPreroll, .cancel])
        #expect(r.dispositions.allSatisfy { $0 == .passThrough })
    }

    @Test func taskModifierWithoutTriggerDoesNothing() {
        var r = Run()
        r.send(.keyDown(.taskModifier, 0))
        #expect(r.actions.isEmpty)
    }
}

@Suite("Command mode chord")
struct CommandModeTests {
    @Test func rightOptionWhileArmedStartsCommand() {
        var r = Run()
        r.send(.triggerDown(0), .keyDown(.commandModifier, 0.1), .triggerUp(2))
        #expect(r.actions == [.armPreroll, .startRecording(.command), .finish(.command)])
    }

    @Test func rightOptionDuringDictationSwitchesToCommand() {
        var r = Run()
        r.send(.triggerDown(0), .timer(0.25), .keyDown(.commandModifier, 0.5), .triggerUp(2))
        #expect(r.actions.suffix(2) == [.changeMode(.command), .finish(.command)])
    }
}

/// Small deterministic RNG so the fuzz test is reproducible.
struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}
