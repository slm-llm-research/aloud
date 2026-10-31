import Foundation

/// macOS virtual key codes used by the trigger (from `Carbon/HIToolbox/Events.h`).
public enum KeyCode {
    public static let tab: UInt16 = 48
    public static let escape: UInt16 = 53
    public static let leftShift: UInt16 = 56
    public static let rightShift: UInt16 = 60
    public static let rightOption: UInt16 = 61
    public static let rightCommand: UInt16 = 54
}

/// Device-dependent modifier bits in `CGEventFlags` (from IOKit `NX_DEVICE*KEYMASK`).
/// They tell left and right modifiers apart, which the device-independent `.maskShift` cannot.
public enum DeviceFlag {
    public static let leftShift: UInt64 = 0x0000_0002
    public static let rightShift: UInt64 = 0x0000_0004
    public static let rightOption: UInt64 = 0x0000_0040
    public static let rightCommand: UInt64 = 0x0000_0010
}

/// The raw event kinds the tap forwards.
public enum RawEventType: Sendable {
    case keyDown, keyUp, flagsChanged
}

/// Turns a raw keyboard event into a `HotkeyInput`. Pure, so the Left/Right Shift and chord-key rules
/// (PLAN.md §2) are unit-tested without an event tap.
public struct KeyClassifier: Sendable {
    public var triggerKeyCode: UInt16
    public var triggerDeviceFlag: UInt64

    public init(triggerKeyCode: UInt16 = KeyCode.rightShift,
                triggerDeviceFlag: UInt64 = DeviceFlag.rightShift) {
        self.triggerKeyCode = triggerKeyCode
        self.triggerDeviceFlag = triggerDeviceFlag
    }

    public func classify(type: RawEventType, keyCode: UInt16, flags: UInt64,
                         isAutoRepeat: Bool = false, at t: TimeInterval) -> HotkeyInput? {
        switch type {
        case .flagsChanged:
            if keyCode == triggerKeyCode {
                return (flags & triggerDeviceFlag) != 0 ? .triggerDown(t) : .triggerUp(t)
            }
            if keyCode == KeyCode.rightOption, (flags & DeviceFlag.rightOption) != 0 {
                return .keyDown(.commandModifier, t)
            }
            if keyCode == KeyCode.rightCommand, (flags & DeviceFlag.rightCommand) != 0 {
                return .keyDown(.taskModifier, t)
            }
            if keyCode == KeyCode.rightCommand, (flags & DeviceFlag.rightCommand) != 0 {
                return .keyDown(.taskModifier, t)
            }
            // Other modifiers (the other Shift, Cmd, Ctrl, ...) changing state: irrelevant to the trigger.
            return nil
        case .keyDown:
            // Holding a key auto-repeats; only the first press matters to the gesture.
            if isAutoRepeat { return nil }
            return .keyDown(kind(of: keyCode), t)
        case .keyUp:
            return .keyUp(kind(of: keyCode), t)
        }
    }

    /// When the trigger goes down while a chord key is already held (Right Command or Right Option
    /// pressed first), the chord counts as if it came second. Returns that chord input, if any.
    public func heldChord(after input: HotkeyInput, flags: UInt64) -> HotkeyInput? {
        guard case .triggerDown(let t) = input else { return nil }
        if (flags & DeviceFlag.rightCommand) != 0 { return .keyDown(.taskModifier, t) }
        if (flags & DeviceFlag.rightOption) != 0 { return .keyDown(.commandModifier, t) }
        return nil
    }

    private func kind(of keyCode: UInt16) -> KeyKind {
        switch keyCode {
        case KeyCode.escape: return .escape
        default: return .other
        }
    }
}
