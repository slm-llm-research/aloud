import AgentKit
import AppKit

/// The window for agent tasks: approval cards ("InstructFlow wants to run: …" with Approve / Deny) and
/// the final result. Unlike the HUD it takes focus, because approving is a deliberate decision.
@MainActor
final class AgentPanel: NSObject, NSWindowDelegate {
    var onDecision: ((AgentProtocol.ApprovalRequest, Bool) -> Void)?
    var onStop: (() -> Void)?

    private let window: NSPanel
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(wrappingLabelWithString: "")
    private let previewView = NSTextView()
    private let scroll = NSScrollView()
    private let approveButton = NSButton(title: "Approve", target: nil, action: nil)
    private let denyButton = NSButton(title: "Deny", target: nil, action: nil)
    private let stopButton = NSButton(title: "Stop task", target: nil, action: nil)
    private var queue: [AgentProtocol.ApprovalRequest] = []
    private var current: AgentProtocol.ApprovalRequest?
    private var hideTask: Task<Void, Never>?

    override init() {
        window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 360),
                         styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: true)
        super.init()
        window.title = "InstructFlow agent"
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.delegate = self

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor

        previewView.isEditable = false
        previewView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        previewView.textContainerInset = NSSize(width: 6, height: 6)
        scroll.documentView = previewView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        previewView.autoresizingMask = [.width]

        approveButton.target = self
        approveButton.action = #selector(approve)
        approveButton.keyEquivalent = "\r"
        approveButton.keyEquivalentModifierMask = [.command]  // ⌘↩, so a stray Return can't approve
        approveButton.bezelColor = .systemBlue
        denyButton.target = self
        denyButton.action = #selector(deny)
        denyButton.keyEquivalent = "\u{1b}"  // Esc
        stopButton.target = self
        stopButton.action = #selector(stop)

        let buttons = NSStackView(views: [stopButton, NSView(), denyButton, approveButton])
        buttons.orientation = .horizontal
        let stack = NSStackView(views: [titleLabel, subtitleLabel, scroll, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = NSView()
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 180),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
        ])
    }

    // MARK: approvals

    func enqueue(_ req: AgentProtocol.ApprovalRequest) {
        queue.append(req)
        if current == nil { showNext() }
    }

    /// Drops cards for a task that ended (e.g. cancelled or timed out on the agent side).
    func taskEnded(_ taskId: String) {
        queue.removeAll { $0.taskId == taskId }
        if current?.taskId == taskId { current = nil; showNext() }
    }

    private func showNext() {
        hideTask?.cancel()
        guard !queue.isEmpty else {
            current = nil
            return
        }
        let req = queue.removeFirst()
        current = req
        titleLabel.stringValue = Self.title(for: req.tool)
        subtitleLabel.stringValue = "Effects: " + req.effects.map { $0.replacingOccurrences(of: "_", with: " ") }
            .joined(separator: ", ") + "   ·   ⌘↩ approve · Esc deny"
        previewView.string = req.preview
        approveButton.isHidden = false
        denyButton.isHidden = false
        stopButton.isHidden = false
        present()
    }

    static func title(for tool: String) -> String {
        switch tool {
        case "run_shell": return "Run this command?"
        case "write_file": return "Make this file change?"
        case "claude_code_task": return "Hand this to Claude Code?"
        default: return "Allow \(tool)?"
        }
    }

    @objc private func approve() { decide(true) }
    @objc private func deny() { decide(false) }

    private func decide(_ approved: Bool) {
        guard let req = current else { window.orderOut(nil); return }
        onDecision?(req, approved)
        current = nil
        if queue.isEmpty {
            showWorking()
        } else {
            showNext()
        }
    }

    @objc private func stop() {
        onStop?()
        queue.removeAll()
        current = nil
        window.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Closing the window with a pending card counts as Deny.
        if current != nil { decide(false) }
    }

    // MARK: status and result

    private func showWorking() {
        titleLabel.stringValue = "Working…"
        subtitleLabel.stringValue = "The agent continues; you'll be asked before anything else changes."
        previewView.string = ""
        approveButton.isHidden = true
        denyButton.isHidden = true
        hide(after: .seconds(2))
    }

    func showResult(_ summary: String, failed: Bool) {
        guard current == nil else { return }
        titleLabel.stringValue = failed ? "Task stopped" : "Task done"
        subtitleLabel.stringValue = ""
        previewView.string = summary
        approveButton.isHidden = true
        denyButton.isHidden = true
        stopButton.isHidden = true
        present()
        hide(after: .seconds(20))
    }

    private func hide(after delay: Duration) {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.current == nil else { return }
            self.window.orderOut(nil)
        }
    }

    private func present() {
        if !window.isVisible { window.center() }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
