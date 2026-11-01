import Foundation
import Testing
@testable import AgentKit

@MainActor
@Suite("Task store")
struct TaskStoreTests {
    typealias P = AgentProtocol

    func step(_ id: String, _ status: P.StepStatus, title: String = "Run swift test in app") -> P.Event {
        .step(P.Step(taskId: "t", stepId: id, tool: "run_shell", title: title, risk: .medium, status: status))
    }

    @Test func aTaskGoesFromRunningToWaitingAndBack() {
        let s = TaskStore()
        s.apply(.started(taskId: "t", utterance: "run the tests"))
        #expect(s.task("t")?.state == .running)
        s.apply(step("s1", .waiting))
        s.apply(.approval(P.ApprovalRequest(taskId: "t", stepId: "s1", tool: "run_shell", preview: "$ swift test",
                                            effects: ["execute_process"])))
        #expect(s.task("t")?.state == .waiting)
        #expect(s.currentApproval?.stepId == "s1")
        s.resolveApproval("s1")
        #expect(s.currentApproval == nil)
        #expect(s.task("t")?.state == .running)
        s.apply(step("s1", .running))
        s.apply(step("s1", .done))
        #expect(s.task("t")?.steps.count == 1)
        #expect(s.task("t")?.steps.first?.status == .done)
        s.apply(.result(taskId: "t", summary: "All 35 tests passed."))
        #expect(s.task("t")?.state == .done)
        #expect(s.activeTasks.isEmpty)
    }

    @Test func progressComesFromThePlanWhenThereIsOne() {
        let s = TaskStore()
        s.apply(.started(taskId: "t", utterance: "tidy downloads"))
        #expect(s.task("t")?.currentActivity == "Planning…")
        s.apply(.plan(taskId: "t", steps: [.init(content: "List Downloads", status: .completed),
                                            .init(content: "Move old files", status: .inProgress),
                                            .init(content: "Summarise", status: .pending)]))
        #expect(s.task("t")?.progressLabel == "1/3")
        #expect(s.task("t")?.currentActivity == "Move old files")
        s.apply(step("s2", .running, title: "Run mv in Downloads"))
        #expect(s.task("t")?.currentActivity == "Run mv in Downloads")
    }

    @Test func endingATaskDropsItsCardsAndCancelsOpenPlanItems() {
        let s = TaskStore()
        s.apply(.started(taskId: "t", utterance: "x"))
        s.apply(.plan(taskId: "t", steps: [.init(content: "a", status: .inProgress)]))
        s.apply(.approval(P.ApprovalRequest(taskId: "t", stepId: "s1", tool: "write_file", preview: "", effects: [])))
        s.apply(.error(taskId: "t", message: "cancelled"))
        #expect(s.approvals.isEmpty)
        #expect(s.task("t")?.state == .stopped)
        #expect(s.task("t")?.plan.first?.status == .canceled)
    }

    @Test func historyIsCappedButRunningTasksStay() {
        let s = TaskStore()
        s.apply(.started(taskId: "live", utterance: "long job"))
        for i in 0..<30 {
            s.apply(.started(taskId: "\(i)", utterance: "job \(i)"))
            s.apply(.result(taskId: "\(i)", summary: "ok"))
        }
        #expect(s.tasks.count == TaskStore.historyLimit)
        #expect(s.task("live")?.isActive == true)
        #expect(s.tasks.first?.id == "29")
    }

    @Test func parsesTimelineEvents() {
        let plan = #"{"method":"task.plan","params":{"taskId":"t","steps":[{"content":"List","status":"completed"},{"content":"Move","status":"inProgress"}]}}"#
        #expect(P.parse(Data(plan.utf8)) == .event(.plan(taskId: "t", steps: [.init(content: "List", status: .completed),
                                                                              .init(content: "Move", status: .inProgress)])))
        let step = #"{"method":"task.step","params":{"taskId":"t","stepId":"s","tool":"run_shell","title":"Run ls","risk":"medium","status":"done","result":"ok","startedAt":1000,"endedAt":3000}}"#
        guard case .event(.step(let st)) = P.parse(Data(step.utf8)) else { Issue.record("not a step"); return }
        #expect(st.status == .done && st.risk == .medium && st.title == "Run ls")
        #expect(st.endedAt == Date(timeIntervalSince1970: 3))
        let card = #"{"method":"approval.request","params":{"taskId":"t","stepId":"s","tool":"run_shell","preview":"$ ls","effects":["execute_process"],"title":"Run ls in app","risk":"high","expiresAt":120000}}"#
        guard case .event(.approval(let req)) = P.parse(Data(card.utf8)) else { Issue.record("not a card"); return }
        #expect(req.title == "Run ls in app" && req.risk == .high && req.expiresAt == Date(timeIntervalSince1970: 120))
    }
}
