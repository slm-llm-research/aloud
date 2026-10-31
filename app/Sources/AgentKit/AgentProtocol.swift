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
        public var id: String { stepId }
    }

    public enum Event: Equatable, Sendable {
        case started(taskId: String, utterance: String)
        case progress(taskId: String, message: String)
        case approval(ApprovalRequest)
        case result(taskId: String, summary: String)
        case error(taskId: String, message: String)
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
        switch method {
        case "task.started": return .event(.started(taskId: s("taskId"), utterance: s("utterance")))
        case "task.progress": return .event(.progress(taskId: s("taskId"), message: s("message")))
        case "task.result": return .event(.result(taskId: s("taskId"), summary: s("summary")))
        case "task.error": return .event(.error(taskId: s("taskId"), message: s("message")))
        case "approval.request":
            return .event(.approval(ApprovalRequest(taskId: s("taskId"), stepId: s("stepId"), tool: s("tool"),
                                                    preview: s("preview"), effects: p["effects"] as? [String] ?? [])))
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
