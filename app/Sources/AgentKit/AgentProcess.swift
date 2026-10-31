import Foundation

/// Starts instructflow-agentd (`node agentd/dist/main.js`) as a child of the app and restarts it if it
/// crashes. agentd exits when its stdin closes, so it never outlives InstructFlow.
@MainActor
public final class AgentProcess {
    public struct Config: Equatable, Sendable {
        public var nodePath: String
        public var mainScript: String
        public init(nodePath: String, mainScript: String) {
            self.nodePath = nodePath
            self.mainScript = mainScript
        }
    }

    public var onLog: ((String) -> Void)?
    private let config: Config
    private var process: Process?
    private var stdinPipe: Pipe?
    private var restarts = 0
    private var stopping = false

    public init(config: Config) {
        self.config = config
    }

    /// Finds node in the usual places (GUI apps don't inherit your shell's PATH).
    public static func findNode() -> String? {
        ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public var isRunning: Bool { process?.isRunning ?? false }

    public func start() {
        guard !isRunning else { return }
        stopping = false
        guard FileManager.default.isExecutableFile(atPath: config.nodePath),
              FileManager.default.fileExists(atPath: config.mainScript) else {
            onLog?("agentd: not started (node at \(config.nodePath) or \(config.mainScript) missing; run `npm run build` in agentd)")
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: config.nodePath)
        p.arguments = [config.mainScript]
        let input = Pipe()
        let output = Pipe()
        p.standardInput = input
        p.standardOutput = output
        p.standardError = output
        output.fileHandleForReading.readabilityHandler = { [weak self] h in
            let text = String(decoding: h.availableData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            Task { @MainActor in self?.onLog?(text) }
        }
        p.terminationHandler = { [weak self] proc in
            Task { @MainActor in self?.terminated(status: proc.terminationStatus) }
        }
        do {
            try p.run()
            process = p
            stdinPipe = input
            onLog?("agentd: started (pid \(p.processIdentifier))")
        } catch {
            onLog?("agentd: failed to start: \(error)")
        }
    }

    public func stop() {
        stopping = true
        try? stdinPipe?.fileHandleForWriting.close()
        process?.terminate()
        process = nil
    }

    private func terminated(status: Int32) {
        onLog?("agentd: exited (status \(status))")
        process = nil
        guard !stopping, restarts < 5 else { return }
        restarts += 1
        Task {
            try? await Task.sleep(for: .seconds(2))
            start()
        }
    }
}
