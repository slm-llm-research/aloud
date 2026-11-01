# 08. Making the Background Agent Visible: UI Report

*Research date: 2026-10-31. Scope: how InstructFlow should show what `agentd` is doing (planning, acting, waiting for approval, finished) in a polished, native macOS way.*

The detailed research (how ~12 agent products show background work, the macOS surfaces and APIs, design guidance, and four concepts with wireframes) is in **[E. Agent UI patterns](E-agent-ui-patterns.md)**. This document is the decision and the build plan, tied to the current code.

---

## 1. TL;DR

1. **The UI isn't really the bottleneck; the data is.** Today agentd sends the app five events, and "progress" is one string (the first line of a step's preview). Claude Code runs with `--output-format text` and says nothing for up to 20 minutes, and the planner doesn't stream. No UI can show a plan, a timeline, live output or cost from that. **Step one is a richer event model** (section 4).
2. **Recommended design: three surfaces on one shared `TaskStore`.**
   - **Agent Island** at the top centre of the screen, hugging the notch where there is one. It shows live state at a glance, expands on hover into the plan and a live tail, and turns into the **approval card in place, without taking focus from your current app**. It replaces both today's bottom pill and the approval window.
   - **Task Center** in the menu bar: every task (running, needs you, done, failed), each task's step timeline, diffs, cost and time, and history.
   - **Notifications** only as a fallback when the island isn't visible (full-screen apps, another Space). They never carry an "Approve" button.
3. **Approval cards become the centrepiece.** They show the plain-language action, a risk badge from the declared Effect, the **exact** payload (a real diff for file writes, the exact command and folder for shell), a one-line "why", a scope choice and a visible auto-deny countdown. Shortcuts are ⌘↩ approve, Esc deny and ⌘. stop, all working without bringing InstructFlow to the front.
4. **Voice belongs in the same surfaces:** show what was heard, the live states (listening → transcribing → planning → acting → waiting → done), "hold Right Shift to steer" while a task runs, and a short spoken summary on completion.
5. **Effort:** about 1 week for the event model and store, 1 to 1.5 weeks for the Task Center, and 2 to 3 weeks for the island. A cut-down version (store + Task Center + new approval card) fits in about 10 days and already fixes "I can't see what the agent is doing".

---

## 2. What the user sees today, and why

Read from `app/Sources/InstructFlow/` and `agentd/src/`:

| Moment | Today | Problem |
|---|---|---|
| Task starts | HUD pill at the bottom: "Agent: \<what you said\>" for 3 s (`AgentController.handle(.started)`) | Disappears; nothing persistent shows a task is running |
| Agent works | Each `task.progress` flashes the first line of a tool preview for 6 s | One line at a time, no plan, no "step 3 of 6", nothing during long steps |
| Claude Code runs | Nothing. `claude_code_task` uses `--output-format text` and returns only at the end (up to 20 min) | The longest, most interesting work is completely invisible |
| Approval needed | `AgentPanel`: a titled utility window that **activates the app and steals focus**; shows tool name, raw effects, monospaced preview | Pulls you out of what you're doing; no diff; no risk level; no countdown even though agentd auto-denies at 2 min |
| Several tasks | Approvals queue in one window; progress lines from different tasks overwrite each other in the pill | No way to tell tasks apart |
| Task ends | Summary in the panel, hidden after 20 s | Lost unless you open the audit log JSONL |
| Menu bar | Static "Agent: N task(s) running" line | No list, no detail, no history |

Root causes in the protocol (`agentd/src/rpc.ts`, `AgentKit/AgentProtocol.swift`):
- Events are `task.started`, `task.progress {message}`, `approval.request`, `task.result`, `task.error`. There is **no structure**: no plan, no step identity, no tool result, no timing, no tokens or cost, and no "waiting" state separate from the approval itself.
- The planner (`ClaudePlanner.run`) awaits the SDK tool runner's final message, so model text and reasoning never stream.
- `claude_code_task` blocks with `runProcess` and text output.
- History exists only as the audit JSONL; the app can't query it.

---

## 3. Target experience

**Glance → peek → full.** Each level has its own surface, and the same state drives all three.

```
GLANCE: island at the notch (or a capsule at top-centre on displays without one)
┌──────────────────────────────[■■ notch ■■]──────────────────────────────┐
│                     ( ◐ Tidy Downloads · 3/5 · 0:41 )                    │
└──────────────────────────────────────────────────────────────────────────┘
   states: ● listening · ⋯ transcribing · ◔ planning · ◐ acting
           ⚠ needs you (amber, widens) · ✓ done · ✕ failed

PEEK: hover, or Right Shift + /
          ┌────────────────────────[■■ notch ■■]────────────────────────┐
          │ ◐ Tidy Downloads                         0:41 · $0.03   ⏹  │
          │ Heard: "clean up my downloads folder, archive old stuff"    │
          │ ✓ List ~/Downloads (212 items)                              │
          │ ✓ Find files older than 30 days (42)                        │
          │ ◐ Create ~/Downloads/Archive                                │
          │ ○ Move 42 files                                             │
          │ ○ Summarise                                                 │
          │ ── live ─────────────────────────────────────────────────  │
          │ > mkdir -p ~/Downloads/Archive                              │
          │ Hold ⇧ to steer                        Open Task Center ↗  │
          └─────────────────────────────────────────────────────────────┘

APPROVAL: the island morphs in place; your current app keeps focus
          ┌────────────────────────[■■ notch ■■]────────────────────────┐
          │ ⚠ Needs your OK              [ WRITE LOCAL ]  auto-deny 1:18│
          │ Move 42 files into ~/Downloads/Archive                       │
          │ Why: they match "older than 30 days" from your request      │
          │ ┌─────────────────────────────────────────────────────────┐ │
          │ │ invoice-2026-08.pdf   → Archive/                         │ │
          │ │ screenshot-0912.png   → Archive/        … 40 more ▾      │ │
          │ └─────────────────────────────────────────────────────────┘ │
          │ ☐ Allow writes in ~/Downloads for the rest of this task     │
          │ [Deny  esc]      [Edit…]      [Stop ⌘.]      [Approve  ⌘↩]  │
          └─────────────────────────────────────────────────────────────┘

FULL: Task Center (menu-bar glyph ◐ with an amber "needs you" count)
┌───────────────────────────────────────────────────────────────────────┐
│ Agent            [Running 2] [Needs you 1] [Done] [History]        ⚙  │
├───────────────────────────────────────────────────────────────────────┤
│ ⚠ Draft reply to vendor email      needs approval · 0:42              │
│ ◐ Fix failing test (Claude Code)   step 3/6 · 2:10 · $0.21            │
│ ✓ Tidy Downloads                   42 files moved · 10:31             │
├───────────────────────────────────────────────────────────────────────┤
│ Fix failing test                                            ⏹ Stop    │
│  ✓ thought   Reading the test output…                    (collapsed)  │
│  ✓ action    run_shell  swift test --filter Parser          4.1 s     │
│  ◐ action    claude_code_task  repo: app/                             │
│     │ Edit Sources/Parser.swift (+12 −3)            [View diff]       │
│     │ Running tests…                                                  │
│  18.2k in / 2.1k out · $0.21 · 2:10                                   │
│ [ Steer… ]                                          [ Open History ]  │
└───────────────────────────────────────────────────────────────────────┘
```

### 3.1 Interruption rules

The agent should be easy to see but never pushy:

| Event | Treatment | Escalation |
|---|---|---|
| Step progress | Island text updates, at most 4 per second | none |
| Plan created or changed | One pulse (none with Reduce Motion) | none |
| **Approval needed** | Island expands to the card + soft sound + VoiceOver announcement | 20 s: pulse again · 60 s: time-sensitive notification with **Review… / Deny** · 120 s: agentd's existing auto-deny, recorded in history |
| Clarifying question | Same as approval; answer by holding Right Shift and speaking | same |
| Done | ✓ + one-line summary for 8 s, then a badge on the menu-bar glyph | notification only if the island wasn't visible |
| Error | Red island state with the reason, stays until dismissed | standard notification |

**Never activate the app or take focus for anything except an approval card, and even then only key status in a non-activating panel.** Approve works only while the card is on screen and at least ~400 ms after it appeared, so a keystroke meant for another app can't approve by accident.

### 3.2 Approval card contents (in order)

1. **Verb + object in plain language:** "Run `swift test` in `app/`", "Write 1 file in `notes/`", "Hand this to Claude Code in `voice-flow`". Today's titles ("Allow write_file?") are a start; drive them from a per-tool `title(input)` in the ToolContract.
2. **Risk badge from the Effect:** read = no card; `write_local` amber; `execute_process` amber+; `network_write` / `send_message` red. Blocked effects never show an Approve button.
3. **Exact payload:** a unified diff for file writes (new files all green), the exact command plus folder plus which allowlist entry it matched for shell, recipient/subject/body for messages, repo plus instruction for Claude Code.
4. **Why:** one sentence of the model's rationale, labelled as the model's words, never as a description of what will run. Everything above it comes from the typed call.
5. **Scope:** "this step" by default; optionally "allow `write_local` in this folder for the rest of this task". Never a standing "always" for send or network writes.
6. **Countdown** to auto-deny, since agentd already enforces 2 minutes.
7. **Buttons:** Approve ⌘↩ · Deny Esc · Edit… (adjust the payload, such as the command or commit message) · Stop task ⌘.

### 3.3 Voice in the UI

- **Show what was heard**, both the raw transcript and the cleaned intent, at the top of every task. Most "the agent did the wrong thing" moments are really "it heard the wrong thing", and showing this builds trust.
- **Live states** in the island: listening (live level meter) → transcribing → planning → acting → waiting → done.
- **Steer without stopping:** while a task runs, hold Right Shift and speak ("use the Archive-2026 folder instead"). The text is sent as `task.steer` and appears in the timeline as your message.
- **Spoken summary (optional):** at most two sentences when a task finishes or needs you ("Moved 42 files. Nothing was deleted."). Never read diffs, paths or code aloud. Use ElevenLabs TTS when a key is set, otherwise the system voice; mute it during calls and while the mic is hot.
- **"Status?"** as a spoken query answered from the store with no model call, which lays the groundwork for the multi-agent fleet control in report 07.

---

## 4. The event model (do this first)

Replace the five events with typed activities. Based on Linear's agent activity contract, Claude Code's `stream-json` output and Warp's agent blocks [E §4]:

```ts
// agentd -> app (JSON-RPC notifications)
task.created   {taskId, title, transcript, intent, context, ts}
task.plan      {taskId, steps: [{id, content, status: "pending"|"inProgress"|"completed"|"canceled"|"failed"}]}  // full array each time
task.activity  {taskId, activityId, kind: "thought"|"action"|"question"|"response"|"error",
                stepId?, tool?, title?, effects?, args?, result?, startedAt, endedAt?}
task.delta     {taskId, activityId, channel: "reasoning"|"text"|"stdout"|"stderr", text}   // throttled ≤ 4 Hz
task.cc        {taskId, event}          // Claude Code stream-json lines, passed through
task.awaiting  {taskId, approvalId, kind: "approval"|"question",
                card: {verb, object, effect, risk, payload, diff?, rationale?, scopeOptions}, expiresAt}
task.metrics   {taskId, inputTokens, outputTokens, costUsd, elapsedMs, toolCalls}
task.state     {taskId, state: "active"|"awaitingInput"|"complete"|"error"|"canceled"|"stale"}

// app -> agentd
approval.respond {approvalId, decision: "approve"|"deny"|"edit", editedPayload?, scope, via}
task.steer     {taskId, text, via: "voice"|"text"}
task.stop      {taskId}
task.list / task.get {taskId} / task.history {limit, before}   // served from the audit JSONL
```

How each piece gets its data:

| Event | Source in agentd |
|---|---|
| `task.plan` | A small `update_plan` tool the planner calls first and whenever the plan changes (the same pattern as Claude Code's TodoWrite). Effect `read_local`, no approval. |
| `task.activity` / `task.delta` | Switch `ClaudePlanner` from awaiting `toolRunner`'s final message to iterating its streaming events (text and thinking deltas, tool-use start/stop). `gatedRun` emits `action` start/end around each tool. |
| `task.cc` | Change `claude_code_task` to `--output-format stream-json --verbose --include-partial-messages`, and parse lines as they arrive in `runProcess` instead of at exit. Forward edits as activities with file names and +/− counts. |
| `task.awaiting` | `ApprovalBroker.request` builds the card from the ToolContract: add optional `title(input)`, `risk(input)` and `diff(input)` methods to `ToolContract`. `write_file` computes a unified diff against the file on disk. |
| `task.metrics` | `usage` from each API response (+ Claude Code's `total_cost_usd`). |
| `task.state` = `stale` | No event for 10 s while active (Linear's rule), so the UI can say "still working…" honestly. |
| `task.history` | Read back from `agent-audit.jsonl`, which already records task start, steps, approvals and results. |

Keep sending the old events for one release so the current UI keeps working while the new one is built.

---

## 5. App architecture

```
AgentKit (Swift package target)
  AgentProtocol.swift      + v2 event types (Codable structs, not hand-parsed dictionaries)
  AgentClient.swift        unchanged transport (unix socket, line JSON)
  TaskStore.swift   NEW    @Observable: tasks by id, plan, activities, live tail (ring buffer),
                           metrics, pending approvals queue, history paging; pure and unit-tested

InstructFlow (app target)
  Island/          NEW     IslandPanel (NSPanel .borderless+.nonactivatingPanel, level .statusBar,
                           .canJoinAllSpaces, .fullScreenAuxiliary), placed by the notch-side areas;
                           SwiftUI views: CompactPill, PeekDrawer, ApprovalCard, VoiceStateView
  TaskCenter/      NEW     MenuBarExtra(.window) or NSStatusItem + NSPanel; TaskListView, TimelineView,
                           DiffView, HistoryView
  Notifications/   NEW     UNUserNotificationCenter: "Review…" + "Deny/Stop" actions only
  AgentPanel.swift         retired once ApprovalCard ships
  HUD.swift                dictation states move into the island; keep the pill as a fallback setting
```

Implementation notes [E §2]:
- **Notch placement:** there is no public notch API. Position using `NSScreen.safeAreaInsets` and `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`, with a floating capsule at top-centre on external displays. DynamicNotchKit (MIT) is a usable starting point. Boring Notch is GPL-3.0, so use it only as visual inspiration in an Apache-2.0 project.
- **Keyboard without stealing focus:** a non-activating panel that `canBecomeKey` can take ⌘↩ / Esc / ⌘. while the frontmost app stays frontmost.
- **Materials:** the package targets macOS 14. Use `.ultraThinMaterial` everywhere and, behind `if #available(macOS 26, *)`, Liquid Glass (`glassEffect`, regular variant) on the island chrome and buttons only, never on timeline or diff content, per Apple's guidance. In notch mode, a solid black background makes the island read as part of the hardware.
- **Motion and accessibility:** spring animations, replaced by cross-fades under Reduce Motion; VoiceOver announcements for `awaitingInput`; never use colour alone for state (glyph + colour + text).
- **Live Activities are out:** on the Mac they only arrive from an iPhone through iPhone Mirroring.

---

## 6. Build plan

| Step | Work | Files | Est. |
|---|---|---|---|
| 1 | v2 events + `update_plan` tool + streaming planner + metrics + `stale` | `agentd/src/rpc.ts`, `agent.ts`, `gate.ts`, `approvals.ts`, `tools/contract.ts` | 3–4 days |
| 2 | Claude Code `stream-json` passthrough; incremental `runProcess` | `agentd/src/tools/index.ts`, `tools/process.ts` | 1–2 days |
| 3 | Typed protocol + `TaskStore` with unit tests (replay recorded event streams) | `AgentKit/` | 2 days |
| 4 | New approval card (non-activating, diff, risk badge, countdown, edit, scope) | `InstructFlow/Island/ApprovalCard` | 3 days |
| 5 | Task Center (list, timeline, diff viewer, cost, history from audit log) | `InstructFlow/TaskCenter/` | 1–1.5 weeks |
| 6 | Island compact/peek states, voice states, steer by voice; retire `AgentPanel` and fold the HUD in | `InstructFlow/Island/`, `HUD.swift`, `main.swift` | 1.5–2 weeks |
| 7 | Notifications fallback; spoken summaries; "status?" | `Notifications/`, agentd | 3 days |
| Later | History window with replay of a task's timeline; Control Center "pause agent" toggle; desktop widget | | — |

**10-day cut** (good enough for a demo video): steps 1–5 with the island limited to the approval card. The Task Center shows everything else.

### Acceptance checks (add to `bench/` as UI scenarios)

- First visible feedback ≤ 300 ms after the hotkey is released; plan visible ≤ 3 s after `task.created`.
- The frontmost app never loses focus during a task, except key status for an approval card.
- Every approval card shows an effect badge and the exact payload or diff; no Approve button for blocked effects.
- Claude Code edits appear in the timeline within 1 s of happening.
- After restarting the app, the last 50 tasks are visible in History.
- VoiceOver announces every "needs you"; Reduce Motion leaves no spring or pulse animations.

---

## 7. Alternatives considered

| Concept [E §5] | Verdict |
|---|---|
| **A. Notch island + drawer** | **Recommended** as the glance and approval surface. Most distinctive; no competitor ships it for agents. |
| **B. Menu-bar Task Center** | **Recommended** as the full view; low risk and idiomatic. |
| **C. Floating side "agent dock"** | Not now. Always-visible docks compete with the user's windows; worth it only for the multi-agent fleet view later. |
| **D. Full "mission control" window** | Later, as "Open History" with replay; useful for debugging and trace cards (report 07). |
| Notification-only | Rejected as primary: notifications are easy to miss, and approve-from-notification is unsafe. |
| Live Activities / widgets | Live Activities aren't available to Mac apps; a widget is a nice extra for a daily summary. |

Sources for product behaviour, macOS APIs and design guidance are listed at the end of [E](E-agent-ui-patterns.md).

---

## 8. Implementation status (2026-10-31)

Built: the first slice. The event model, a task store and the island, with the approval card in the
island. Not built yet: the Task Center window, Claude Code streaming, notifications, steering by voice
and spoken summaries.

| Piece | Status | Where |
|---|---|---|
| `task.step` events (waiting / running / done / error / blocked / denied, with title, risk, timing, one-line result) | Done | `agentd/src/gate.ts` |
| `update_plan` tool → `task.plan` (whole checklist each time; no approval) | Done | `agentd/src/tools/plan.ts`, `agent.ts` |
| Commentary between tools (`task.note`) and running token counts (`task.metrics`) | Done; the planner steps through the tool runner | `agent.ts` |
| Approval card data: plain title per tool, risk from effects, `expiresAt`, same id as the timeline step | Done | `approvals.ts`, `effects.ts` (`riskOf`), `tools/index.ts` (`title`) |
| Per-task stop (`task.cancel` from the app) | Done | `AgentKit/AgentClient.swift` |
| Typed events and `TaskStore` (tasks, plan, steps, approval queue, history of 20) | Done, unit-tested | `AgentKit/AgentProtocol.swift`, `TaskStore.swift` |
| Island: compact pill → hover drawer → approval card → done (8 s) / failed (until dismissed) | Done | `AgentUI/AgentIsland.swift` |
| Notch placement (hangs from the notch, black) and a capsule under the menu bar elsewhere | Done | same |
| Never takes focus; the card becomes key only when clicked; Approve arms after 400 ms; VoiceOver announcement; Reduce Motion | Done | same |
| Recent tasks in the menu (Agent Tasks ▸), opening one in the island | Done | `InstructFlow/main.swift` |
| `AgentPanel` (focus-stealing window) | Removed | — |
| Task Center window, history from the audit log, diff viewer | Not yet | step 5 |
| Claude Code `stream-json` passthrough | Not yet | step 2 |
| Notifications fallback, steer by voice, spoken summary, "status?" | Not yet | step 7 |
| Edit… and scope ("allow writes here for this task") on the card | Not yet | needs `approval.respond` with a payload and scope |

**Deliberate change from section 3.1.** The card does not take key status on its own. If it did, the
next dictation would type into the card instead of your app. Click the card first, then ⌘↩ / Esc / ⌘.
work.

**Verification:**
- Unit tests: agentd 35 (4 new for timeline events); Swift 230 (5 new for `TaskStore` and parsing).
- Rendered states: `INSTRUCTFLOW_RENDER_DIR=<dir> swift test --filter IslandRender` writes the compact, notch, drawer, approval and done states to PNG.
- Live run: a real task over the socket (`git status` in voice-flow, denied). The island window appeared at 347×69, hanging from the notch, grew to 480×252 for the card, showed the result, and hid 8 s later.
