import Foundation
import Testing
@testable import AgentKit

@Suite("Agent protocol")
struct AgentProtocolTests {
    @Test func requestsAreSingleLineJSONRPC() throws {
        let d = AgentProtocol.request(id: 7, method: "task.submit", params: ["utterance": "run the tests"])
        #expect(d.last == 0x0A)
        #expect(d.dropLast().contains(0x0A) == false)
        let obj = try #require(JSONSerialization.jsonObject(with: d.dropLast()) as? [String: Any])
        #expect(obj["jsonrpc"] as? String == "2.0")
        #expect(obj["id"] as? Int == 7)
        #expect((obj["params"] as? [String: String])?["utterance"] == "run the tests")
    }

    @Test func splitsLinesAndKeepsPartialData() {
        var buf = Data("{\"a\":1}\n{\"b\":2}\n{\"c\"".utf8)
        let lines = AgentProtocol.takeLines(&buf)
        #expect(lines.count == 2)
        #expect(String(decoding: buf, as: UTF8.self) == "{\"c\"")
        buf.append(Data(":3}\n".utf8))
        #expect(AgentProtocol.takeLines(&buf).count == 1)
        #expect(buf.isEmpty)
    }

    @Test func parsesResponses() {
        #expect(AgentProtocol.parse(Data(#"{"jsonrpc":"2.0","id":1,"result":{"taskId":"t-1"}}"#.utf8))
                == .response(id: 1, result: ["taskId": .string("t-1")], error: nil))
        #expect(AgentProtocol.parse(Data(#"{"jsonrpc":"2.0","id":2,"error":{"code":-32602,"message":"bad"}}"#.utf8))
                == .response(id: 2, result: nil, error: "bad"))
        #expect(AgentProtocol.parse(Data(#"{"id":3,"result":{"cancelled":2,"ok":true}}"#.utf8))
                == .response(id: 3, result: ["cancelled": .number(2), "ok": .bool(true)], error: nil))
    }

    @Test func parsesEvents() {
        let approval = #"{"jsonrpc":"2.0","method":"approval.request","params":{"taskId":"t","stepId":"s","tool":"run_shell","preview":"$ npm test","effects":["execute_process"]}}"#
        #expect(AgentProtocol.parse(Data(approval.utf8)) == .event(.approval(.init(
            taskId: "t", stepId: "s", tool: "run_shell", preview: "$ npm test", effects: ["execute_process"]))))
        #expect(AgentProtocol.parse(Data(#"{"method":"task.result","params":{"taskId":"t","summary":"Done."}}"#.utf8))
                == .event(.result(taskId: "t", summary: "Done.")))
        #expect(AgentProtocol.parse(Data(#"{"method":"task.error","params":{"taskId":"t","message":"cancelled"}}"#.utf8))
                == .event(.error(taskId: "t", message: "cancelled")))
        #expect(AgentProtocol.parse(Data("garbage".utf8)) == .unknown)
    }
}

/// Starts the real agentd on a temporary socket and pings it (no LLM call).
/// ALOUD_INTEGRATION=1 swift test --filter AgentLive   (needs `npm run build` in agentd/)
@MainActor
@Suite("AgentLive", .enabled(if: ProcessInfo.processInfo.environment["ALOUD_INTEGRATION"] == "1"))
struct AgentLiveTests {
    @Test func startsConnectsAndPings() async throws {
        let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../agentd/dist/main.js").standardized.path
        // Unix socket paths are limited to 104 bytes on macOS; keep the folder name short.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mm-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let config = dir.appendingPathComponent("agent.json")
        let socket = dir.appendingPathComponent("a.sock").path
        try #"{"socketPath":"\#(socket)","auditPath":"\#(dir.path)/audit.jsonl"}"#.write(to: config, atomically: true, encoding: .utf8)

        let node = try #require(AgentProcess.findNode())
        let p = Process()
        p.executableURL = URL(fileURLWithPath: node)
        p.arguments = [script]
        var env = ProcessInfo.processInfo.environment
        env["ALOUD_AGENT_CONFIG"] = config.path
        env["ANTHROPIC_API_KEY"] = env["ANTHROPIC_API_KEY"] ?? "test-key-not-used-for-ping"
        p.environment = env
        p.standardInput = Pipe()
        try p.run()
        defer { p.terminate() }

        let client = AgentClient(socketPath: socket)
        for _ in 0..<50 where !FileManager.default.fileExists(atPath: socket) { try await Task.sleep(for: .milliseconds(100)) }
        client.connect()
        for _ in 0..<50 where !client.isConnected { try await Task.sleep(for: .milliseconds(100)) }
        #expect(client.isConnected)
        let pong = try await client.call("ping")
        #expect(pong["ok"]?.bool == true)
        #expect(try await client.cancelAll() == 0)
        client.disconnect()
    }
}
