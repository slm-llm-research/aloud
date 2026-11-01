import AgentKit
import AgentUI
import AppKit
import AloudCore

/// Owns the agent side of the app: starts agentd, forwards spoken tasks, feeds the task store that
/// the agent island and the menu show, and provides the kill switch.
@MainActor
final class AgentController: TaskSubmitting {
    static let configURL = AppDelegate.supportDir.appendingPathComponent("agent.json")
    static let socketPath = AppDelegate.supportDir.appendingPathComponent("agentd.sock").path
    /// The daemon in the same checkout as the app: <repo>/app/build/Aloud.app -> <repo>/agentd/dist/main.js
    /// (override with "agentdScript" in agent.json).
    static let defaultScript = Bundle.main.bundleURL
        .deletingLastPathComponent()  // app/build
        .deletingLastPathComponent()  // app
        .deletingLastPathComponent()  // repo
        .appendingPathComponent("agentd/dist/main.js").path

    let client = AgentClient(socketPath: socketPath)
    let store = TaskStore()
    private(set) lazy var island = AgentIsland(store: store)
    private(set) lazy var center = TaskCenter(store: store)
    private var process: AgentProcess?
    private let hud: HUD
    var onChange: (() -> Void)?

    init(hud: HUD) {
        self.hud = hud
        client.onEvent = { [weak self] in self?.handle($0) }
        client.onConnectionChange = { [weak self] up in
            dlog("agent: \(up ? "connected" : "disconnected")")
            if up { self?.loadHistory() }
            self?.onChange?()
        }
        island.onDecision = { [weak self] req, approved in
            dlog("agent: \(approved ? "approved" : "denied") \(req.tool)")
            Task { try? await self?.client.respond(stepId: req.stepId, approve: approved) }
        }
        island.onStop = { [weak self] id in self?.stop(id) }
        island.onOpenCenter = { [weak self] id in self?.center.show(select: id) }
        center.onDecision = { [weak self] req, approved in
            dlog("agent: \(approved ? "approved" : "denied") \(req.tool) (Task Center)")
            Task { try? await self?.client.respond(stepId: req.stepId, approve: approved) }
        }
        center.onStop = { [weak self] id in self?.stop(id) }
        center.onRefresh = { [weak self] in self?.loadHistory() }
    }

    func start() {
        ensureConfig()
        let settings = (try? JSONSerialization.jsonObject(with: Data(contentsOf: Self.configURL))) as? [String: Any] ?? [:]
        let script = (settings["agentdScript"] as? String) ?? Self.defaultScript
        guard let node = (settings["nodePath"] as? String) ?? AgentProcess.findNode() else {
            dlog("agent: node not found; task mode unavailable")
            return
        }
        let p = AgentProcess(config: .init(nodePath: node, mainScript: script))
        p.onLog = { dlog($0) }
        p.start()
        process = p
        client.connect()
    }

    func shutdown() {
        process?.stop()
        client.disconnect()
    }

    /// Settings are read when agentd starts; restart it to apply changes.
    func restart() {
        dlog("agent: restarting to apply settings")
        process?.stop()
        process = nil
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            start()
        }
    }

    var statusText: String {
        if !client.isConnected { return "Agent: off" }
        let active = store.activeTasks
        if active.isEmpty { return "Agent: ready" }
        let waiting = active.filter { $0.state == .waiting }.count
        return "Agent: \(active.count) running" + (waiting > 0 ? " · \(waiting) needs you" : "")
    }

    // MARK: TaskSubmitting

    func submit(task: String, context: DictationContext) async -> Bool {
        var ctx: [String: String] = [:]
        if let a = context.appName { ctx["app"] = a }
        if let b = context.bundleID { ctx["bundleId"] = b }
        if let w = context.windowTitle { ctx["windowTitle"] = w }
        do {
            let id = try await client.submit(utterance: task, context: ctx)
            dlog("agent: submitted task \(id): \(task)")
            return true
        } catch {
            dlog("agent: submit failed: \(error)")
            return false
        }
    }

    /// The kill switch: cancels every running task (kills their processes) and denies pending approvals.
    func stopAll() {
        Task {
            let n = (try? await client.cancelAll()) ?? 0
            dlog("agent: stop all -> cancelled \(n)")
            hud.showMessage(n > 0 ? "Stopped \(n) agent task(s)" : "No agent tasks running")
        }
    }

    /// Past tasks from agentd's audit log, so the Task Center survives app restarts.
    func loadHistory() {
        Task {
            do {
                store.mergeHistory(try await client.history(limit: TaskStore.historyLimit))
            } catch {
                dlog("agent: history failed: \(error)")
            }
        }
    }

    /// Stops one task (the island's stop button, ⌘. on its card).
    func stop(_ taskId: String) {
        Task {
            let ok = (try? await client.cancel(taskId: taskId)) ?? false
            dlog("agent: stop \(taskId) -> \(ok)")
        }
    }

    private func handle(_ event: AgentProtocol.Event) {
        store.apply(event)
        switch event {
        case .started(let id, _):
            dlog("agent: started \(id)")
        case .approval(let req):
            dlog("agent: approval requested for \(req.tool)")
        case .result(let id, let summary):
            island.taskEnded(id, failed: false)
            dlog("agent: done \(id): \(summary)")
        case .error(let id, let message):
            island.taskEnded(id, failed: message != "cancelled")
            dlog("agent: error \(id): \(message)")
        case .step(let s) where s.status == .blocked || s.status == .error:
            dlog("agent: step \(s.status.rawValue) \(s.tool): \(s.result)")
        case .progress, .plan, .step, .note, .metrics:
            break
        }
        onChange?()
    }

    /// Writes a starter agent.json so the allowed folders are visible and editable.
    private func ensureConfig() {
        guard !FileManager.default.fileExists(atPath: Self.configURL.path) else { return }
        let starter = """
        {
          "allowedRoots": [],
          "model": "claude-opus-5-5",
          "effort": "low",
          "approvalTimeoutMs": 120000
        }

        """
        try? starter.write(to: Self.configURL, atomically: true, encoding: .utf8)
    }
}
