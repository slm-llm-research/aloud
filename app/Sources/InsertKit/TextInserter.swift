import AppKit
import Carbon.HIToolbox
import CoreGraphics

public enum InsertionResult: Equatable, Sendable {
    case inserted(InsertionStrategy)
    /// Not typed into the app; left on the clipboard instead (e.g. a secure password field).
    case copiedToClipboard
    case empty
}

/// Puts text into whatever app has keyboard focus. Needs the Accessibility permission to post events.
@MainActor
public final class TextInserter {
    private let pasteboard: NSPasteboard
    /// Restores the user's clipboard ~450 ms after the paste (the target reads the pasteboard when
    /// it handles Cmd-V; slow Electron apps need a few hundred ms), without making insert() wait.
    private let clipboard: ClipboardGuard

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        self.clipboard = ClipboardGuard(pasteboard: pasteboard)
    }

    public func insert(_ raw: String) async -> InsertionResult {
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let category = InsertionPolicy.category(bundleID: bundleID)
        let text = InsertionPolicy.sanitize(raw, for: category)
        guard !text.isEmpty else { return .empty }

        switch InsertionPolicy.strategy(bundleID: bundleID, secureInputActive: IsSecureEventInputEnabled()) {
        case .clipboardOnly:
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            return .copiedToClipboard
        case .typeUnicode:
            Self.typeUnicode(text)
            return .inserted(.typeUnicode)
        case .pasteShortcut:
            let ours = clipboard.lend(text)
            Self.postCommandV()
            clipboard.scheduleRestore(ours: ours)
            return .inserted(.pasteShortcut)
        }
    }

    static func postCommandV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let v = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: false)
        // Only Command: if Shift were still reported as held, apps would see Cmd-Shift-V.
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    static func typeUnicode(_ text: String) {
        let src = CGEventSource(stateID: .combinedSessionState)
        let units = Array(text.utf16)
        // Small chunks: some apps drop long Unicode strings attached to a single event.
        for start in stride(from: 0, to: units.count, by: 20) {
            let chunk = Array(units[start..<min(start + 20, units.count)])
            for keyDown in [true, false] {
                let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: keyDown)
                e?.flags = []
                chunk.withUnsafeBufferPointer { e?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: $0.baseAddress) }
                e?.post(tap: .cghidEventTap)
            }
        }
    }
}
