import Foundation
import Network

public enum AgentClientError: Error, Equatable {
    case notConnected
    case server(String)
    case timeout
}

/// Talks to aloud-agentd over its Unix socket. Reconnects automatically; events arrive on the main
/// actor via `onEvent`.
@MainActor
public final class AgentClient {
    public var onEvent: ((AgentProtocol.Event) -> Void)?
    public var onConnectionChange: ((Bool) -> Void)?
    public private(set) var isConnected = false

    private let socketPath: String
    private var connection: NWConnection?
    private var buffer = Data()
    private var nextID = 1
    private var waiters: [Int: CheckedContinuation<[String: AnyCodableValue], Error>] = [:]
    private let queue = DispatchQueue(label: "aloud.agentclient")
    private var reconnectTask: Task<Void, Never>?

    public init(socketPath: String) {
        self.socketPath = socketPath
    }

    public func connect() {
        reconnectTask?.cancel()
        connection?.cancel()
        let conn = NWConnection(to: .unix(path: socketPath), using: .tcp)
        connection = conn
        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in self?.handle(state: state, conn: conn) }
        }
        conn.start(queue: queue)
    }

    public func disconnect() {
        reconnectTask?.cancel()
        connection?.cancel()
        connection = nil
        setConnected(false)
    }

    private func handle(state: NWConnection.State, conn: NWConnection) {
        guard conn === connection else { return }
        switch state {
        case .ready:
            setConnected(true)
            receive(on: conn)
        case .failed, .waiting, .cancelled:
            setConnected(false)
            failWaiters(AgentClientError.notConnected)
            if case .cancelled = state { return }
            scheduleReconnect()
        default:
            break
        }
    }

    private func setConnected(_ value: Bool) {
        guard value != isConnected else { return }
        isConnected = value
        onConnectionChange?(value)
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.connect()
        }
    }

    private func receive(on conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self, conn === self.connection else { return }
                if let data { self.consume(data) }
                if isComplete || error != nil {
                    conn.cancel()
                    self.setConnected(false)
                    self.failWaiters(AgentClientError.notConnected)
                    self.scheduleReconnect()
                } else {
                    self.receive(on: conn)
                }
            }
        }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        for line in AgentProtocol.takeLines(&buffer) {
            switch AgentProtocol.parse(line) {
            case .response(let id, let result, let error):
                guard let w = waiters.removeValue(forKey: id) else { continue }
                if let error { w.resume(throwing: AgentClientError.server(error)) } else { w.resume(returning: result ?? [:]) }
            case .event(let e):
                onEvent?(e)
            case .unknown:
                continue
            }
        }
    }

    private func failWaiters(_ error: Error) {
        let all = waiters
        waiters.removeAll()
        for (_, w) in all { w.resume(throwing: error) }
    }

    @discardableResult
    public func call(_ method: String, _ params: [String: Any] = [:], timeout: Duration = .seconds(5)) async throws
        -> [String: AnyCodableValue]
    {
        guard let conn = connection, isConnected else { throw AgentClientError.notConnected }
        let id = nextID
        nextID += 1
        let data = AgentProtocol.request(id: id, method: method, params: params)
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.waiters.removeValue(forKey: id)?.resume(throwing: AgentClientError.timeout)
        }
        defer { timeoutTask.cancel() }
        return try await withCheckedThrowingContinuation { cont in
            waiters[id] = cont
            conn.send(content: data, completion: .contentProcessed { [weak self] error in
                guard let error else { return }
                Task { @MainActor in self?.waiters.removeValue(forKey: id)?.resume(throwing: error) }
            })
        }
    }

    public func submit(utterance: String, context: [String: String]) async throws -> String {
        let r = try await call("task.submit", ["utterance": utterance, "context": context])
        return r["taskId"]?.string ?? ""
    }

    public func respond(stepId: String, approve: Bool) async throws {
        try await call("approval.respond", ["stepId": stepId, "decision": approve ? "approve" : "deny"])
    }

    /// Finished tasks from agentd's audit log, newest first (running ones come from live events).
    @MainActor
    public func history(limit: Int = 50) async throws -> [TaskStore.AgentTask] {
        let r = try await call("task.history", ["limit": limit])
        return TaskStore.parseHistory(r["tasks"]?.json ?? Data("[]".utf8))
    }

    @discardableResult
    public func cancel(taskId: String) async throws -> Bool {
        try await call("task.cancel", ["taskId": taskId])["cancelled"]?.bool ?? false
    }

    @discardableResult
    public func cancelAll() async throws -> Int {
        Int(try await call("task.cancelAll")["cancelled"]?.number ?? 0)
    }
}
