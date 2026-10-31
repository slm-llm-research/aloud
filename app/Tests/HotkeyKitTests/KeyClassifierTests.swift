import Testing
@testable import HotkeyKit

@Suite("Key classification")
struct KeyClassifierTests {
    let c = KeyClassifier()

    @Test func rightShiftIsTheDefaultTrigger() {
        #expect(c.classify(type: .flagsChanged, keyCode: KeyCode.rightShift,
                           flags: DeviceFlag.rightShift, at: 1) == .triggerDown(1))
        #expect(c.classify(type: .flagsChanged, keyCode: KeyCode.rightShift, flags: 0, at: 2) == .triggerUp(2))
    }

    /// Real right-Shift-down flags from a MacBook keyboard: device bit + .maskShift + non-coalesced bit.
    @Test func realWorldFlagsAreRecognized() {
        #expect(c.classify(type: .flagsChanged, keyCode: KeyCode.rightShift, flags: 0x20104, at: 1) == .triggerDown(1))
        #expect(c.classify(type: .flagsChanged, keyCode: KeyCode.rightShift, flags: 0x100, at: 2) == .triggerUp(2))
    }

    @Test func leftShiftIsIgnored() {
        #expect(c.classify(type: .flagsChanged, keyCode: KeyCode.leftShift, flags: DeviceFlag.leftShift, at: 1) == nil)
    }

    @Test func rightShiftReleasedWhileLeftShiftHeldIsStillAnUp() {
        // Left Shift device bit still set, right bit cleared.
        #expect(c.classify(type: .flagsChanged, keyCode: KeyCode.rightShift,
                           flags: DeviceFlag.leftShift, at: 3) == .triggerUp(3))
    }

    @Test func triggerKeyIsConfigurable() {
        let left = KeyClassifier(triggerKeyCode: KeyCode.leftShift, triggerDeviceFlag: DeviceFlag.leftShift)
        #expect(left.classify(type: .flagsChanged, keyCode: KeyCode.leftShift,
                              flags: DeviceFlag.leftShift, at: 1) == .triggerDown(1))
        #expect(left.classify(type: .flagsChanged, keyCode: KeyCode.rightShift, flags: DeviceFlag.rightShift, at: 1) == nil)
    }

    @Test func tabIsAnOrdinaryKeyAndEscapeIsSpecial() {
        #expect(c.classify(type: .keyDown, keyCode: KeyCode.tab, flags: 0, at: 1) == .keyDown(.other, 1))
        #expect(c.classify(type: .keyDown, keyCode: KeyCode.escape, flags: 0, at: 1) == .keyDown(.escape, 1))
    }

    @Test func rightCommandDownIsTaskModifierButUpIsIgnored() {
        #expect(c.classify(type: .flagsChanged, keyCode: KeyCode.rightCommand,
                           flags: DeviceFlag.rightCommand, at: 1) == .keyDown(.taskModifier, 1))
        #expect(c.classify(type: .flagsChanged, keyCode: KeyCode.rightCommand, flags: 0, at: 2) == nil)
        // Left Command (keycode 55, device bit 0x8) is not the chord key.
        #expect(c.classify(type: .flagsChanged, keyCode: 55, flags: 0x8, at: 3) == nil)
    }

    @Test func lettersAreOther() {
        #expect(c.classify(type: .keyDown, keyCode: 0 /* A */, flags: 0, at: 1) == .keyDown(.other, 1))
    }

    @Test func autoRepeatIsIgnored() {
        #expect(c.classify(type: .keyDown, keyCode: 0, flags: 0, isAutoRepeat: true, at: 1) == nil)
    }

    @Test func rightOptionDownIsCommandModifierButUpIsIgnored() {
        #expect(c.classify(type: .flagsChanged, keyCode: KeyCode.rightOption,
                           flags: DeviceFlag.rightOption, at: 1) == .keyDown(.commandModifier, 1))
        #expect(c.classify(type: .flagsChanged, keyCode: KeyCode.rightOption, flags: 0, at: 2) == nil)
    }

    /// Feeds raw events through classifier + machine and returns every output.
    func run(_ events: [(RawEventType, UInt16, UInt64)]) -> [HotkeyOutput] {
        var m = HotkeyMachine()
        var outputs: [HotkeyOutput] = []
        for (i, e) in events.enumerated() {
            if let input = c.classify(type: e.0, keyCode: e.1, flags: e.2, at: Double(i) * 0.05) {
                outputs.append(m.handle(input))
            }
        }
        return outputs
    }

    @Test func rightShiftPlusRightCommandStartsATaskWithoutConsumingAnything() {
        let out = run([
            (.flagsChanged, KeyCode.rightShift, DeviceFlag.rightShift),
            (.flagsChanged, KeyCode.rightCommand, DeviceFlag.rightShift | DeviceFlag.rightCommand),
            (.flagsChanged, KeyCode.rightCommand, DeviceFlag.rightShift),
            (.flagsChanged, KeyCode.rightShift, 0),
        ])
        #expect(out.flatMap(\.actions) == [.armPreroll, .startRecording(.task), .finish(.task)])
        #expect(out.allSatisfy { $0.disposition == .passThrough })
    }

    /// Shift + Tab (either Shift) reaches the app untouched, so Claude Code's mode switch keeps working.
    @Test func shiftTabReachesTheAppAndNeverStartsATask() {
        for (code, flag) in [(KeyCode.rightShift, DeviceFlag.rightShift), (KeyCode.leftShift, DeviceFlag.leftShift)] {
            let out = run([
                (.flagsChanged, code, flag),
                (.keyDown, KeyCode.tab, flag),
                (.keyUp, KeyCode.tab, flag),
                (.flagsChanged, code, 0),
            ])
            #expect(out.allSatisfy { $0.disposition == .passThrough })
            #expect(!out.flatMap(\.actions).contains { if case .startRecording = $0 { true } else { false } })
        }
    }

    @Test func rightCommandPressedBeforeRightShiftStillStartsATask() {
        let down = c.classify(type: .flagsChanged, keyCode: KeyCode.rightShift,
                              flags: DeviceFlag.rightCommand | DeviceFlag.rightShift, at: 1)!
        #expect(down == .triggerDown(1))
        let chord = c.heldChord(after: down, flags: DeviceFlag.rightCommand | DeviceFlag.rightShift)
        #expect(chord == .keyDown(.taskModifier, 1))
        var m = HotkeyMachine()
        let actions = [down, chord!, .triggerUp(3)].flatMap { m.handle($0).actions }
        #expect(actions == [.armPreroll, .startRecording(.task), .finish(.task)])
        #expect(c.heldChord(after: down, flags: DeviceFlag.rightShift) == nil)
        #expect(c.heldChord(after: .triggerUp(2), flags: DeviceFlag.rightCommand) == nil)
    }

    @Test func rightCommandAloneDoesNothing() {
        let out = run([
            (.flagsChanged, KeyCode.rightCommand, DeviceFlag.rightCommand),
            (.flagsChanged, KeyCode.rightCommand, 0),
        ])
        #expect(out.flatMap(\.actions).isEmpty)
    }
}
