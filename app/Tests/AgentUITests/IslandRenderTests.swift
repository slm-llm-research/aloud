import AppKit
import Foundation
import SwiftUI
import Testing
@testable import AgentKit
@testable import AgentUI

/// Renders each island state to PNG for a visual check (the island lives above the menu bar, where
/// screenshots need Screen Recording permission). Enabled by INSTRUCTFLOW_RENDER_DIR; run it alone
/// (`swift test --filter IslandRender`): it spins the main run loop, which slows main-actor tests.
@MainActor
@Suite("Island render", .enabled(if: ProcessInfo.processInfo.environment["INSTRUCTFLOW_RENDER_DIR"] != nil))
struct IslandRenderTests {
    static let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["INSTRUCTFLOW_RENDER_DIR"] ?? "/tmp")
    typealias P = AgentProtocol

    func store() -> TaskStore {
        let start = Date().addingTimeInterval(-41)
        let s = TaskStore(now: { start })
        s.apply(.started(taskId: "t", utterance: "clean up my downloads folder and archive the old stuff"))
        s.apply(.plan(taskId: "t", steps: [.init(content: "List ~/Downloads", status: .completed),
                                            .init(content: "Find files older than 30 days", status: .completed),
                                            .init(content: "Move them into Archive", status: .inProgress),
                                            .init(content: "Summarise", status: .pending)]))
        s.apply(.step(.init(taskId: "t", stepId: "a", tool: "list_dir", title: "List ~/Downloads", status: .done,
                            result: "212 entries", startedAt: start, endedAt: start.addingTimeInterval(0.4))))
        s.apply(.step(.init(taskId: "t", stepId: "b", tool: "find_files", title: "Find files older than 30 days",
                            status: .done, result: "42 files", startedAt: start, endedAt: start.addingTimeInterval(1.2))))
        s.apply(.metrics(taskId: "t", inputTokens: 18_200, outputTokens: 2_100))
        return s
    }

    /// Through a real NSHostingView in an offscreen window, so AppKit-backed controls draw too.
    func render(_ view: some View, _ name: String) throws {
        let host = NSHostingView(rootView: view.padding(24).background(Color(white: 0.55)))
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try png.write(to: Self.dir.appendingPathComponent("island-\(name).png"))
    }

    func root(_ s: TaskStore, notch: CGFloat = 0, hovering: Bool = false) -> IslandRoot {
        let state = AgentIsland.ViewState()
        state.hovering = hovering
        return IslandRoot(store: s, state: state, notch: notch, actions: IslandActions())
    }

    @Test func renderStates() throws {
        let s = store()
        try render(root(s), "compact")
        try render(root(s, notch: 32), "compact-notch")
        try render(root(s, hovering: true), "drawer")

        s.apply(.step(.init(taskId: "t", stepId: "c", tool: "run_shell", title: "Run mv in Downloads", risk: .medium, status: .waiting)))
        s.apply(.approval(P.ApprovalRequest(
            taskId: "t", stepId: "c", tool: "write_file",
            preview: "Change ~/Documents/notes/todo.md:\n  # Today\n- - ship the island\n+ - [x] ship the island\n+ - [ ] record the demo\n  - review BUG-001",
            effects: ["write_local"], title: "Change todo.md", risk: .low, expiresAt: Date().addingTimeInterval(78))))
        try render(root(s), "approval")

        s.resolveApproval("c")
        s.apply(.result(taskId: "t", summary: "Moved 42 files into ~/Downloads/Archive. Nothing was deleted."))
        let state = AgentIsland.ViewState()
        state.recentlyEnded = ["t"]
        try render(IslandRoot(store: s, state: state, notch: 0, actions: IslandActions()), "done")
    }
}
