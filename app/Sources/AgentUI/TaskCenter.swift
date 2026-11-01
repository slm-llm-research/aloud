import AgentKit
import AppKit
import Observation
import SwiftUI

/// The full view of the agent (research/08-agent-ui §3, "FULL"): every task, running or past, with
/// its plan, step timeline, result and cost, and any approval it is waiting for. A normal window
/// that you open on purpose (menu bar or the island), so unlike the island it may take focus.
@MainActor
public final class TaskCenter: NSObject, NSWindowDelegate {
    @MainActor @Observable
    final class Model {
        enum Filter: String, CaseIterable, Identifiable {
            case all = "All", running = "Running", needsYou = "Needs you", done = "Done", failed = "Failed"
            var id: String { rawValue }
        }
        var selection: String?
        var filter: Filter = .all
        var search = ""
    }

    public let store: TaskStore
    public var onDecision: ((AgentProtocol.ApprovalRequest, Bool) -> Void)?
    public var onStop: ((String) -> Void)?
    /// Asked to (re)load history from agentd when the window opens.
    public var onRefresh: (() -> Void)?

    private let model = Model()
    private var window: NSWindow?

    public init(store: TaskStore) {
        self.store = store
    }

    /// Opens the window, optionally on one task.
    public func show(select taskId: String? = nil) {
        if let taskId { model.selection = taskId; model.filter = .all; model.search = "" }
        if model.selection == nil { model.selection = store.tasks.first?.id }
        onRefresh?()
        let w = window ?? makeWindow()
        window = w
        if !w.isVisible { w.center() }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        var actions = IslandActions()
        actions.decide = { [weak self] req, approved in
            self?.store.resolveApproval(req.stepId)
            self?.onDecision?(req, approved)
        }
        actions.stop = { [weak self] id in self?.onStop?(id) }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 580),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
                         backing: .buffered, defer: true)
        w.title = "Agent Tasks"
        w.isReleasedWhenClosed = false
        w.minSize = NSSize(width: 680, height: 420)
        w.setFrameAutosaveName("AloudTaskCenter")
        w.contentView = NSHostingView(rootView: TaskCenterView(store: store, model: model, actions: actions))
        w.delegate = self
        return w
    }
}

// MARK: - Views

struct TaskCenterView: View {
    let store: TaskStore
    @Bindable var model: TaskCenter.Model
    let actions: IslandActions

    var body: some View {
        NavigationSplitView {
            TaskList(store: store, model: model)
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 380)
        } detail: {
            if let id = model.selection, let task = store.task(id) {
                TaskDetail(task: task, approvals: store.approvals.filter { $0.taskId == id }, actions: actions)
            } else {
                ContentUnavailableView("No task selected", systemImage: "list.bullet.rectangle",
                                       description: Text(store.tasks.isEmpty
                                                         ? "Hold Right Shift + Right ⌘ and say a task. It shows up here."
                                                         : "Choose a task on the left."))
            }
        }
    }
}

struct TaskList: View {
    let store: TaskStore
    @Bindable var model: TaskCenter.Model

    var body: some View {
        VStack(spacing: 0) {
            Picker("Show", selection: $model.filter) {
                ForEach(TaskCenter.Model.Filter.allCases) { f in
                    Text(count(f) > 0 && f != .all ? "\(f.rawValue) \(count(f))" : f.rawValue).tag(f)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            List(selection: $model.selection) {
                ForEach(shown) { t in
                    TaskListRow(task: t, waiting: store.approvals.contains { $0.taskId == t.id }).tag(t.id)
                }
            }
            .searchable(text: $model.search, placement: .sidebar, prompt: "Search tasks")
            .overlay {
                if shown.isEmpty {
                    Text(store.tasks.isEmpty ? "No tasks yet" : "Nothing matches")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var shown: [TaskStore.AgentTask] {
        let q = model.search.trimmingCharacters(in: .whitespaces).lowercased()
        return store.tasks.filter { t in
            matches(t, model.filter)
                && (q.isEmpty || t.heard.lowercased().contains(q) || t.summary.lowercased().contains(q)
                    || t.steps.contains { $0.title.lowercased().contains(q) })
        }
    }

    private func count(_ f: TaskCenter.Model.Filter) -> Int { store.tasks.filter { matches($0, f) }.count }

    private func matches(_ t: TaskStore.AgentTask, _ f: TaskCenter.Model.Filter) -> Bool {
        switch f {
        case .all: true
        case .running: t.state == .running
        case .needsYou: t.state == .waiting
        case .done: t.state == .done
        case .failed: t.state == .failed || t.state == .stopped || t.state == .interrupted
        }
    }
}

struct TaskListRow: View {
    let task: TaskStore.AgentTask
    let waiting: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            StateGlyph(state: task.state).frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(task.heard.isEmpty ? "(task)" : task.heard).lineLimit(2).font(.system(size: 12.5, weight: .medium))
                Text(subtitle).lineLimit(1).font(.system(size: 11)).foregroundStyle(waiting ? Color.orange : .secondary)
                HStack(spacing: 6) {
                    Text(task.startedAt, format: .relative(presentation: .named))
                    if task.endedAt != nil || task.isActive { Text("·"); Elapsed(task: task) }
                }
                .font(.system(size: 10.5)).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
    }

    private var subtitle: String {
        if waiting { return "Needs your OK" }
        return task.isActive ? task.currentActivity : (task.summary.isEmpty ? "—" : task.summary)
    }
}

struct TaskDetail: View {
    let task: TaskStore.AgentTask
    let approvals: [AgentProtocol.ApprovalRequest]
    let actions: IslandActions

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                ForEach(approvals) { InlineApproval(req: $0, actions: actions) }
                if !task.summary.isEmpty {
                    CardSection("Result") {
                        Text(task.summary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !task.plan.isEmpty {
                    CardSection("Plan · \(task.progressLabel)") {
                        ForEach(Array(task.plan.enumerated()), id: \.offset) { _, item in PlanRow(item: item) }
                    }
                }
                CardSection(task.steps.isEmpty ? "Steps" : "Steps · \(task.steps.count)") {
                    if task.steps.isEmpty {
                        Text(task.isActive ? (task.note.isEmpty ? "Planning…" : task.note) : "No tool steps.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(task.steps) { TimelineRow(step: $0) }
                    if task.isActive, !task.note.isEmpty, !task.steps.isEmpty {
                        Text(task.note).italic().foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                StateGlyph(state: task.state)
                Text(stateLabel).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                if task.isActive {
                    Button(role: .destructive) { actions.stop(task.id) } label: { Label("Stop", systemImage: "stop.fill") }
                }
                Button { copy(task.heard) } label: { Label("Copy request", systemImage: "doc.on.doc") }
                    .disabled(task.heard.isEmpty)
                if !task.summary.isEmpty {
                    Button { copy(task.summary) } label: { Label("Copy result", systemImage: "doc.on.clipboard") }
                }
            }
            .controlSize(.small)
            Text(task.heard.isEmpty ? "(no transcript)" : "“\(task.heard)”")
                .font(.system(size: 17, weight: .semibold)).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Text(task.startedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                Text("·")
                Elapsed(task: task)
                if task.outputTokens > 0 {
                    Text("·")
                    Text("\(TaskDrawer.tokens(task.inputTokens)) in / \(TaskDrawer.tokens(task.outputTokens)) out tokens")
                }
            }
            .font(.system(size: 11.5)).foregroundStyle(.secondary)
        }
    }

    private var stateLabel: String {
        switch task.state {
        case .running: "Running"
        case .waiting: "Needs your OK"
        case .done: "Done"
        case .failed: "Failed"
        case .stopped: "Stopped"
        case .interrupted: "Interrupted"
        }
    }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}

/// A titled group with a hairline card behind it.
private struct CardSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.system(size: 10.5, weight: .semibold)).tracking(0.5).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) { content }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08)))
        }
    }
}

/// One tool step with its full one-line result, risk and duration.
struct TimelineRow: View {
    let step: AgentProtocol.Step
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    StepIcon(step: step)
                    Text(step.title).font(.system(size: 12.5, weight: .medium)).textSelection(.enabled)
                    if step.risk != .read { RiskBadge(risk: step.risk) }
                    Spacer(minLength: 8)
                    Text(timing).font(.system(size: 10.5)).foregroundStyle(.tertiary).monospacedDigit()
                }
                if !step.result.isEmpty {
                    Text(step.result).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 22)
                }
            }
        }
    }

    private var timing: String {
        var parts: [String] = []
        if step.status == .denied { parts.append("denied") }
        if step.status == .blocked { parts.append("blocked") }
        if let s = step.startedAt, let e = step.endedAt { parts.append(String(format: "%.1f s", e.timeIntervalSince(s))) }
        return parts.joined(separator: " · ")
    }
}

struct StepIcon: View {
    let step: AgentProtocol.Step
    var body: some View {
        Image(systemName: icon).foregroundStyle(color).frame(width: 16)
    }
    private var icon: String {
        switch step.status {
        case .done: "checkmark.circle.fill"
        case .running: "arrow.triangle.2.circlepath.circle.fill"
        case .waiting: "hand.raised.circle.fill"
        case .error: "exclamationmark.circle.fill"
        case .blocked: "nosign"
        case .denied: "hand.thumbsdown.circle.fill"
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

/// The approval card's content inside the Task Center (same payload, same buttons).
struct InlineApproval: View {
    let req: AgentProtocol.ApprovalRequest
    let actions: IslandActions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(req.title.isEmpty ? "Allow \(req.tool)?" : req.title).font(.system(size: 13.5, weight: .semibold))
                RiskBadge(risk: req.risk)
                Spacer()
                if let exp = req.expiresAt { Countdown(until: exp) }
            }
            PayloadText(text: req.preview).padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            HStack {
                Spacer()
                Button("Deny") { actions.decide(req, false) }
                Button("Approve") { actions.decide(req, true) }.buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.35)))
    }
}
