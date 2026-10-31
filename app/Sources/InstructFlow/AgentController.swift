import AgentKit
import AppKit
import InstructFlowCore

/// Owns the agent side of the app: starts agentd, forwards spoken tasks, shows approvals/results,
/// and provides the kill switch.
@MainActor
final class AgentController: TaskSubmitting {
    static let configURL = AppDelegate.supportDir.appendingPathComponent("agent.json")
    static let socketPath = AppDelegate.supportDir.appendingPathComponent("agentd.sock").path
    /// The daemon in the same checkout as the app: <repo>/app/build/InstructFlow.app -> <repo>/agentd/dist/main.js
    /// (override with "agentdScript" in agent.json).
    static let defaultScript = Bundle.main.bundleURL
        .deletingLastPathComponent()  // app/build
        .deletingLastPathComponent()  // app
        .deletingLastPathComponent()  // repo
        .appendingPathComponent("agentd/dist/main.js").path

    let client = AgentClient(socketPath: socketPath)
    private let panel = AgentPanel()
    private var process: AgentProcess?
    private let hud: HUD
    private(set) var activeTasks = Set<String>()
    var onChange: (() -> Void)?

    init(hud: HUD) {
        self.hud = hud
        client.onEvent = { [weak self] in self?.handle($0) }
        client.onConnectionChange = { [weak self] up in
            dlog("agent: \(up ? "connected" : "disconnected")")
            self?.onChange?()
        }
        panel.onDecision = { [weak self] req, approved in
            dlog("agent: \(approved ? "approved" : "denied") \(req.tool)")
            Task { try? await self?.client.respond(stepId: req.stepId, approve: approved) }
        }
        panel.onStop = { [weak self] in self?.stopAll() }
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
        return activeTasks.isEmpty ? "Agent: ready" : "Agent: \(activeTasks.count) task(s) running"
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

    private func handle(_ event: AgentProtocol.Event) {
        switch event {
        case .started(let id, let utterance):
            activeTasks.insert(id)
            hud.showMessage("Agent: \(utterance)")
            dlog("agent: started \(id)")
        case .progress(_, let message):
            hud.showMessage("Agent: \(message)", for: .seconds(6))
        case .approval(let req):
            dlog("agent: approval requested for \(req.tool)")
            panel.enqueue(req)
        case .result(let id, let summary):
            activeTasks.remove(id)
            panel.taskEnded(id)
            panel.showResult(summary, failed: false)
            dlog("agent: done \(id): \(summary)")
        case .error(let id, let message):
            activeTasks.remove(id)
            panel.taskEnded(id)
            panel.showResult(message == "cancelled" ? "Stopped." : "The task failed: \(message)", failed: true)
            dlog("agent: error \(id): \(message)")
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
