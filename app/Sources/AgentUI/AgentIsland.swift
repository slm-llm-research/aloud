import AgentKit
import AppKit
import Observation
import SwiftUI

/// The agent's one surface (research/08-agent-ui): a capsule at the top centre of the screen that
/// grows out of the notch where there is one. Compact while a task runs, a drawer with the plan and
/// steps on hover, and the approval card in place when a step needs you.
///
/// It is a non-activating panel, so it never takes focus from the app you're in. The approval card
/// only becomes key when you click it (then ⌘↩ / Esc / ⌘. work): taking key on its own would send
/// your next dictation into the card instead of your app.
@MainActor
public final class AgentIsland {
    /// What the island shows besides the store: hover, a task the user pinned from the menu, and
    /// finished tasks that are still on screen.
    @MainActor @Observable
    final class ViewState {
        var hovering = false
        var pinnedTask: String?
        /// Done tasks show their summary briefly; failures stay until dismissed.
        var recentlyEnded: Set<String> = []
        var dismissed: Set<String> = []
    }

    public let store: TaskStore
    public var onDecision: ((AgentProtocol.ApprovalRequest, Bool) -> Void)?
    public var onStop: ((String) -> Void)?

    private let panel: IslandPanel
    private let host: NSHostingView<IslandRoot>
    private let state = ViewState()

    public init(store: TaskStore) {
        self.store = store
        panel = IslandPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 40),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true  // before `level`: setting it resets the level to .floating
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        host = NSHostingView(rootView: IslandRoot(store: store, state: state, notch: 0,
                                                  actions: IslandActions()))
        // Report the content size (for fittingSize) without letting SwiftUI resize the panel itself.
        host.sizingOptions = [.intrinsicContentSize]
        panel.contentView = host
        rebuild()
        observe()
    }

    /// Shows a task in the drawer (from the menu's task list) until the pointer leaves it.
    public func focus(_ taskId: String) {
        state.pinnedTask = taskId
        state.dismissed.remove(taskId)
        layout()
        // Unpinned when the pointer leaves it, or after a while if it never arrives.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard let self, self.state.pinnedTask == taskId, !self.state.hovering else { return }
            self.state.pinnedTask = nil
        }
    }

    /// Called for every agent event, after the store has applied it.
    public func taskEnded(_ taskId: String, failed: Bool) {
        state.recentlyEnded.insert(taskId)
        guard !failed else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            self?.state.recentlyEnded.remove(taskId)
            self?.layout()
        }
    }

    private func rebuild() {
        var actions = IslandActions()
        actions.decide = { [weak self] req, approved in
            guard let self else { return }
            self.store.resolveApproval(req.stepId)
            self.onDecision?(req, approved)
            self.layout()
        }
        actions.stop = { [weak self] id in self?.onStop?(id) }
        actions.dismiss = { [weak self] id in
            self?.state.dismissed.insert(id)
            self?.state.recentlyEnded.remove(id)
            if self?.state.pinnedTask == id { self?.state.pinnedTask = nil }
            self?.layout()
        }
        actions.hover = { [weak self] inside in
            guard let self else { return }
            self.state.hovering = inside
            if !inside { self.state.pinnedTask = nil }
            self.layout()
        }
        actions.becomeKey = { [weak self] in self?.panel.makeKey() }
        host.rootView = IslandRoot(store: store, state: state, notch: notchHeight, actions: actions)
    }

    /// Re-lays out whenever anything the view reads changes.
    private func observe() {
        withObservationTracking {
            _ = store.tasks
            _ = store.approvals
            _ = state.hovering
            _ = state.pinnedTask
            _ = state.recentlyEnded
            _ = state.dismissed
        } onChange: { [weak self] in
            // After SwiftUI has applied the change, so fittingSize reflects the new content.
            DispatchQueue.main.async {
                self?.layout()
                self?.observe()
            }
        }
        layout()
    }

    private var screen: NSScreen? { NSScreen.main ?? NSScreen.screens.first }
    private var notchHeight: CGFloat { screen?.safeAreaInsets.top ?? 0 }

    private func layout() {
        let visible = IslandRoot.content(store: store, state: state) != .hidden
        guard visible, let screen else {
            if panel.isVisible { panel.orderOut(nil) }
            return
        }
        if host.rootView.notch != notchHeight { rebuild() }
        let size = host.fittingSize
        let f = screen.frame
        // With a notch the island hangs from the top edge (its top padding covers the notch);
        // otherwise it floats just under the menu bar.
        let top = notchHeight > 0 ? f.maxY : screen.visibleFrame.maxY - 6
        panel.setFrame(NSRect(x: f.midX - size.width / 2, y: top - size.height, width: size.width, height: size.height),
                       display: true)
        if !panel.isVisible { panel.orderFrontRegardless() }
        if store.currentApproval == nil, panel.isKeyWindow { panel.resignKey() }
    }
}

/// Borderless panels can't become key by default; the approval card needs it once clicked.
final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

struct IslandActions {
    var decide: (AgentProtocol.ApprovalRequest, Bool) -> Void = { _, _ in }
    var stop: (String) -> Void = { _ in }
    var dismiss: (String) -> Void = { _ in }
    var hover: (Bool) -> Void = { _ in }
    var becomeKey: () -> Void = {}
}

// MARK: - Views

struct IslandRoot: View {
    enum Content: Equatable {
        case hidden
        case approval
        case compact(String)
        case drawer(String)
    }

    let store: TaskStore
    let state: AgentIsland.ViewState
    let notch: CGFloat
    let actions: IslandActions

    /// Which surface to show: an approval always wins; then the pinned or hovered task; then the
    /// newest running task; then a just-finished or failed task that hasn't been dismissed.
    @MainActor
    static func content(store: TaskStore, state: AgentIsland.ViewState) -> Content {
        if store.currentApproval != nil { return .approval }
        if let id = state.pinnedTask, store.task(id) != nil { return .drawer(id) }
        let shown = store.activeTasks.first
            ?? store.tasks.first { state.recentlyEnded.contains($0.id) && !state.dismissed.contains($0.id) }
        guard let task = shown else { return .hidden }
        return state.hovering ? .drawer(task.id) : .compact(task.id)
    }

    var body: some View {
        let content = Self.content(store: store, state: state)
        VStack(spacing: 0) {
            switch content {
            case .hidden:
                EmptyView()
            case .approval:
                if let req = store.currentApproval {
                    ApprovalCard(req: req, task: store.task(req.taskId), queued: store.approvals.count - 1,
                                 actions: actions)
                }
            case .compact(let id):
                if let t = store.task(id) { CompactPill(task: t, others: store.activeTasks.count - 1) }
            case .drawer(let id):
                if let t = store.task(id) { TaskDrawer(task: t, actions: actions) }
            }
        }
        .padding(.top, notch > 0 ? notch + 4 : 0)
        .background(IslandShape(notch: notch > 0).fill(notch > 0 ? AnyShapeStyle(Color.black) : AnyShapeStyle(.regularMaterial)))
        .overlay(IslandShape(notch: notch > 0).stroke(Color.white.opacity(notch > 0 ? 0 : 0.12), lineWidth: 0.5))
        .environment(\.colorScheme, .dark)
        .fixedSize()
        .onHover { actions.hover($0) }
        .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .spring(duration: 0.3), value: content)
    }
}

/// A capsule, or (hanging from a notch) a shape with square top corners and round bottom ones.
struct IslandShape: Shape {
    var notch: Bool
    func path(in r: CGRect) -> Path {
        notch
            ? Path(UnevenRoundedRectangle(cornerRadii: .init(bottomLeading: 18, bottomTrailing: 18)).path(in: r).cgPath)
            : Path(RoundedRectangle(cornerRadius: min(18, r.height / 2), style: .continuous).path(in: r).cgPath)
    }
}

/// Glyph + colour + word for a state: never colour alone.
struct StateGlyph: View {
    let state: TaskStore.State
    var body: some View {
        switch state {
        case .running: ProgressView().controlSize(.mini).frame(width: 14, height: 14)
        case .waiting: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        case .stopped: Image(systemName: "stop.circle.fill").foregroundStyle(.secondary)
        }
    }
}

struct Elapsed: View {
    let task: TaskStore.AgentTask
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            Text(Self.format((task.endedAt ?? ctx.date).timeIntervalSince(task.startedAt)))
                .monospacedDigit()
        }
    }

    static func format(_ s: TimeInterval) -> String {
        let n = max(0, Int(s))
        return n < 60 ? "0:\(String(format: "%02d", n))" : "\(n / 60):\(String(format: "%02d", n % 60))"
    }
}

struct CompactPill: View {
    let task: TaskStore.AgentTask
    let others: Int

    var body: some View {
        HStack(spacing: 8) {
            StateGlyph(state: task.state)
            Text(line).lineLimit(task.isActive ? 1 : 2).truncationMode(.tail)
                .frame(maxWidth: task.isActive ? 300 : 380, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if !task.progressLabel.isEmpty, task.isActive {
                Text(task.progressLabel).foregroundStyle(.secondary).monospacedDigit()
            }
            if task.isActive { Elapsed(task: task).foregroundStyle(.secondary) }
            if others > 0 { Text("+\(others)").font(.caption.bold()).foregroundStyle(.secondary) }
        }
        .font(.system(size: 12.5, weight: .medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(minWidth: 220)
        .accessibilityElement(children: .combine)
    }

    private var line: String {
        switch task.state {
        case .running, .waiting: return task.currentActivity
        case .done, .failed, .stopped: return task.summary.isEmpty ? "Done." : task.summary
        }
    }
}

struct TaskDrawer: View {
    let task: TaskStore.AgentTask
    let actions: IslandActions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                StateGlyph(state: task.state)
                Text(heading).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 12)
                Elapsed(task: task).foregroundStyle(.secondary)
                if task.outputTokens > 0 {
                    Text("· \(Self.tokens(task.inputTokens + task.outputTokens)) tokens").foregroundStyle(.secondary)
                }
                if task.isActive {
                    Button { actions.stop(task.id) } label: { Image(systemName: "stop.fill") }
                        .buttonStyle(.borderless).help("Stop this task")
                } else {
                    Button { actions.dismiss(task.id) } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless).help("Dismiss")
                }
            }
            .font(.system(size: 11.5))
            if !task.heard.isEmpty {
                Text("Heard: “\(task.heard)”").font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(2)
            }
            Divider().opacity(0.4)
            if !task.plan.isEmpty {
                ForEach(Array(task.plan.enumerated()), id: \.offset) { _, item in
                    PlanRow(item: item)
                }
            }
            let steps = task.steps.suffix(task.plan.isEmpty ? 6 : 3)
            if !steps.isEmpty {
                if !task.plan.isEmpty { Text("Steps").font(.caption2).foregroundStyle(.tertiary) }
                ForEach(Array(steps)) { StepRow(step: $0) }
            }
            if task.plan.isEmpty, steps.isEmpty, task.isActive {
                Text(task.note.isEmpty ? "Planning…" : task.note).font(.system(size: 12)).foregroundStyle(.secondary)
            } else if task.isActive, !task.note.isEmpty {
                Text(task.note).font(.system(size: 11.5)).italic().foregroundStyle(.secondary).lineLimit(2)
            }
            if !task.isActive, !task.summary.isEmpty {
                Text(task.summary).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(width: 420, alignment: .leading)
    }

    private var heading: String {
        switch task.state {
        case .running: return "Working"
        case .waiting: return "Needs your OK"
        case .done: return "Done"
        case .failed: return "Failed"
        case .stopped: return "Stopped"
        }
    }

    static func tokens(_ n: Int) -> String { n < 1000 ? "\(n)" : String(format: "%.1fk", Double(n) / 1000) }
}

struct PlanRow: View {
    let item: AgentProtocol.PlanItem
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 14)
            Text(item.content).strikethrough(item.status == .canceled)
                .foregroundStyle(item.status == .pending ? .secondary : .primary)
        }
        .font(.system(size: 12))
    }
    private var icon: String {
        switch item.status {
        case .completed: "checkmark.circle.fill"
        case .inProgress: "circle.dotted.circle"
        case .pending: "circle"
        case .canceled: "minus.circle"
        case .failed: "xmark.circle.fill"
        }
    }
    private var color: Color {
        switch item.status {
        case .completed: .green
        case .inProgress: .blue
        case .failed: .red
        case .pending, .canceled: .secondary
        }
    }
}

struct StepRow: View {
    let step: AgentProtocol.Step
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(step.title).lineLimit(1)
                if !step.result.isEmpty, step.status != .running {
                    Text(step.result).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let s = step.startedAt, let e = step.endedAt {
                Text(String(format: "%.1f s", e.timeIntervalSince(s))).font(.system(size: 10.5)).foregroundStyle(.tertiary)
            }
        }
        .font(.system(size: 12))
    }
    private var icon: String {
        switch step.status {
        case .done: "checkmark"
        case .running: "arrow.triangle.2.circlepath"
        case .waiting: "hand.raised.fill"
        case .error: "exclamationmark.circle"
        case .blocked: "nosign"
        case .denied: "hand.thumbsdown"
        }
    }
    private var color: Color {
        switch step.status {
        case .done: .green
        case .running: .blue
        case .waiting: .orange
        case .error, .blocked: .red
        case .denied: .secondary
        }
    }
}

struct ApprovalCard: View {
    let req: AgentProtocol.ApprovalRequest
    let task: TaskStore.AgentTask?
    let queued: Int
    let actions: IslandActions
    /// A keystroke meant for another app must not approve: buttons arm after a short delay.
    @State private var armed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("Needs your OK").font(.system(size: 13, weight: .semibold))
                RiskBadge(risk: req.risk)
                Spacer(minLength: 12)
                if let exp = req.expiresAt { Countdown(until: exp) }
            }
            Text(title).font(.system(size: 14, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            if let heard = task?.heard, !heard.isEmpty {
                Text("For: “\(heard)”").font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(2)
            }
            ScrollView {
                PayloadText(text: req.preview).frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            .frame(maxHeight: 220)
            .fixedSize(horizontal: false, vertical: true)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
            HStack(spacing: 8) {
                Button("Stop task") { actions.stop(req.taskId) }
                    .keyboardShortcut(".", modifiers: .command)
                if queued > 0 { Text("\(queued) more waiting").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button("Deny") { actions.decide(req, false) }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Approve") { actions.decide(req, true) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(!armed)
            }
            .controlSize(.regular)
            Text("Click the card, then ⌘↩ approve · Esc deny · ⌘. stop")
                .font(.system(size: 10.5)).foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(width: 480, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { actions.becomeKey() }
        .task(id: req.stepId) {
            armed = false
            try? await Task.sleep(for: .milliseconds(400))
            armed = true
        }
        .onAppear {
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                 userInfo: [.announcement: "InstructFlow agent needs your approval: \(title)",
                                            .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
    }

    private var title: String {
        if !req.title.isEmpty { return req.title }
        switch req.tool {
        case "run_shell": return "Run this command?"
        case "write_file": return "Make this file change?"
        case "claude_code_task": return "Hand this to Claude Code?"
        default: return "Allow \(req.tool)?"
        }
    }
}

struct RiskBadge: View {
    let risk: AgentProtocol.Risk
    var body: some View {
        Text(label).font(.system(size: 9.5, weight: .bold)).tracking(0.6)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.22)))
            .foregroundStyle(color)
    }
    private var label: String {
        switch risk {
        case .read: "READ"
        case .low: "WRITES FILES"
        case .medium: "RUNS A COMMAND"
        case .high: "SENDS / PUBLISHES"
        case .blocked: "BLOCKED"
        }
    }
    private var color: Color {
        switch risk {
        case .read: .secondary
        case .low: .yellow
        case .medium: .orange
        case .high, .blocked: .red
        }
    }
}

struct Countdown: View {
    let until: Date
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let left = until.timeIntervalSince(ctx.date)
            Text("auto-deny \(Elapsed.format(left))")
                .font(.system(size: 11)).monospacedDigit()
                .foregroundStyle(left < 20 ? Color.red : Color.secondary)
        }
    }
}

/// The exact payload, monospaced; diff lines ("+ ", "- ") are tinted.
struct PayloadText: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(text.split(separator: "\n", omittingEmptySubsequences: false).prefix(400).enumerated()),
                    id: \.offset) { _, line in
                Text(line.isEmpty ? " " : String(line))
                    .foregroundStyle(line.hasPrefix("+ ") ? Color.green : line.hasPrefix("- ") ? Color.red : Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(line.hasPrefix("+ ") ? Color.green.opacity(0.08) : line.hasPrefix("- ") ? Color.red.opacity(0.08) : .clear)
            }
        }
        .font(.system(size: 11.5, design: .monospaced))
        .textSelection(.enabled)
    }
}
