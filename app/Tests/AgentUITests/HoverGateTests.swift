import AppKit
import SwiftUI
import Testing
@testable import AgentKit
@testable import AgentUI

@Suite("Island hover")
struct HoverGateTests {
    @Test func opensOnlyAfterThePointerSettles() {
        var g = HoverGate()
        #expect(g.update(inside: true, now: 0) == nil)
        #expect(g.update(inside: true, now: 0.05) == nil)
        #expect(g.update(inside: true, now: 0.13) == true)
        #expect(g.hovering)
    }

    @Test func passingByDoesNotOpen() {
        var g = HoverGate()
        _ = g.update(inside: true, now: 0)
        #expect(g.update(inside: false, now: 0.08) == nil)
        #expect(g.update(inside: true, now: 0.15) == nil)  // timer restarted
        #expect(!g.hovering)
    }

    /// The flicker: a resize used to report exit+enter under a still pointer. A blip outside
    /// shorter than the exit delay must not close the drawer.
    @Test func briefExitKeepsItOpen() {
        var g = HoverGate()
        _ = g.update(inside: true, now: 0)
        _ = g.update(inside: true, now: 0.2)
        #expect(g.update(inside: false, now: 0.3) == nil)
        #expect(g.update(inside: true, now: 0.4) == nil)
        #expect(g.update(inside: false, now: 0.5) == nil)
        #expect(g.update(inside: false, now: 0.9) == false)
    }

    /// The top-aligned frame that keeps content still during a delayed shrink must not change the
    /// size the island reports (it would grow the panel to the whole screen).
    @MainActor @Test func reportedSizeIsTheContentSize() {
        let s = TaskStore()
        s.apply(.started(taskId: "t", utterance: "check git status"))
        let host = NSHostingView(rootView: IslandRoot(store: s, state: AgentIsland.ViewState(), notch: 0,
                                                      actions: IslandActions()))
        host.sizingOptions = [.intrinsicContentSize]
        let size = host.fittingSize
        #expect(size.width > 100 && size.width < 600)
        #expect(size.height > 20 && size.height < 120)
    }
}
