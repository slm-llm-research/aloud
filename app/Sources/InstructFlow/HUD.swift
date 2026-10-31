import AppKit
import InstructFlowCore

/// The small floating pill near the bottom of the screen. It is a non-activating panel, so showing it
/// never steals focus from the app you're dictating into.
@MainActor
final class HUD {
    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "")
    private var hideTask: Task<Void, Never>?

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 40),
                        styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let bg = NSVisualEffectView(frame: panel.contentView!.bounds)
        bg.material = .hudWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 20
        bg.autoresizingMask = [.width, .height]
        panel.contentView = bg

        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.frame = bg.bounds.insetBy(dx: 14, dy: 11)
        label.autoresizingMask = [.width, .height]
        bg.addSubview(label)
    }

    func show(_ status: SessionStatus) {
        hideTask?.cancel()
        switch status {
        case .idle:
            panel.orderOut(nil)
            return
        case .listening(.dictation): label.stringValue = "● Listening…"
        case .listening(.task): label.stringValue = "● Listening for a task…"
        case .listening(.command): label.stringValue = "● Listening for an edit…"
        case .transcribing: label.stringValue = "Transcribing…"
        case .inserted: label.stringValue = "✓"
        case .failed(let msg): label.stringValue = msg
        }
        position()
        panel.orderFrontRegardless()
        switch status {
        case .inserted: hide(after: .milliseconds(600))
        case .failed: hide(after: .seconds(3))
        default: break
        }
    }

    /// A transient status line (agent progress etc.) that isn't a dictation state.
    func showMessage(_ text: String, for duration: Duration = .seconds(3)) {
        hideTask?.cancel()
        label.stringValue = text
        position()
        panel.orderFrontRegardless()
        hide(after: duration)
    }

    private func hide(after delay: Duration) {
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.panel.orderOut(nil)
        }
    }

    private func position() {
        guard let screen = NSScreen.main else { return }
        let w = max(140, min(420, label.attributedStringValue.size().width + 40))
        let f = screen.visibleFrame
        panel.setFrame(NSRect(x: f.midX - w / 2, y: f.minY + 60, width: w, height: 40), display: true)
    }
}
