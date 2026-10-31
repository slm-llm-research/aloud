import AppKit

/// Lends the user's clipboard to a paste and gives it back afterwards, in the background, so the
/// dictation finishes as soon as Cmd-V is posted.
///
/// Back-to-back dictations are the tricky case: if a second paste starts before the first restore
/// ran, snapshotting "the clipboard" would capture our own dictated text and later "restore" that.
/// So while a restore is pending, the original snapshot is reused and only the latest restore runs.
@MainActor
public final class ClipboardGuard {
    private let pasteboard: NSPasteboard
    private let delay: Duration
    private var pendingSnapshot: PasteboardSnapshot?
    private var pendingRestore: Task<Void, Never>?

    public init(pasteboard: NSPasteboard, delay: Duration = .milliseconds(450)) {
        self.pasteboard = pasteboard
        self.delay = delay
    }

    /// Puts `text` on the clipboard (marked transient) and returns the change count to verify later.
    public func lend(_ text: String) -> Int {
        let snapshot = pendingSnapshot ?? PasteboardSnapshot.capture(pasteboard)
        pendingRestore?.cancel()
        pendingSnapshot = snapshot
        return pasteboard.writeTransientText(text)
    }

    /// Schedules the restore. Skipped if the user copied something new in the meantime.
    @discardableResult
    public func scheduleRestore(ours: Int) -> Task<Void, Never> {
        let task = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.delay)
            if Task.isCancelled { return }
            if self.pasteboard.stillHoldsOurItem(changeCount: ours), let snap = self.pendingSnapshot {
                snap.restore(to: self.pasteboard)
            }
            self.pendingSnapshot = nil
            self.pendingRestore = nil
        }
        pendingRestore = task
        return task
    }
}
