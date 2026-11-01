# E. Making the Background Agent Visible: UI Patterns and macOS Surfaces for Aloud

*Research date: 2026-10-31. Scope: how to make `agentd` visible, glanceable and trustworthy in a native macOS way. This file does not revisit hotkeys, insertion, audio or distribution, which are covered in earlier research files.*

---

## 0. TL;DR

- **The problem is the event model as much as the UI.** Five RPC events (`task.started`, `task.progress(string)`, `approval.request`, `task.result`, `task.error`) cannot drive a plan, a timeline, live streaming, cost or history. Every product studied here sends **typed activities** (thought / action / elicitation / response / error) and a **replaceable plan array**. Linear publishes the cleanest public version of that contract ([Linear agent interaction](https://linear.app/developers/agent-interaction.md)). Do this first (section 4).
- **The pattern that converged across products in 2026** has four parts: a persistent *status glyph*, a *plan checklist*, a *step timeline with expandable tool calls and logs*, and a distinct, loud **"needs you"** state that routes to one approval surface. Most also add a notification inbox and a history/replay view. Codex, Cursor 3, Warp, Copilot, Devin, Cowork and Linear all ship some version of this.
- **Recommended direction for Aloud: Concept A + B.** A notch "island" (glance and peek, holding approvals and voice state) plus a menu-bar Task Center (task list, timeline, history). A Mission-Control-style window (D) can come later as a "History & Replay" window. Build the island with MIT-licensed **DynamicNotchKit** or your own `NSPanel`, not with GPL-3.0 Boring Notch code, which is incompatible with Apache-2.0 distribution.
- **Don't rely on Live Activities.** On the Mac they appear only when they come from an iPhone through iPhone Mirroring ([Apple Support](https://support.apple.com/en-us/120684)). Notification actions should never carry *Approve* for write, execute or send effects. Use them for *Review…* and *Stop* only.

---

## 1. How leading agent products visualise background agents (2026)

### 1.1 Product-by-product extraction

| Product | Where the agent lives | Plan / checklist | Step timeline and logs | "Needs you" state | Notifications | History / replay | Diff / preview |
|---|---|---|---|---|---|---|---|
| **ChatGPT agent** | Agent's own virtual browser shown in the chat | Implicit in the chat | Live visual browser, screenshot-driven actions | Pauses for clarification. Asks confirmation before high-impact actions (sharing files, changing settings). "Take over browser" for logins. "Watch mode" on sensitive sites requires you to supervise ([OpenAI Help](https://help.openai.com/articles/11752874)) | Not documented | Chat transcript | Live view of the browser |
| **Codex app (macOS)** | Projects → threads; subagent threads you can inspect ([IntuitionLabs](https://intuitionlabs.ai/articles/openai-codex-app-ai-coding-agents)) | Task sidebar "plan view" with step progress, sources, artifacts and a summary for when you return ([Codex workspace notes](https://codex.danielvaughan.com/2026/04/17/codex-app-workspace-pr-review-task-sidebar-artifact-viewer/)) | Per-thread history | Approvals in-thread | Automation results land in a central **review queue** | Threads persist; CLI sessions are imported | Diff view with inline comments; commit, reject or open in editor; artifact viewer for PDFs and spreadsheets |
| **Claude Cowork / desktop** | Session view with a Progress widget | TodoList shown as a widget with pending / in-progress / completed rows ([coworkhow guide](https://coworkhow.com/guides/optimizing-workflows)) | Conversation and tool calls | AskUserQuestion structured questions | Background tasks on web and mobile | Sessions | Artifacts |
| **Claude computer use** | Your real desktop; other apps hidden while it works | n/a | Screenshots per action | Per-app approval prompt with **sentinel warnings**: "Equivalent to shell access", "Can read or write any file", "Can change system settings" | macOS notification "Claude is using your computer · press Esc to stop", then a second one when it's done. **Esc anywhere** aborts, and the keypress is consumed so on-screen injection can't use it ([Claude Code docs](https://code.claude.com/docs/en/computer-use.md)) | n/a | n/a |
| **Claude Code** | Terminal | TodoWrite / Task list; `TaskCreated` / `TaskCompleted` hooks | Streaming tool calls. `--output-format stream-json --verbose --include-partial-messages` emits token deltas, retries and the final result ([stream-json write-up](https://backgroundclaude.com/blog/stream-json)) | `PermissionRequest` and `Notification` hooks fire when Claude waits for input or permission ([hooks guide](https://code.claude.com/docs/en/hooks-guide.md)) | Hook → `osascript` desktop notification | Session resume | Status line gets JSON with model, `context_window.used_percentage`, `cost.total_cost_usd` and `total_duration_ms`, **debounced at 300 ms** ([statusline docs](https://code.claude.com/docs/en/statusline)) |
| **Cursor 3** | Full-screen **Agents Window**: sidebar of local and cloud agents, agent tabs in a grid or side-by-side ([dev.to review](https://dev.to/jangwook_kim_e31e7291ad98/cursor-3-review-background-agents-and-the-agent-first-ide-7me)) | Per-agent | Per-tab session; cloud agents have their own desktop and browser and can record video demos | — | — | Sessions hand off between cloud and local | PRs |
| **GitHub Copilot coding agent** | Agents panel reachable from any GitHub page | — | Session log shows reasoning and tools; overview shows **token usage and session length** | **Steering**: a follow-up prompt is applied after the current tool call, with no stop needed. **Stop session** keeps the commits already pushed ([GitHub Docs](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/coding-agent/track-copilot-sessions)) | GitHub notifications | Archive (not delete); commits link back to the session log | PR diff |
| **Perplexity Comet** | In-browser assistant | — | Shows when it is browsing and what actions it takes | Stop at any time, add guidance mid-task. Permission gates before login or purchase. Browsing autonomy levels: you browse / browse once / auto ([createwith](https://www.createwith.com/tool/perplexity/updates/perplexity-updates-comet-with-more-transparent-assistant-controls)) | — | — | — |
| **Raycast AI (v2.3)** | AI Chat window | Agent plans and retries | — | Approval prompts that "clearly explain the requested action and its impact". **Auto** confirmation mode with Auto-review rules. Keeps the Mac awake while AI runs ([Raycast changelog](https://raycast.com/changelog/macos/2-3)) | Automations post results into a chat | Chats | — |
| **Warp** | Tabs with status icons; **Agent Management Panel** shows every agent as running, waiting or finished ([Warp guide](https://docs.warp.dev/guides/agent-workflows/running-multiple-agents-at-once-with-warp/)) | Orchestration pill bar for child agents | Blocks | Three notification types: **Complete / Request / Error**. Tab attention badge | In-app toasts (max 2, pause on hover, click to jump), a **mailbox** with All / Unread / Errors filters and full keyboard navigation, plus native notifications when backgrounded ([Warp notifications](https://docs.warp.dev/agents/capabilities/agent-notifications.md)) | Mailbox | Code Review panel per tab |
| **Devin** | Session with Progress, Shell, IDE and Browser tabs | Progress tab | Unified timeline of shell, edits and browser; **click a step to jump** there; commands that run later appear greyed out ([Devin docs](https://docs.devin.ai/work-with-devin/devin-session-tools.md)) | Take over the IDE or browser (logins, CAPTCHA) | Slack / web | Scrub through the timeline | IDE |
| **Manus "My Computer"** | Desktop app on your Mac | — | — | Every shell action needs sign-off, or you mark routine ops to run unprompted ([AlternativeTo](https://alternativeto.net/news/2026/3/manus-introduces-my-computer-for-local-ai-tast-execution-and-automation-on-macos-and-windows)) | — | Manus Replay | — |
| **Conductor** | Workspace list with time since last activity, e.g. "9m" ([conductor.build](https://www.conductor.build)) | — | Boot logs while a workspace starts | — | — | Workspaces | Changes panel next to the chat |
| **Linear agents** | Agent Session panel on an issue | **Plan** = an array of `{content, status: pending/inProgress/completed/canceled}`, always replaced whole | Activities: `thought`, `action` (start, then result), `elicitation`, `response`, `error`. Thoughts and actions can be **ephemeral** | Session state `awaitingInput`. Set automatically from the last activity | Inbox | Session history | — |

Linear's session states are `pending`, `active`, `error`, `awaitingInput`, `complete` and `stale`. An agent must emit an activity within **10 s** of creation or it is marked unresponsive ([Linear](https://linear.app/developers/agent-interaction.md)).

### 1.2 The patterns that recur

1. **A persistent status glyph with a small, fixed state set.** Warp uses working / blocked / completed / errored, plus an unread badge. Linear uses pending / active / awaitingInput / error / complete / stale. Users learn four or five states. They never learn free-form strings.
2. **The plan is a checklist the agent replaces whole.** Codex, Cowork and Linear all show one. Linear's rule (send the whole array, never patch one item) avoids the stale-row bugs reported against Cowork's Progress widget ([issue 67516](https://claudeissues.com/issue/67516-bug-cowork-in-session-task-list-progress-widget-does-not-repaint-rows-after-task)).
3. **Thought and action are separate.** Reasoning is collapsible and often ephemeral. Actions are durable rows with a start, a result and a duration (Linear, Copilot logs, Devin progress).
4. **"Needs you" is its own channel.** Warp's *Request* type, Linear's `awaitingInput`, Claude Code's `PermissionRequest` / `Notification` hooks. Every product makes it louder than progress and routes it to one place.
5. **Approval cards show the exact action and its blast radius.** Raycast explains action and impact. Claude computer use flags apps that amount to shell, filesystem or settings access. Comet gates login and purchase.
6. **Steer without stopping, and stop without losing work.** Copilot steering, Devin `/btw` side chats, a global Esc in computer use, Copilot "Stop keeps commits".
7. **An inbox and a review queue for results.** Warp's mailbox, Codex's automation review queue, Raycast automations posting into chats.
8. **Cost and time are shown as numbers.** Copilot shows token usage and session length. Claude Code's status line carries cost, duration and context %.
9. **Take over, then hand back.** ChatGPT agent and Devin, with privacy during takeover (ChatGPT captures no screenshots while you control the browser).
10. **Autonomy levels.** Comet (browse yourself / once / auto), Raycast (Auto plus review rules), Manus (mark routine ops). This matches the "Autonomy Dial" pattern ([Smashing Magazine, Feb 2026](https://smashingmagazine.com/2026/02/designing-agentic-ai-practical-ux-patterns/)).

---

## 2. macOS surfaces and APIs

### 2.1 Surface comparison

| Surface | Good for | Limits / risks | Key API |
|---|---|---|---|
| **Menu bar extra (window style)** | Always-reachable task center; status glyph with a badge | No first-party API to open or close it from code, reach the `NSStatusItem` or reach its window. The **MenuBarExtraAccess** package adds `isPresented`, status-item access and window introspection ([MenuBarExtraAccess](https://swiftpackageregistry.com/orchetect/MenuBarExtraAccess)). Menu bar space is crowded on notched Macs | `MenuBarExtra { }.menuBarExtraStyle(.window)`, macOS 13+ ([Apple](https://developer.apple.com/documentation/swiftui/windowmenubarextrastyle.md)); or `NSStatusItem` + `NSPanel` for full control |
| **Notch "island" overlay** | Glance (pill) → peek (expanded) right next to where the eye already goes; ideal for voice state | No public notch API. You position a borderless panel yourself. Must fall back to a floating pill on non-notched and external displays. Can collide with other notch apps | `NSScreen.safeAreaInsets.top > 0` means a notch. `auxiliaryTopLeftArea` and `auxiliaryTopRightArea` (macOS 12+) give the unobscured rects on either side, so the notch is the gap between them ([Apple](https://developer.apple.com/documentation/appkit/nsscreen/auxiliarytopleftarea-uglc.md)) |
| **Floating non-activating NSPanel** | Approval cards, task drawer, side dock; keyboard input **without activating Aloud or stealing the frontmost app** | Must manage level, Spaces and full-screen behaviour yourself | `NSPanel` with `.nonactivatingPanel`, `isFloatingPanel = true`, `level = .floating`, `collectionBehavior += .fullScreenAuxiliary`, override `canBecomeKey`, host SwiftUI in `NSHostingView` ([Cindori floating panel](https://cindori.com/developer/floating-panel)) |
| **Liquid Glass (macOS 26)** | Native 2026 look for the island, dock and controls | HIG: glass is for the **controls/navigation layer, not content**. Use it sparingly. Use **regular** for text-heavy components (alerts, popovers). Use clear only over rich media ([HIG Materials](https://developer.apple.com/design/human-interface-guidelines/materials.md)). Needs a fallback on macOS 14/15 | `.glassEffect(.regular, in: .capsule)`, `GlassEffectContainer`, `.glassEffectID(_:in:)` for morphing pill ↔ expanded, `.buttonStyle(.glass/.glassProminent)`. Reduce Transparency, Increase Contrast and Reduce Motion adapt automatically ([summary](https://dev.to/diskcleankit/liquid-glass-in-swift-official-best-practices-for-ios-26-macos-tahoe-1coo)) |
| **Live Activities on Mac** | — | Apple documents only Live Activities **from iPhone**, via iPhone Mirroring, shown in the menu bar ([Apple Support](https://support.apple.com/en-us/120684)). No native-Mac route is documented, so don't plan on it. A future iOS companion app could use it for remote approvals | ActivityKit (iOS) |
| **UNUserNotificationCenter actionable notifications** | "Task done", "Agent needs you" when the island is hidden or the user is in full-screen or another Space | Actions run from a tiny banner with no preview, so they're easy to click by accident. Focus can delay delivery. Options are only `.foreground`, `.destructive` and `.authenticationRequired` ([Apple](https://developer.apple.com/tutorials/data/documentation/usernotifications/unnotificationactionoptions.md)). Use **Time Sensitive** only for things relevant now (an approval with a 2-minute timeout qualifies; "task done" does not) ([HIG Notifications](https://developer.apple.com/design/human-interface-guidelines/managing-notifications.md)) | `UNNotificationCategory` with actions `Review…` (`.foreground`) and `Deny` / `Stop` (`.destructive`). **Never Approve** for write, execute, send or network_write |
| **WidgetKit desktop / Notification Center widgets** | Passive dashboard: last tasks, today's cost, pending approvals count; interactive buttons via App Intents | Timeline-budgeted, so not for live streaming. Inactive widgets fade into the wallpaper ([MacRumors](https://macrumors.com/how-to/use-interactive-widgets-mac-desktop)) | `Widget` + `AppIntent` buttons (macOS 14+) |
| **Control Center controls (macOS 26)** | A **kill switch / pause agent** toggle and "New voice task" button | Third-party controls are supported, but a gallery-refresh bug hid them for many users ([MacStories](https://www.macstories.net/stories/mystery-solved-why-third-party-apps-vanished-from-the-macs-control-center/)) | `ControlWidgetToggle` / `ControlWidgetButton` + App Intent |
| **Stage Manager / Spaces / full screen** | — | Normal windows get grouped and hidden by Stage Manager. Panels with `.canJoinAllSpaces` + `.fullScreenAuxiliary` stay visible across Spaces and over full-screen apps | `NSWindow.CollectionBehavior` |
| **Accessibility** | VoiceOver users must hear "Agent needs approval" | Animation-heavy islands are a problem with Reduce Motion | `NSAccessibility.post(element:notification: .announcementRequested, userInfo: [.announcement:…, .priority: high])` ([Apple](https://developer.apple.com/documentation/appkit/nsaccessibility-swift.struct/notification/announcementrequested.md)); `@Environment(\.accessibilityReduceMotion)` ([Apple](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion.md)) |

### 2.2 Notch overlay implementation notes

- **Libraries:**
  - **DynamicNotchKit** (MIT, macOS 13+) wraps any SwiftUI view, handles notch safe areas and falls back to a `.floating` style on non-notched Macs ([GitHub](https://github.com/MrKai77/DynamicNotchKit)).
  - **Boring Notch** (11k+ stars) is a good UX reference: hover to expand, a music, shelf and HUD replacement. It is **GPL-3.0** and requires macOS 14+ ([GitHub](https://github.com/TheBoredTeam/boring.notch)). Read it for ideas only, and don't vendor its code into Apache-2.0 Aloud.
  - **NotchNook** is the commercial reference: widgets in the island and drop "pipelines" that run on dropped files ([iMore](https://www.imore.com/apps/mac-apps/notchnook-app-that-turns-macbook-notch-into-a-dynamic-island-is-now-better-than-ever)).
- **Geometry:** `let s = NSScreen.main!`. If `s.safeAreaInsets.top > 0`, the notch rect is `x = auxiliaryTopLeftArea!.maxX`, `width = auxiliaryTopRightArea!.minX - x`, `height = safeAreaInsets.top`, at the top of `s.frame`. Anchor a borderless `NSPanel` (black background that blends into the notch) centred on that rect. Grow it downward and sideways. Recompute on `NSApplication.didChangeScreenParametersNotification`.
- **Window flags:** `styleMask = [.borderless, .nonactivatingPanel]`, `level = .statusBar` (above menu bar content), `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`, `hasShadow = false` while compact. `ignoresMouseEvents` stays true in compact mode, except for a hover tracking area.
- **Non-notched or external display:** render the same view as a floating glass capsule at top-centre, below the menu bar. Expose this as a setting. Many developers use clamshell mode with an external monitor.

### 2.3 Keyboard-first approval without stealing focus

- A `.nonactivatingPanel` whose `canBecomeKey` returns true can take keystrokes while the user's frontmost app stays active. The current `AgentPanel` "takes focus", which this fixes.
- Make the panel key only when an approval is shown, then hand key status back (`orderOut` restores the previous key window).
- Bindings: **⌘↩ Approve**, **Esc Deny**, **⌘. Stop task**, **Space toggles preview**, **Tab cycles effect rows**.
- Aloud already owns a CGEventTap. Add a global "summon pending approval" chord (for example Right Shift + Return) that brings the card forward. **Don't allow a global chord to approve unseen.** Approve only works while the card is visible and has been on screen for ≥ 400 ms. That debounce prevents an accidental approval from a stray Enter meant for another app.
- Mirror Claude Code's global Esc for **stop**: consume the keypress while a task is in an acting state. Prefer a less-common chord, because Esc is heavily used.

---

## 3. Design guidance

### 3.1 Progressive disclosure: glance → peek → full

| Level | Surface | Content | Interaction cost |
|---|---|---|---|
| **Glance** (0 clicks) | Notch pill or menu-bar glyph | State icon + 1 short phrase ("Searching files · 3/5"), elapsed time, attention dot | Peripheral vision only |
| **Peek** (hover or 1 key) | Expanded island or drawer | Plan checklist, current step with live tail (last 3 lines of Claude Code output or reasoning), cost so far, Stop / Steer | 1 hover |
| **Full** (1 click) | Task Center popover or window | All tasks, full timeline with expandable tool I/O, diffs, audit log, history, replay | Deliberate |

This applies Microsoft's human–AI guidelines: "make clear what the system can do", "support efficient dismissal" and "support efficient correction" ([Microsoft Research](https://www.microsoft.com/en-us/research/blog/guidelines-for-human-ai-interaction/)). It also covers Smashing's *Intent Preview* (plan before acting) and *Action Audit & Undo* (timeline plus history) ([Smashing](https://smashingmagazine.com/2026/02/designing-agentic-ai-practical-ux-patterns/)).

### 3.2 Attention management: when to interrupt

| Event | Default treatment | Escalation |
|---|---|---|
| Step progress | Glance text only; **throttle UI to ≤ 4 Hz** (Claude Code debounces its status line at 300 ms) | none |
| Plan created / changed | Pill pulses once (no pulse with Reduce Motion) | none |
| **Approval needed** | Island expands with the card and a soft sound; VoiceOver announcement at high priority | 20 s: re-pulse. 60 s: Time Sensitive notification with `Review…` / `Deny`. 120 s: timeout → auto-deny (existing policy), shown in history |
| Clarifying question (elicitation) | Same as approval, but the answer field accepts voice (hold Right Shift to answer) | same |
| Task complete | Pill shows ✓ + a one-line summary for 8 s, then collapses to a badge on the menu-bar glyph (the inbox) | Notification only if the app wasn't visible (full screen or another Space) |
| Error | Red pill with a short reason; stays until dismissed | Active notification |
| Agent idle | Pill hidden or minimal dot | — |

Rules:

- **Never activate the app or take key focus for anything other than an approval.**
- Don't use Time Sensitive for "done" notifications ([HIG](https://developer.apple.com/design/human-interface-guidelines/managing-notifications.md)).
- Limit toasts to two, as Warp does.
- Notifications are a fallback for when the island isn't visible. They are not the primary channel.

### 3.3 Showing "the agent is waiting for you"

- **Use a different colour and shape, not just different text.** Amber with a hand or question glyph, and the pill widens. Never rely on colour alone.
- Show **what it is waiting for** and **since when**: "Waiting for approval · Write file · 0:42 (auto-deny in 1:18)". The countdown matters because the 2-minute timeout already exists in `agentd`.
- Show the waiting state in **every** surface: island, menu-bar badge, Task Center row and Dock badge if the app has a Dock icon. This mirrors Warp's tab badge and Linear's `awaitingInput`.
- With several tasks, show one aggregate badge ("2 need you") and a queue in the island, approvals first.

### 3.4 Trust UX for approvals

Approval card contents, in order:

1. **Verb + object in plain language.** "Write 1 file in `~/Projects/notes`", not "write_file".
2. **Risk badge from the declared Effect.** `write_local` = amber, `execute_process` = amber+, `network_write` / `send_message` = red. Blocked effects (delete, spend, system_settings) never get an Approve button; they show "Blocked by policy". This mirrors Claude computer use's sentinel warnings.
3. **Exact payload.** For write_file, a **unified diff** against the current file (new files shown as all-green). For run_shell, the exact command with its cwd and allowlist match. For a message, recipient, subject and body. For claude_code_task, the repo, branch or worktree and the prompt it will receive.
4. **Rationale.** One sentence from the model, "why this step". This is the *Explainable Rationale* pattern.
5. **Scope.** "This step only" by default. Optional "allow `write_local` in this folder for this task" (the Autonomy Dial, Manus-style "mark routine"). Never "always" for send or network_write.
6. **Buttons:** Approve (⌘↩) · Deny (Esc) · Edit… (open the payload editable) · Stop task (⌘.).

Afterwards, the timeline row keeps the approved payload, who approved, when, and from which surface (island / notification / voice), for the audit log JSONL.

### 3.5 Voice-agent-specific guidance

- **Show what was heard.** The task's first timeline row is the raw transcript plus the cleaned intent ("Heard: 'clean up my downloads folder'. Task: move files older than 30 days in ~/Downloads to ~/Downloads/Archive"). Mis-hearing is the top voice failure mode, and showing the transcript lets the user correct the task before anything runs.
- **Use a small state machine with a matching visual for each state:**

  | State | Visual | Sound / voice |
  |---|---|---|
  | listening | waveform in pill | start tick |
  | transcribing | waveform freezes + shimmer | — |
  | planning | plan rows appear one by one | — |
  | acting | spinner + current step | — |
  | waiting-for-you | amber, expanded card | chime; optional spoken "Need your OK to write one file" |
  | speaking | pulse synced to TTS | TTS |
  | done / error | ✓ / ✕ | short earcon |

- **Pair spoken and visual output.** Speech carries the headline ("Done, moved 42 files"). The screen carries the detail (the list, an Undo button). Never speak anything that needs reading, such as paths or diffs.
- **Voice approval:** allowed only for low-risk effects, and only when the card is visible. Never for send, spend or delete (this matches the existing plan). Show "🎙 say 'approve' or press ⌘↩" so the user knows which modality is armed.
- **Barge-in:** holding the dictation key during an acting task means **steer**, as in Copilot steering. The utterance becomes a `prompt` activity applied after the current tool call.

---

## 4. Prerequisite: an event model that can drive any of these UIs

Replace the five-event model with typed activities. The schema below borrows from Linear, Claude Code stream-json and Warp.

```ts
// agentd -> app  (JSON-RPC notifications)
task.created   {taskId, title, transcript, cleanedIntent, context:{app,bundleId,window}, ts}
task.plan      {taskId, steps:[{id, content, status:"pending"|"inProgress"|"completed"|"canceled"|"failed"}]}  // always full array
task.activity  {taskId, activityId, kind:"thought"|"action"|"elicitation"|"response"|"error",
                stepId?, ephemeral?, tool?, effects?:Effect[], args?, result?, startedAt, endedAt?}
task.delta     {taskId, activityId, channel:"reasoning"|"text"|"stdout"|"stderr"|"cc", text}  // throttled 4 Hz
task.cc        {taskId, event}          // raw Claude Code stream-json line passthrough (tool_use, result, api_retry)
task.awaiting  {taskId, approvalId, kind:"approval"|"question", card:{verb, object, effect, risk, payload, diff?, rationale}, expiresAt}
task.metrics   {taskId, inputTokens, outputTokens, costUsd, elapsedMs, toolCalls}
task.state     {taskId, state:"pending"|"active"|"awaitingInput"|"complete"|"error"|"canceled"|"stale"}
// app -> agentd
approval.respond {approvalId, decision:"approve"|"deny"|"edit", editedPayload?, scope:"step"|"task-folder", via:"island"|"notification"|"voice"|"keyboard"}
task.steer     {taskId, text, via:"voice"|"text"}
task.stop      {taskId}
task.list / task.get {taskId} / task.history {limit, before}   // backed by the existing audit JSONL
```

Implementation notes:

- `claude_code_task` should spawn Claude Code with `--output-format stream-json --verbose --include-partial-messages` and forward lines as `task.cc` and `task.delta`.
- Map Claude Code's own permission requests into `task.awaiting` so there is **one** approval surface.
- Mark a task `stale` if nothing is emitted for 10 s while active, following Linear's 10-second rule.
- The Anthropic SDK's streaming events give reasoning and text deltas for `task.delta`. Usage blocks give `task.metrics`.

---

## 5. UI concept options for Aloud

### Concept A: Notch Island + expandable Task Drawer

The island is the single "agent presence" surface. Compact = live state. Hover or hotkey = drawer with plan and live tail. Approvals morph the island into a card.

```
 Compact (glance)                          notch
 ┌─────────────────────────────────────[■■■■■■■■]──────────────────────────┐
 │                          ( ◐ Searching files · 2/5   0:14 )               │  <- pill hugs notch
 └───────────────────────────────────────────────────────────────────────────┘

 Expanded (peek)  - hover or Right Shift + /
            ┌───────────────────────[■■■■■■■■]───────────────────────┐
            │  ◐ Tidy Downloads                     0:41 · $0.03  ⏹ │
            │  Heard: "clean up my downloads folder"                 │
            │  ✓ List ~/Downloads (212 items)                        │
            │  ✓ Find files older than 30 days (42)                  │
            │  ◐ Create ~/Downloads/Archive                          │
            │  ○ Move 42 files                                       │
            │  ○ Summarise                                           │
            │  ── live ─────────────────────────────────────────── │
            │  > mkdir -p ~/Downloads/Archive                        │
            │  [ Steer… (hold ⇧) ]              [ Open Task Center ] │
            └─────────────────────────────────────────────────────────┘

 Approval (island morphs, becomes key, app not activated)
            ┌───────────────────────[■■■■■■■■]───────────────────────┐
            │  ⚠ Needs your OK            [WRITE LOCAL]  auto-deny 1:18│
            │  Move 42 files into ~/Downloads/Archive                │
            │  Why: they match "older than 30 days" from your request│
            │  ┌──────────────────────────────────────────────────┐ │
            │  │ invoice-2026-08.pdf  -> Archive/                  │ │
            │  │ screenshot-0912.png  -> Archive/   … 40 more ▾    │ │
            │  └──────────────────────────────────────────────────┘ │
            │  ☐ Allow writes in ~/Downloads for this task           │
            │  [Deny  esc]   [Edit…]   [Stop ⌘.]   [Approve  ⌘↩]     │
            └─────────────────────────────────────────────────────────┘
```

| Pros | Cons |
|---|---|
| Most distinctive and "Dynamic Island for agents". Good portfolio material and no competitor ships it | No public notch API; positioning is hand-rolled and fragile across displays |
| The eye is already near the menu bar. Voice state (listening → acting) fits naturally | Small canvas; long diffs need a hand-off to the full view |
| Approvals happen in place without stealing focus | Conflicts with other notch utilities; needs a floating-capsule fallback for external displays |

**Implementation:**
- DynamicNotchKit (MIT) or a custom `NSPanel` (`.borderless, .nonactivatingPanel`, level `.statusBar`, `.canJoinAllSpaces/.fullScreenAuxiliary`).
- SwiftUI content in `NSHostingView`. On macOS 26, put the morph inside a `GlassEffectContainer` with `.glassEffectID` on pill, drawer and card. Fall back to `.ultraThinMaterial` on 14/15. In notch mode use a solid black background so it reads as hardware.
- Use `withAnimation(.spring)` unless `accessibilityReduceMotion` is on; then cross-fade.
- Replaces the existing HUD pill.

**Effort:** M–L, about 2–3 weeks, with multi-display edge cases the main risk.

### Concept B: Menu-bar Task Center

A status item whose glyph is the glance. Clicking opens a window-style popover with a task list, one selected task's timeline, and an inbox.

```
 Menu bar:   …  🎙  ◐²  ⌁  Wi-Fi  Fri 10:42        (◐ = agent busy, ² = needs-you count, amber)

            ┌──────────────────────────────────────────────────────────────┐
            │ Aloud Agent        [Running 2] [Needs you 1] [Done]  ⚙ │
            ├──────────────────────────────────────────────────────────────┤
            │ ⚠ Draft reply to vendor email     needs approval · 0:42      │
            │ ◐ Fix failing test (Claude Code)  step 3/6 · 2:10 · $0.21    │
            │ ✓ Tidy Downloads                  42 files moved · 10:31     │
            │ ✕ Open quarterly report           file not found · 09:58     │
            ├──────────────────────────────────────────────────────────────┤
            │ Fix failing test                                    ⏹ Stop   │
            │  ✓ thought  Reading test output…                (collapsed)  │
            │  ✓ action   run_shell  swift test --filter Parser   4.1 s    │
            │  ◐ action   claude_code_task  repo: app/  worktree: fix-1    │
            │     │ Edit Sources/Parser.swift (+12 −3)  [View diff]        │
            │     │ Running tests…                                         │
            │  tokens 18.2k in / 2.1k out · $0.21 · 2:10                   │
            │ [ Steer… ]                                [ Open History ]   │
            └──────────────────────────────────────────────────────────────┘
```

| Pros | Cons |
|---|---|
| Most conventional and idiomatic Mac pattern. Easy to discover. Works on every display | Hidden until clicked. A busy menu bar on notched Macs can push the icon under the notch |
| A natural home for multi-task, inbox, history and cost | Not great for approvals on its own: a popover needs a click, then it dismisses on outside click |
| Low risk to build | Less distinctive |

**Implementation:**
- `MenuBarExtra(.window)` + MenuBarExtraAccess for programmatic open (to pop it on "needs you"), or `NSStatusItem` + custom `NSPanel` for full control.
- The glyph is an SF Symbol with a `symbolEffect` (pulse while acting; static if Reduce Motion is on) and a count overlay.
- Use a SwiftUI `List` with `DisclosureGroup` rows for activities. Render diffs in a monospaced `Text` with attributed +/− colouring.
- `@Observable TaskStore` fed by the new RPC.

**Effort:** S–M, about 1–1.5 weeks.

### Concept C: Floating Side "Agent Dock"

A slim, translucent column at the screen edge. It is collapsed to an 8-pt "rail" with state dots and expands on hover, like a mini Warp Agent Management Panel.

```
                                                         ┌──┐   collapsed rail
                                                         │◐ │   (one dot per task)
                                                         │⚠ │
                                                         │✓ │
                                                         └──┘
 expanded on hover:                            ┌────────────────────────┐
                                               │ AGENTS             ⚙  │
                                               │ ⚠ Vendor reply   0:42 │
                                               │   send_message  [RED] │
                                               │   [Review]   [Deny]   │
                                               │ ◐ Fix test   3/6 2:10 │
                                               │   > Running tests…    │
                                               │ ✓ Tidy Downloads      │
                                               │ ───────────────────── │
                                               │ Today: 7 tasks · $0.64│
                                               └────────────────────────┘
```

| Pros | Cons |
|---|---|
| Shows several tasks in parallel at a glance; good for developer workflows with many Claude Code runs | Takes screen edge space; clashes with Dock or Stage Manager strips on the left or right |
| Edge hover is fast; can be pinned open as a monitor | Edge-hover panels annoy people when triggered by accident |
| Simple geometry compared with the notch | Can feel like a third-party overlay rather than native |

**Implementation:**
- Non-activating `NSPanel` anchored to `screen.visibleFrame.maxX`, `.canJoinAllSpaces`. Hover detection with `NSTrackingArea` and a 150 ms intent delay.
- Glass rail via `.glassEffect(.regular, in: .capsule)`.
- Respect the Dock position (`UserDefaults "orientation"` from `com.apple.dock`) to avoid overlap.

**Effort:** M, about 1.5–2 weeks.

### Concept D: "Mission Control" Task Window (History & Replay)

A full window with a sidebar of tasks, a centre timeline and a right inspector (diff, files, audit). It is the "full" level of disclosure, and the only place for replay.

```
┌─ Aloud · Agent ──────────────────────────────────────────────────────────────┐
│ ◀ ▶  Today ▾   🔍 Search tasks                                 Autonomy: Ask ▾  ⏹ All │
├───────────────────┬───────────────────────────────────────────┬─────────────────────┤
│ NEEDS YOU (1)     │ Fix failing test  · active · 2:10 · $0.21 │ INSPECTOR           │
│ ⚠ Vendor reply    │ Heard: "fix the parser test that broke"   │ Sources/Parser.swift│
│ RUNNING (1)       │ ─ Plan ──────────────────────────────────  │ @@ -40,7 +40,16 @@  │
│ ◐ Fix failing test│ ✓ Reproduce failure                       │ - let t = tok.next  │
│ TODAY             │ ✓ Locate cause                            │ + guard let t = …   │
│ ✓ Tidy Downloads  │ ◐ Patch & re-run tests                    │ …                   │
│ ✕ Open report     │ ─ Timeline ───────────────[▶ Replay 1×]─  │ ─ Effects ───────── │
│ YESTERDAY         │ 10:40:02 thought  …                       │ write_local  ✓ appr │
│ ✓ Weekly summary  │ 10:40:05 run_shell swift test   4.1 s ▸   │ execute_proc ✓ auto │
│                   │ 10:40:12 claude_code_task       ▸ stream  │ ─ Cost ──────────── │
│                   │ │ Edit Parser.swift (+12 −3)              │ 18.2k / 2.1k tok    │
│                   │ ▕██████████████░░░░░ scrubber             │ $0.21               │
└───────────────────┴───────────────────────────────────────────┴─────────────────────┘
```

| Pros | Cons |
|---|---|
| Room for diffs, history, replay, search and cost analytics; strong demo for evals-minded reviewers (audit log as a first-class UI) | A window is the opposite of "background". Needs A or B for presence |
| Plain SwiftUI `NavigationSplitView`; Stage Manager friendly | Most code; duplicates some of B |

**Implementation:**
- `Window("Agent", id:)` scene + `NavigationSplitView` (sidebar / content / inspector `.inspector`).
- Replay reads the audit JSONL and re-emits events into the same `TaskStore` with a playback clock. Show a scrubber like Devin's clickable steps.
- Glass only on the toolbar and sidebar (system-provided), never on the timeline content (HIG).

**Effort:** M–L, about 2 weeks, plus replay at about 0.5 week.

### 5.1 Comparison

| | A Notch Island | B Menu-bar Center | C Side Dock | D Task Window |
|---|---|---|---|---|
| Glance | ★★★ | ★★ | ★★★ | ★ |
| Approvals without focus theft | ★★★ | ★★ (with panel) | ★★ | ★ |
| Multi-task | ★★ | ★★★ | ★★★ | ★★★ |
| History / replay | ★ | ★★ | ★ | ★★★ |
| Voice-state fit | ★★★ | ★ | ★★ | ★ |
| Native feel | ★★ (custom) | ★★★ | ★★ | ★★★ |
| Distinctiveness | ★★★ | ★ | ★★ | ★★ |
| Effort | M–L | S–M | M | M–L |

### 5.2 Recommendation and sequencing

**Ship A + B on one `TaskStore`, then add D as "Open History".**

1. **Week 1: event model and `TaskStore`.** Section 4 schema, Claude Code stream-json passthrough, `task.metrics`, history from the audit JSONL. Without this, no UI concept works.
2. **Week 1–2: B, the Menu-bar Task Center.** Task list, timeline, inbox and cost, using `MenuBarExtra(.window)` + MenuBarExtraAccess. Low risk, and it immediately fixes "no task list, no history".
3. **Week 2–4: A, the island.** Replace the HUD pill and AgentPanel with the island (DynamicNotchKit or a custom panel). Approval cards move in, non-activating, keyboard-first, with diff previews and risk badges. Voice states (listening / transcribing / planning / acting / waiting) render here. Floating capsule on non-notch displays.
4. **Notifications, minimal.** "Needs you" as Time Sensitive with `Review…` + `Deny`, only when the island isn't visible. Done and error as Active, only when backgrounded or in full screen.
5. **Later.** D window with replay. A Control Center "Pause agent" toggle bound to the existing kill switch. A desktop widget for "today: tasks / cost / pending".

**Acceptance checks** (these make good eval-style scenarios for the bench):
- First visible feedback ≤ 300 ms after the hotkey is released.
- Plan visible ≤ 3 s after `task.created`.
- 0 focus changes of the frontmost app during a whole task, except for approval key status.
- Approval card always shows the effect badge and an exact payload or diff.
- VoiceOver announces every `awaitingInput`.
- Reduce Motion leaves no spring or pulse animations.

---

## 6. Risks and gotchas

- **Licensing.** Boring Notch is GPL-3.0, so don't copy its code. DynamicNotchKit is MIT, which is fine with Apache-2.0.
- **Notification approvals.** Banners hide the payload, and Focus can delay them. Keep Approve out of notification actions for any approval-requiring effect. The auto-deny timeout must surface in history ("Denied: timed out").
- **Over-animation.** Throttle deltas to ≤ 4 Hz and coalesce like Claude Code's 300 ms debounce. Reasoning streams at token rate would make the island flicker.
- **Prompt-injection surfacing.** If a tool result contains instructions (from a web page or a file), show it as data in the timeline. Never render it as a UI command, and flag suspected injection on the card. Claude computer use flags on-screen injection, and Aloud should do the same.
- **Liquid Glass misuse.** No glass on timeline or diff content; regular variant only (HIG).
- **Multi-display and clamshell.** Choose the island screen by `NSScreen.main` (the key window's screen) or by mouse location, and let the user pin it.

---

## Sources

**Agent products**
- OpenAI Help, ChatGPT agent: https://help.openai.com/articles/11752874
- IntuitionLabs, OpenAI Codex App guide: https://intuitionlabs.ai/articles/openai-codex-app-ai-coding-agents
- Codex app workspace (task sidebar, review pane, artifact viewer): https://codex.danielvaughan.com/2026/04/17/codex-app-workspace-pr-review-task-sidebar-artifact-viewer/
- Cowork TodoList / AskUserQuestion guide: https://coworkhow.com/guides/optimizing-workflows
- Cowork Progress widget repaint bug: https://claudeissues.com/issue/67516-bug-cowork-in-session-task-list-progress-widget-does-not-repaint-rows-after-task
- Claude Code computer use: https://code.claude.com/docs/en/computer-use.md
- Claude Code hooks guide: https://code.claude.com/docs/en/hooks-guide.md
- Claude Code status line: https://code.claude.com/docs/en/statusline
- Claude Code stream-json write-up: https://backgroundclaude.com/blog/stream-json
- Cursor 3 review: https://dev.to/jangwook_kim_e31e7291ad98/cursor-3-review-background-agents-and-the-agent-first-ide-7me
- GitHub Docs, Track Copilot sessions: https://docs.github.com/en/copilot/how-tos/use-copilot-agents/coding-agent/track-copilot-sessions
- Perplexity Comet transparency update: https://www.createwith.com/tool/perplexity/updates/perplexity-updates-comet-with-more-transparent-assistant-controls
- Raycast v2.3 changelog: https://raycast.com/changelog/macos/2-3
- Warp, Agent notifications: https://docs.warp.dev/agents/capabilities/agent-notifications.md
- Warp, Running multiple agents: https://docs.warp.dev/guides/agent-workflows/running-multiple-agents-at-once-with-warp/
- Devin session tools: https://docs.devin.ai/work-with-devin/devin-session-tools.md
- Manus My Computer (AlternativeTo): https://alternativeto.net/news/2026/3/manus-introduces-my-computer-for-local-ai-tast-execution-and-automation-on-macos-and-windows
- Conductor: https://www.conductor.build
- Linear, Agent interaction: https://linear.app/developers/agent-interaction.md

**macOS APIs and design**
- Apple, WindowMenuBarExtraStyle: https://developer.apple.com/documentation/swiftui/windowmenubarextrastyle.md
- MenuBarExtraAccess: https://swiftpackageregistry.com/orchetect/MenuBarExtraAccess
- Cindori, Floating panel in SwiftUI: https://cindori.com/developer/floating-panel
- Apple, NSScreen.auxiliaryTopLeftArea: https://developer.apple.com/documentation/appkit/nsscreen/auxiliarytopleftarea-uglc.md
- DynamicNotchKit: https://github.com/MrKai77/DynamicNotchKit
- Boring Notch: https://github.com/TheBoredTeam/boring.notch
- NotchNook (iMore): https://www.imore.com/apps/mac-apps/notchnook-app-that-turns-macbook-notch-into-a-dynamic-island-is-now-better-than-ever
- Apple HIG, Materials (Liquid Glass): https://developer.apple.com/design/human-interface-guidelines/materials.md
- Liquid Glass in Swift best practices: https://dev.to/diskcleankit/liquid-glass-in-swift-official-best-practices-for-ios-26-macos-tahoe-1coo
- Apple Support, iPhone notifications and Live Activities on Mac: https://support.apple.com/en-us/120684
- Apple, UNNotificationActionOptions: https://developer.apple.com/tutorials/data/documentation/usernotifications/unnotificationactionoptions.md
- Apple HIG, Managing notifications: https://developer.apple.com/design/human-interface-guidelines/managing-notifications.md
- MacRumors, Interactive widgets on Mac desktop: https://macrumors.com/how-to/use-interactive-widgets-mac-desktop
- MacStories, Third-party Control Center controls on Tahoe: https://www.macstories.net/stories/mystery-solved-why-third-party-apps-vanished-from-the-macs-control-center/
- Apple, NSAccessibility announcementRequested: https://developer.apple.com/documentation/appkit/nsaccessibility-swift.struct/notification/announcementrequested.md
- Apple, accessibilityReduceMotion: https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion.md

**UX guidance**
- Smashing Magazine, Designing for Agentic AI (Feb 2026): https://smashingmagazine.com/2026/02/designing-agentic-ai-practical-ux-patterns/
- Microsoft Research, Guidelines for Human-AI Interaction: https://www.microsoft.com/en-us/research/blog/guidelines-for-human-ai-interaction/
