import Foundation

/// Wire format for instructflow-agentd: JSON-RPC 2.0, one JSON object per line, over a Unix socket
/// (agentd/src/rpc.ts). Pure and unit-tested; `AgentClient` does the I/O.
public enum AgentProtocol {
    public struct ApprovalRequest: Equatable, Sendable, Identifiable {
        public var taskId: String
        public var stepId: String
        public var tool: String
        public var preview: String
        public var effects: [String]
        /// Card data from agentd (absent from older daemons): plain title, risk badge, auto-deny time.
        public var title: String = ""
        public var risk: Risk = .medium
        public var expiresAt: Date?
        public var id: String { stepId }

        public init(taskId: String, stepId: String, tool: String, preview: String, effects: [String],
                    title: String = "", risk: Risk = .medium, expiresAt: Date? = nil) {
            self.taskId = taskId
            self.stepId = stepId
            self.tool = tool
            self.preview = preview
            self.effects = effects
            self.title = title
            self.risk = risk
            self.expiresAt = expiresAt
        }
    }

    /// agentd's effects.ts `riskOf`.
    public enum Risk: String, Equatable, Sendable {
        case read, low, medium, high, blocked
    }

    public enum StepStatus: String, Equatable, Sendable {
        case waiting, running, done, error, blocked, denied
    }

    /// One tool call in a task's timeline (task.step); later events for the same stepId replace it.
    public struct Step: Equatable, Sendable, Identifiable {
        public var taskId: String
        public var stepId: String
        public var tool: String
        public var title: String
        public var risk: Risk
        public var status: StepStatus
        public var result: String
        public var startedAt: Date?
        public var endedAt: Date?
        public var id: String { stepId }

        public init(taskId: String, stepId: String, tool: String, title: String, risk: Risk = .read,
                    status: StepStatus, result: String = "", startedAt: Date? = nil, endedAt: Date? = nil) {
            self.taskId = taskId
            self.stepId = stepId
            self.tool = tool
            self.title = title
            self.risk = risk
            self.status = status
            self.result = result
            self.startedAt = startedAt
            self.endedAt = endedAt
        }
    }

    public enum PlanStatus: String, Equatable, Sendable {
        case pending, inProgress, completed, canceled, failed
    }

    public struct PlanItem: Equatable, Sendable {
        public var content: String
        public var status: PlanStatus
        public init(content: String, status: PlanStatus) {
            self.content = content
            self.status = status
        }
    }

    public enum Event: Equatable, Sendable {
        case started(taskId: String, utterance: String)
        case progress(taskId: String, message: String)
        case approval(ApprovalRequest)
        case result(taskId: String, summary: String)
        case error(taskId: String, message: String)
        case plan(taskId: String, steps: [PlanItem])
        case step(Step)
        case note(taskId: String, text: String)
        case metrics(taskId: String, inputTokens: Int, outputTokens: Int)
    }

    public enum Incoming: Equatable, Sendable {
        case response(id: Int, result: [String: AnyCodableValue]?, error: String?)
        case event(Event)
        case unknown
    }

    public static func request(id: Int, method: String, params: [String: Any] = [:]) -> Data {
        var obj: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method]
        if !params.isEmpty { obj["params"] = params }
        var data = (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])) ?? Data()
        data.append(0x0A)
        return data
    }

    /// Splits complete lines off `buffer` (leaving any partial line in it).
    public static func takeLines(_ buffer: inout Data) -> [Data] {
        var lines: [Data] = []
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            if !line.isEmpty { lines.append(Data(line)) }
        }
        return lines
    }

    public static func parse(_ line: Data) -> Incoming {
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return .unknown }
        if let id = obj["id"] as? Int {
            let err = (obj["error"] as? [String: Any])?["message"] as? String
            let result = (obj["result"] as? [String: Any])?.compactMapValues(AnyCodableValue.init)
            return .response(id: id, result: result, error: err)
        }
        guard let method = obj["method"] as? String, let p = obj["params"] as? [String: Any] else { return .unknown }
        let s = { (k: String) in p[k] as? String ?? "" }
        let date = { (k: String) in (p[k] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) } }
        switch method {
        case "task.started": return .event(.started(taskId: s("taskId"), utterance: s("utterance")))
        case "task.progress": return .event(.progress(taskId: s("taskId"), message: s("message")))
        case "task.result": return .event(.result(taskId: s("taskId"), summary: s("summary")))
        case "task.error": return .event(.error(taskId: s("taskId"), message: s("message")))
        case "approval.request":
            return .event(.approval(ApprovalRequest(taskId: s("taskId"), stepId: s("stepId"), tool: s("tool"),
                                                    preview: s("preview"), effects: p["effects"] as? [String] ?? [],
                                                    title: s("title"), risk: Risk(rawValue: s("risk")) ?? .medium,
                                                    expiresAt: date("expiresAt"))))
        case "task.plan":
            let items = (p["steps"] as? [[String: Any]] ?? []).compactMap { d -> PlanItem? in
                guard let c = d["content"] as? String else { return nil }
                return PlanItem(content: c, status: PlanStatus(rawValue: d["status"] as? String ?? "") ?? .pending)
            }
            return .event(.plan(taskId: s("taskId"), steps: items))
        case "task.step":
            guard let status = StepStatus(rawValue: s("status")) else { return .unknown }
            return .event(.step(Step(taskId: s("taskId"), stepId: s("stepId"), tool: s("tool"), title: s("title"),
                                     risk: Risk(rawValue: s("risk")) ?? .read, status: status, result: s("result"),
                                     startedAt: date("startedAt"), endedAt: date("endedAt"))))
        case "task.note": return .event(.note(taskId: s("taskId"), text: s("text")))
        case "task.metrics":
            return .event(.metrics(taskId: s("taskId"), inputTokens: p["inputTokens"] as? Int ?? 0,
                                   outputTokens: p["outputTokens"] as? Int ?? 0))
        default: return .unknown
        }
    }
}

/// The few JSON scalar types responses carry, made Equatable/Sendable.
public enum AnyCodableValue: Equatable, Sendable {
    case string(String), number(Double), bool(Bool)

    public init?(_ any: Any) {
        if let n = any as? NSNumber {
            // JSONSerialization returns NSNumber for both; booleans are CFBoolean underneath.
            self = CFGetTypeID(n) == CFBooleanGetTypeID() ? .bool(n.boolValue) : .number(n.doubleValue)
        } else if let s = any as? String {
            self = .string(s)
        } else {
            return nil
        }
    }

    public var string: String? { if case .string(let s) = self { s } else { nil } }
    public var number: Double? { if case .number(let n) = self { n } else { nil } }
    public var bool: Bool? { if case .bool(let b) = self { b } else { nil } }
}
