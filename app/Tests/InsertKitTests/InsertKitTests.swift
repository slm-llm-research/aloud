import AppKit
import Testing
@testable import InsertKit

/// A private, uniquely named pasteboard so tests never touch your real clipboard.
private func scratchPasteboard() -> NSPasteboard {
    NSPasteboard(name: NSPasteboard.Name("instructflow.test.\(UUID().uuidString)"))
}

@Suite("Pasteboard save and restore")
struct PasteboardTests {
    @Test func restoresTextExactly() {
        let pb = scratchPasteboard()
        pb.clearContents()
        pb.setString("user's clipboard", forType: .string)
        let snap = PasteboardSnapshot.capture(pb)

        pb.writeTransientText("dictated text")
        #expect(pb.string(forType: .string) == "dictated text")

        snap.restore(to: pb)
        #expect(pb.string(forType: .string) == "user's clipboard")
        pb.releaseGlobally()
    }

    @Test func restoresMultipleTypesAndItems() {
        let pb = scratchPasteboard()
        pb.clearContents()
        let a = NSPasteboardItem()
        a.setString("plain", forType: .string)
        a.setString("<b>rich</b>", forType: .html)
        let b = NSPasteboardItem()
        b.setString("second", forType: .string)
        pb.writeObjects([a, b])

        let snap = PasteboardSnapshot.capture(pb)
        pb.writeTransientText("x")
        snap.restore(to: pb)

        let items = pb.pasteboardItems ?? []
        #expect(items.count == 2)
        #expect(items[0].string(forType: .html) == "<b>rich</b>")
        #expect(items[1].string(forType: .string) == "second")
        pb.releaseGlobally()
    }

    @Test func emptyClipboardStaysEmpty() {
        let pb = scratchPasteboard()
        pb.clearContents()
        let snap = PasteboardSnapshot.capture(pb)
        pb.writeTransientText("x")
        snap.restore(to: pb)
        #expect(pb.string(forType: .string) == nil)
        pb.releaseGlobally()
    }

    @Test func transientItemIsMarkedForClipboardManagers() {
        let pb = scratchPasteboard()
        pb.writeTransientText("secret-ish")
        let types = pb.types ?? []
        #expect(types.contains(TransientPasteboardType.transient))
        #expect(types.contains(TransientPasteboardType.concealed))
        pb.releaseGlobally()
    }

    @Test func detectsWhenUserCopiedSomethingNew() {
        let pb = scratchPasteboard()
        let ours = pb.writeTransientText("dictated")
        #expect(pb.stillHoldsOurItem(changeCount: ours))
        pb.clearContents()
        pb.setString("user copied this meanwhile", forType: .string)
        #expect(!pb.stillHoldsOurItem(changeCount: ours))
        pb.releaseGlobally()
    }
}

@Suite("Insertion policy")
struct InsertionPolicyTests {
    @Test func secureInputNeverTypes() {
        #expect(InsertionPolicy.strategy(bundleID: "com.apple.Terminal", secureInputActive: true) == .clipboardOnly)
        #expect(InsertionPolicy.strategy(bundleID: nil, secureInputActive: true) == .clipboardOnly)
    }

    @Test func remoteDesktopTypesUnicode() {
        #expect(InsertionPolicy.strategy(bundleID: "com.apple.ScreenSharing", secureInputActive: false) == .typeUnicode)
    }

    @Test func everythingElsePastes() {
        for id in ["com.tinyspeck.slackmacgap", "com.todesktop.230313mzl4w4u92", "com.google.Chrome",
                   "com.anthropic.claudefordesktop", "com.apple.Terminal", "us.zoom.xos"] {
            #expect(InsertionPolicy.strategy(bundleID: id, secureInputActive: false) == .pasteShortcut)
        }
    }

    @Test func terminalTextNeverEndsInNewline() {
        let out = InsertionPolicy.sanitize("git status\n\n", for: .terminal)
        #expect(out == "git status")
    }

    @Test func terminalStripsControlCharactersButKeepsLines() {
        let out = InsertionPolicy.sanitize("line one\u{1B}[2J\nline two\u{07}", for: .terminal)
        #expect(out == "line one[2J\nline two")
    }

    @Test func otherAppsOnlyTrim() {
        #expect(InsertionPolicy.sanitize("  Hello, world.\n", for: .other) == "Hello, world.")
    }

    @Test func whitespaceOnlyBecomesEmpty() {
        #expect(InsertionPolicy.sanitize(" \n\t ", for: .other).isEmpty)
    }
}

@MainActor
@Suite("Clipboard guard")
struct ClipboardGuardTests {
    @Test func restoresUserClipboardAfterDelay() async {
        let pb = scratchPasteboard()
        pb.clearContents()
        pb.setString("user's clipboard", forType: .string)
        let g = ClipboardGuard(pasteboard: pb, delay: .milliseconds(20))
        let ours = g.lend("dictated")
        #expect(pb.string(forType: .string) == "dictated")
        await g.scheduleRestore(ours: ours).value
        #expect(pb.string(forType: .string) == "user's clipboard")
        pb.releaseGlobally()
    }

    /// Two dictations in quick succession must not "restore" the first dictation as your clipboard.
    @Test func backToBackDictationsKeepTheOriginalClipboard() async {
        let pb = scratchPasteboard()
        pb.clearContents()
        pb.setString("original", forType: .string)
        let g = ClipboardGuard(pasteboard: pb, delay: .milliseconds(50))
        let first = g.scheduleRestore(ours: g.lend("first dictation"))
        let second = g.scheduleRestore(ours: g.lend("second dictation"))  // before the first restore ran
        await first.value
        await second.value
        #expect(pb.string(forType: .string) == "original")
        pb.releaseGlobally()
    }

    @Test func doesNotClobberSomethingTheUserCopiedMeanwhile() async {
        let pb = scratchPasteboard()
        pb.clearContents()
        pb.setString("original", forType: .string)
        let g = ClipboardGuard(pasteboard: pb, delay: .milliseconds(30))
        let restore = g.scheduleRestore(ours: g.lend("dictated"))
        pb.clearContents()
        pb.setString("copied just now", forType: .string)
        await restore.value
        #expect(pb.string(forType: .string) == "copied just now")
        pb.releaseGlobally()
    }
}
