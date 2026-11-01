import CoreGraphics
import Foundation

/// Bridges a CGEventTap to `HotkeyMachine`. Runs the tap on its own thread and run loop so a busy
/// main thread can never make macOS disable the tap for slowness.
///
/// Requires the Accessibility permission (active taps that can consume events) and Input Monitoring.
public final class EventTap: @unchecked Sendable {
    public typealias ActionHandler = @Sendable (HotkeyAction) -> Void
    /// Diagnostics: every classified input and the machine's decision.
    public typealias InputObserver = @Sendable (HotkeyInput, HotkeyOutput) -> Void

    private let classifier: KeyClassifier
    private let onAction: ActionHandler
    private let lock = NSLock()
    private var machine: HotkeyMachine
    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?
    private var timer: CFRunLoopTimer?
    private var thread: Thread?
    private let observer: InputObserver?
    /// Raw keyboard events the tap has received (any key). 0 after typing means the tap is deaf.
    public private(set) var eventsSeen = 0

    public init(config: HotkeyConfig = HotkeyConfig(), classifier: KeyClassifier = KeyClassifier(),
                observer: InputObserver? = nil, onAction: @escaping ActionHandler) {
        self.machine = HotkeyMachine(config: config)
        self.classifier = classifier
        self.observer = observer
        self.onAction = onAction
    }

    /// Returns false if the tap could not be created (usually a missing permission).
    @discardableResult
    public func start() -> Bool {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        self.tap = tap

        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            guard let self, let tap = self.tap else { return }
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            self.runLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(self.runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "aloud.eventtap"
        thread.qualityOfService = .userInteractive
        thread.start()
        self.thread = thread
        ready.wait()
        return true
    }

    public func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoop { CFRunLoopStop(runLoop) }
        tap = nil
        runLoop = nil
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        eventsSeen += 1
        let raw: RawEventType
        switch type {
        case .keyDown: raw = .keyDown
        case .keyUp: raw = .keyUp
        case .flagsChanged: raw = .flagsChanged
        default: return Unmanaged.passUnretained(event)
        }
        guard let input = classifier.classify(
            type: raw,
            keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
            flags: event.flags.rawValue,
            isAutoRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
            at: Self.now()
        ) else { return Unmanaged.passUnretained(event) }

        let output = step(input)
        if let chord = classifier.heldChord(after: input, flags: event.flags.rawValue) { _ = step(chord) }
        return output.disposition == .consume ? nil : Unmanaged.passUnretained(event)
    }

    private func step(_ input: HotkeyInput) -> HotkeyOutput {
        lock.lock()
        let output = machine.handle(input)
        let deadline = machine.nextDeadline
        lock.unlock()
        observer?(input, output)
        for action in output.actions { onAction(action) }
        schedule(deadline)
        return output
    }

    /// Keeps exactly one pending timer, at the machine's next deadline.
    private func schedule(_ deadline: TimeInterval?) {
        guard let runLoop else { return }
        if let timer { CFRunLoopTimerInvalidate(timer) }
        timer = nil
        guard let deadline else { return }
        let fireAt = CFAbsoluteTimeGetCurrent() + max(0, deadline - Self.now())
        let t = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault, fireAt, 0, 0, 0) { [weak self] _ in
            guard let self else { return }
            _ = self.step(.timer(Self.now()))
        }
        timer = t
        CFRunLoopAddTimer(runLoop, t, .commonModes)
    }

    static func now() -> TimeInterval {
        TimeInterval(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1_000_000_000
    }
}

private func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                              userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue()
    return tap.handle(type: type, event: event)
}
