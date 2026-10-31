import Foundation

/// What the recording is for. Chosen by the key gesture, see PLAN.md §2.
public enum RecordingMode: Equatable, Sendable {
    case dictation  // hold Right Shift (or double-tap to latch)
    case task       // Right Shift + Right Command: routed to the agent daemon
    case command    // Right Shift + Right Option: edit the selection by voice
}

/// Side effects the app must perform in response to an input.
public enum HotkeyAction: Equatable, Sendable {
    /// Start buffering microphone audio (pre-roll) because a recording may be about to start.
    case armPreroll
    /// The gesture is confirmed: keep the pre-roll and continue recording in this mode.
    case startRecording(RecordingMode)
    /// The user added a chord key while recording; the same audio now belongs to a different mode.
    case changeMode(RecordingMode)
    /// Stop recording and process the audio.
    case finish(RecordingMode)
    /// Stop recording (or pre-roll) and discard the audio.
    case cancel
}

/// Whether the original keyboard event should reach the focused app.
public enum KeyDisposition: Equatable, Sendable {
    case passThrough
    case consume
}

public enum KeyKind: Equatable, Sendable {
    case escape
    case taskModifier     // Right Command, only meaningful while the trigger is held
    case commandModifier  // Right Option, only meaningful while the trigger is held
    case other
}

/// Inputs carry their own timestamps (seconds, monotonic) so the machine is deterministic under test.
public enum HotkeyInput: Equatable, Sendable {
    case triggerDown(TimeInterval)
    case triggerUp(TimeInterval)
    case keyDown(KeyKind, TimeInterval)
    case keyUp(KeyKind, TimeInterval)
    /// Fired by the adapter at (or after) `nextDeadline`.
    case timer(TimeInterval)
}

public struct HotkeyConfig: Equatable, Sendable {
    /// The trigger (Right Shift by default) must be held this long, with no other key pressed, before dictation starts.
    /// Longer than for a dedicated key because Shift is also used for typing capitals.
    public var minHold: TimeInterval = 0.25
    /// Second press must come within this long after the first release to latch the mic open.
    public var doubleTapWindow: TimeInterval = 0.30
    /// A latched session finishes on its own after this long.
    public var maxLatched: TimeInterval = 20 * 60

    public init(minHold: TimeInterval = 0.25, doubleTapWindow: TimeInterval = 0.30,
                maxLatched: TimeInterval = 20 * 60) {
        self.minHold = minHold
        self.doubleTapWindow = doubleTapWindow
        self.maxLatched = maxLatched
    }
}

public struct HotkeyOutput: Equatable, Sendable {
    public var actions: [HotkeyAction]
    public var disposition: KeyDisposition

    public init(_ actions: [HotkeyAction] = [], _ disposition: KeyDisposition = .passThrough) {
        self.actions = actions
        self.disposition = disposition
    }
}

/// The trigger-key state machine (PLAN.md §2). No OS dependencies: the event tap feeds it inputs
/// and performs the returned actions.
public struct HotkeyMachine: Sendable {
    public enum State: Equatable, Sendable {
        case idle
        /// Trigger is down, not yet long enough to count as a hold. Pre-roll is running.
        case armed(downAt: TimeInterval)
        /// A quick tap just ended; a second press within the window latches.
        case tapPending(upAt: TimeInterval)
        /// Recording while the trigger is held.
        case holding(RecordingMode)
        /// Latched by a double-tap, and the second press is still held down.
        case latchedHeld(startedAt: TimeInterval)
        /// Latched: recording hands-free until the trigger is tapped again.
        case latched(startedAt: TimeInterval)
        /// Trigger pressed while latched; recording finishes when it is released.
        case latchedStopPressed(startedAt: TimeInterval)
    }

    public let config: HotkeyConfig
    public private(set) var state: State = .idle

    public init(config: HotkeyConfig = HotkeyConfig()) {
        self.config = config
    }

    /// When the adapter should deliver `.timer`, or nil if no timer is needed.
    public var nextDeadline: TimeInterval? {
        switch state {
        case .armed(let downAt): return downAt + config.minHold
        case .tapPending(let upAt): return upAt + config.doubleTapWindow
        case .latched(let startedAt), .latchedHeld(let startedAt), .latchedStopPressed(let startedAt):
            return startedAt + config.maxLatched
        case .idle, .holding: return nil
        }
    }

    public var isRecording: Bool {
        switch state {
        case .holding, .latchedHeld, .latched, .latchedStopPressed: return true
        case .idle, .armed, .tapPending: return false
        }
    }

    public mutating func handle(_ input: HotkeyInput) -> HotkeyOutput {
        switch (state, input) {

        // MARK: idle
        case (.idle, .triggerDown(let t)):
            state = .armed(downAt: t)
            return HotkeyOutput([.armPreroll])

        // MARK: armed
        case (.armed(let downAt), .timer(let t)) where t - downAt >= config.minHold:
            state = .holding(.dictation)
            return HotkeyOutput([.startRecording(.dictation)])
        case (.armed(let downAt), .triggerUp(let t)):
            if t - downAt >= config.minHold {
                // The timer was late; the key was held long enough, so treat it as a full hold.
                state = .idle
                return HotkeyOutput([.startRecording(.dictation), .finish(.dictation)])
            }
            state = .tapPending(upAt: t)
            return HotkeyOutput([.cancel])
        case (.armed, .keyDown(.taskModifier, _)):
            // Chords are modifier-only, so nothing reaches the app as a shortcut and nothing is consumed.
            state = .holding(.task)
            return HotkeyOutput([.startRecording(.task)])
        case (.armed, .keyDown(.commandModifier, _)):
            state = .holding(.command)
            return HotkeyOutput([.startRecording(.command)])
        case (.armed, .keyDown):
            // Shift + letter (or Shift + Tab): ordinary typing. Never steal it.
            state = .idle
            return HotkeyOutput([.cancel])

        // MARK: tapPending
        case (.tapPending(let upAt), .triggerDown(let t)):
            if t - upAt <= config.doubleTapWindow {
                state = .latchedHeld(startedAt: t)
                return HotkeyOutput([.armPreroll, .startRecording(.dictation)])
            }
            state = .armed(downAt: t)
            return HotkeyOutput([.armPreroll])
        case (.tapPending(let upAt), .timer(let t)) where t - upAt > config.doubleTapWindow:
            state = .idle
            return HotkeyOutput()
        case (.tapPending, .keyDown):
            state = .idle
            return HotkeyOutput()

        // MARK: holding
        case (.holding(let mode), .triggerUp):
            state = .idle
            return HotkeyOutput([.finish(mode)])
        case (.holding(.dictation), .keyDown(.taskModifier, _)):
            state = .holding(.task)
            return HotkeyOutput([.changeMode(.task)])
        case (.holding(.dictation), .keyDown(.commandModifier, _)):
            state = .holding(.command)
            return HotkeyOutput([.changeMode(.command)])
        case (.holding, .keyDown(.escape, _)):
            state = .idle
            return HotkeyOutput([.cancel], .consume)
        case (.holding, .keyDown(.commandModifier, _)), (.holding, .keyDown(.taskModifier, _)):
            // Already in task or command mode: another chord key changes nothing.
            return HotkeyOutput()
        case (.holding, .keyDown):
            // A slow Shift + letter (held past minHold). Discard, let the key through.
            state = .idle
            return HotkeyOutput([.cancel])

        // MARK: latched
        case (.latchedHeld(let s), .triggerUp):
            state = .latched(startedAt: s)
            return HotkeyOutput()
        case (.latchedHeld, .keyDown(.escape, _)),
             (.latched, .keyDown(.escape, _)),
             (.latchedStopPressed, .keyDown(.escape, _)):
            state = .idle
            return HotkeyOutput([.cancel], .consume)
        case (.latchedHeld, .keyDown):
            // Double-tap immediately followed by Shift + letter: it was typing, not a latch.
            state = .idle
            return HotkeyOutput([.cancel])
        case (.latched(let s), .triggerDown):
            state = .latchedStopPressed(startedAt: s)
            return HotkeyOutput()
        case (.latchedStopPressed, .triggerUp):
            state = .idle
            return HotkeyOutput([.finish(.dictation)])
        case (.latchedStopPressed(let s), .keyDown):
            // Typing a capital while the mic is latched: keep recording.
            state = .latched(startedAt: s)
            return HotkeyOutput()
        case (.latched(let s), .timer(let t)) where t - s >= config.maxLatched,
             (.latchedHeld(let s), .timer(let t)) where t - s >= config.maxLatched,
             (.latchedStopPressed(let s), .timer(let t)) where t - s >= config.maxLatched:
            state = .idle
            return HotkeyOutput([.finish(.dictation)])

        default:
            // Early timers, stray key-ups, keys typed while latched, etc.
            return HotkeyOutput()
        }
    }
}
