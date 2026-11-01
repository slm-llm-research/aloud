import Foundation
import Observation

/// Everything the agent UI shows, built from agentd's events: tasks with their plan, steps and
/// state, plus the queue of approvals waiting for the user. Pure state (no AppKit), unit-tested by
/// replaying event sequences; the island and the menu read it.
@MainActor
@Observable
public final class TaskStore {
    public enum State: Equatable, Sendable {
        case running, waiting, done, failed, stopped
    }

    public struct AgentTask: Equatable, Sendable, Identifiable {
        public var id: String
        /// What the user said (after cleanup).
        public var heard: String
        public var state: State = .running
        public var plan: [AgentProtocol.PlanItem] = []
        public var steps: [AgentProtocol.Step] = []
        /// The model's latest one-line commentary between tools.
        public var note: String = ""
        public var summary: String = ""
        public var startedAt: Date
        public var endedAt: Date?
        public var inputTokens = 0
        public var outputTokens = 0

        /// "3/5" from the plan when there is one, else completed tool steps.
        public var progressLabel: String {
            if !plan.isEmpty {
                return "\(plan.filter { $0.status == .completed }.count)/\(plan.count)"
            }
            let done = steps.filter { $0.status == .done }.count
            return done == 0 ? "" : "\(done) step\(done == 1 ? "" : "s")"
        }

        /// The line for the compact island: the step in progress, else the plan item, else the note.
        public var currentActivity: String {
            if let s = steps.last(where: { $0.status == .running || $0.status == .waiting }) { return s.title }
            if let p = plan.first(where: { $0.status == .inProgress }) { return p.content }
            if !note.isEmpty { return note }
            return steps.last?.title ?? "Planning…"
        }

        public var isActive: Bool { state == .running || state == .waiting }
    }

    /// Newest first; finished tasks are kept (capped) so the menu can show recent history.
    public private(set) var tasks: [AgentTask] = []
    public private(set) var approvals: [AgentProtocol.ApprovalRequest] = []
    public static let historyLimit = 20

    private let now: () -> Date

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    public var activeTasks: [AgentTask] { tasks.filter(\.isActive) }
    /// The approval on screen; others wait their turn.
    public var currentApproval: AgentProtocol.ApprovalRequest? { approvals.first }

    public func task(_ id: String) -> AgentTask? { tasks.first { $0.id == id } }

    public func apply(_ event: AgentProtocol.Event) {
        switch event {
        case .started(let id, let utterance):
            tasks.removeAll { $0.id == id }
            tasks.insert(AgentTask(id: id, heard: utterance, startedAt: now()), at: 0)
            trim()
        case .progress:
            break  // superseded by task.step; old daemons still get a timeline from approvals and results
        case .plan(let id, let steps):
            update(id) { $0.plan = steps }
        case .step(let step):
            update(step.taskId) { t in
                if let i = t.steps.firstIndex(where: { $0.stepId == step.stepId }) { t.steps[i] = step } else { t.steps.append(step) }
            }
            if step.status != .waiting { approvals.removeAll { $0.stepId == step.stepId } }
            refreshWaiting(step.taskId)
        case .note(let id, let text):
            update(id) { $0.note = text }
        case .metrics(let id, let input, let output):
            update(id) { $0.inputTokens = input; $0.outputTokens = output }
        case .approval(let req):
            if !approvals.contains(where: { $0.stepId == req.stepId }) { approvals.append(req) }
            if task(req.taskId) == nil {  // approval from a task we missed the start of (app restarted)
                tasks.insert(AgentTask(id: req.taskId, heard: "", startedAt: now()), at: 0)
            }
            refreshWaiting(req.taskId)
        case .result(let id, let summary):
            finish(id, state: .done, summary: summary)
        case .error(let id, let message):
            finish(id, state: message == "cancelled" ? .stopped : .failed,
                   summary: message == "cancelled" ? "Stopped." : message)
        }
    }

    /// The user answered (or the card was dismissed): the card goes away at once, before agentd confirms.
    public func resolveApproval(_ stepId: String) {
        let taskId = approvals.first { $0.stepId == stepId }?.taskId
        approvals.removeAll { $0.stepId == stepId }
        if let taskId { refreshWaiting(taskId) }
    }

    private func finish(_ id: String, state: State, summary: String) {
        approvals.removeAll { $0.taskId == id }
        update(id) { t in
            t.state = state
            t.summary = summary
            t.endedAt = self.now()
            for i in t.plan.indices where t.plan[i].status == .inProgress || t.plan[i].status == .pending {
                if state != .done { t.plan[i].status = .canceled }
            }
        }
    }

    private func refreshWaiting(_ id: String) {
        let waiting = approvals.contains { $0.taskId == id }
        update(id) { t in
            guard t.isActive else { return }
            t.state = waiting ? .waiting : .running
        }
    }

    private func update(_ id: String, _ change: (inout AgentTask) -> Void) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        change(&tasks[i])
    }

    private func trim() {
        while tasks.count > Self.historyLimit, let i = tasks.lastIndex(where: { !$0.isActive }) { tasks.remove(at: i) }
    }
}
