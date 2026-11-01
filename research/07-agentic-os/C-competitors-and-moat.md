# C. Competitive Landscape and Moat Features for InstructFlow

*Research date: 2026-10-31. Scope: voice-first agentic layers on macOS. This builds on the Wispr Flow / OpenWhispr teardowns and macOS integration notes already in `research/`; it does not repeat them.*

**Bottom line.** By late 2026 the market has split into two camps that barely overlap:

1. **Voice-input apps** (Wispr Flow, Superwhisper, VoiceInk, FluidVoice, OpenWhispr, Aqua, Willow, Monologue). These are very good at speech to text in any text field. Their "agent" features stop at rewriting a selection, asking a chatbot a question, or opening an app. None of them runs governed, multi-step tool calls against local files, Mail, a shell, or Claude Code.
2. **Agent platforms** (ChatGPT desktop with Codex, Claude Cowork / computer use / Claude in Chrome, Perplexity Personal Computer, Siri AI in macOS 27, Raycast AI 2.x, Simular). These have strong tool use, but voice is either a separate chat surface (ChatGPT Voice, Gemini Live) or missing (Cowork, Raycast agent chat, Simular). None of them is built on dictation-grade input, an approval model you can audit, or published reliability numbers.

InstructFlow already sits in the gap between the two: a dictation core with a mode router and fidelity guardrail, plus agentd with typed Effects, policy, an audit log and an eval bench. The moat is to own **trustworthy voice-to-action on the local Mac**: measurably reliable, explicitly governed, screen- and context-aware, and open.

---

## 1. Product survey

### 1.1 Voice-input apps (dictation first)

| Product | Voice / agent capabilities today | Pricing | Open/closed | Notes |
|---|---|---|---|---|
| **Wispr Flow** | Dictation with styles and dictionary. **Command Mode** (experimental; Fn+Ctrl): edit or draft from the current text box or selection, or send a search to Perplexity. No multi-step actions. Bot-free Notetaker. A **remote MCP server** gives *read-only* access to meeting notes, transcripts and calendar; clients cannot create or edit content, or read dictation history. | Free 2k words/wk; Pro $15/mo ($12 annual); Growth $18-23/user; Growth+Notetaker $26-33 | Closed | About $81M raised. Says it wants to grow into an assistant for "messaging, note-taking, reminders" [1][2][3][4] |
| **Superwhisper** | Modes: a Whisper model plus an optional LLM prompt, assigned per app. Local models. No agent. A request for "tool calling via MCP" on its public board is still *Pending* (44 votes). | Free (small models); Pro $8.49/mo, $84.99/yr; Lifetime $249.99 | Closed | Mac, Windows, iOS [5][6] |
| **VoiceInk** | Power Mode (settings per app or URL), Smart Modes, BYO-key AI enhancement, Assistant Mode (ask an LLM by voice). No MCP or agent. | $25-49 one-time | **GPL-3.0** (about 6.5k stars) | [7] |
| **FluidVoice** | Local ASR (Parakeet, Nemotron, Whisper, Apple), Write Mode, prompts per app, **Command Mode: "control your Mac by voice"** (launch apps, run Shortcuts, system actions). No MCP or agent. | Free | **GPL-3.0** since Feb 2026 (Apache before); about 12.4k stars | The closest open-source peer to InstructFlow's agent direction [8] |
| **OpenWhispr** | v1.6+: **Agent mode**. The voice agent types its answer at the cursor. A chat agent can search and write notes, search the web and read the calendar. BYO provider or a local model. Bot-free meetings with Google Calendar. No MCP or approval model is documented. | Free plus cloud tier | Open (MIT per earlier teardown) | [9][10] |
| **Aqua Voice** | Avalon ASR (vendor claims 97.4% on its own AISpeak-10), "Deep Context," **MCP/CLI access**, Realtime Mode and voice commands (Max). Cloud only. | Pro $10-12/mo; Max $19-24/mo | Closed | [11] |
| **Willow** | Style memory per app, AI Mode, "Hey Willow" desktop Q&A assistant, Cursor/IDE support, offline mode (Mac/iOS). No agent actions. | Free 2k words/wk; $12-15/mo | Closed | Claims 200 ms latency (vendor figure) [12] |
| **Monologue (Every)** | Screen-aware "deep context" formatting, custom dictionary, voice commands, bot-free meeting notes. No agent. | $12-15/mo; $30 Every bundle | Closed | Mac + iOS [13] |
| **Talon Voice** | **Talon 1.0 (Sep 20, 2026)**: new GPU models (Hum dictation, Song commands with rejection, Tone speaker verification), Conformer D2, a third-generation eye-tracking algorithm. Fully scriptable command grammar. **No LLM integration.** | Free; beta and Talon+ via Patreon | Closed core, open community scripts | The gold standard for hands-free users with RSI, with a steep learning curve [14] |

### 1.2 Agent platforms and assistants

| Product | Voice | Agent / actions | Screen context | Pricing | Open/closed |
|---|---|---|---|---|---|
| **Siri AI (macOS 27 "Golden Gate", shipped Sep 14, 2026; 27.2 on Oct 26)** | Native Siri. Siri app. Gemini-backed per multiple reports | Actions in apps through **App Intents** only. Voice actions in about 13 domains (Mail, Messages, Notes, Calendar, Reminders, Files...). Spreadsheet, browser and presentation domains are Shortcuts-only. Shortcuts can be written in natural language. System-wide MCP for Siri/Core AI is *reported* by third parties [17]; code for MCP in App Intents was found in the 26.1 beta [18]. Verify before relying on it. | Personal and on-screen context. Visual Intelligence on Mac. On-screen awareness is described as **read-only**, and cross-app tasks as "challenging" | Free; M1+, best features need M3 with 12 GB or more | Closed [15][16][17][18] |
| **ChatGPT desktop (Voice + Codex, Jul 23, 2026)** | GPT-Live voice in the desktop app; you can interrupt mid-sentence | Voice launches and steers **several concurrent Codex/Work task threads**. Remote control from iOS. | **Appshots**: opt-in view of the frontmost window, Mac only | Plus about 15-30 min voice per 5 h; Pro $100 about 1-2.5 h; Pro $200 unlimited voice. No API for GPT-Live | Closed [19] |
| **Claude (desktop, Cowork, computer use, Chrome, Code)** | Desktop: **dictation only** through Quick Entry (Caps Lock). Two-way Voice Mode on web/mobile. Claude Code `/voice` (hold Space) | **Cowork** GA on all paid plans (Apr 2026): local files, connectors, controls per tool. **Computer use + Dispatch** on Mac (research preview, Mar 2026, Pro/Max): starts from the phone and runs on the Mac. **Claude in Chrome** GA (Aug 26, 2026): navigates and fills forms, with a safety classifier on each action instead of a prompt per step | Screenshots (computer use) | Paid plans | Closed (MCP is open) [20][21][22][23] |
| **Gemini for Mac (Apr 15, 2026)** | Gemini Live, "Speak to Window" dictation and "Magic Pointer" are **in testing** | No local actions announced | Window/file sharing; Option+Space overlay | Free | Closed [24][25] |
| **Raycast AI (v2.3-2.10, Sep-Oct 2026)** | Dictate command with LLM post-processing, shared with AI Chat | AI Chat rebuilt to **plan, use extensions, run code, pause for decisions**. MCP server management. Projects + Automations. BYO model / Ollama. Expanded permission approvals | "Send Element / Window to AI" | Usage-based (v2.3) | Closed core, open extensions [26] |
| **Perplexity Personal Computer (Mac, Apr-May 2026)** | Press both ⌘ keys; voice or text | Local files and native apps, multi-step workflows, a sandbox for files it creates. Pairs with Comet to drive web tools. Actions "auditable and reversible" | Sees active apps | Requires Pro/Max/Enterprise | Closed; hybrid local-cloud [27] |
| **VoiceOS (YC S25)** | Dictate, Agent, Edit | Multi-step workflows with Gmail, Slack, Calendar, Notion and Drive; developer integrations | Answers about the screen | Not public | Closed [28] |
| **Highlight AI** | Hands-free voice | Meeting notes, task tracking, Gmail/Slack/Linear/Notion | Reads the screen | Freemium; $40M Series A (Mar 2026) | Closed; claims local-first [29] |
| **Littlebird** | Not covered | Always-on screen memory, meeting notes, **Routines** (morning briefings), MCP (Power tier) | Continuous capture of the active window | Free; $17-20; Power $42-50 | Closed; memory on AWS [30] |
| **Screenpipe** | Audio capture/transcripts | "Pipes" (plugins), MCP server | 24/7 local screen + audio recording | Freemium (see listing) | Open source (MIT core) [31] |
| **Limitless / Rewind** | n/a | n/a | **Discontinued**: Meta bought Limitless (Dec 5, 2025); Rewind capture disabled Dec 19, 2025 | n/a | [32] |
| **Granola** | Meeting audio | MCP (Feb 2026), personal + enterprise APIs, Spaces. Lost trust with power users after **locking its local cache, which broke local agent workflows** | n/a | $1.5B valuation (Mar 2026) | Closed [33] |
| **Cluely** | System-audio STT | Answers only, no actions | OCR the screen into a hidden overlay | Free; $20; $75 "undetectable" | Closed [34] |
| **Clicky** | Voice via AssemblyAI + ElevenLabs | Guides you through tasks next to the cursor | Sees the screen | Free | Open source [35] |
| **Open Interpreter** | Not in current desktop app (01 voice device effectively dormant) | Desktop agent with Word/Excel/PDF editors; experimental macOS control (Pro) | Partial | Free / $20 / $60 | Open core [36] |
| **Simular (Sai / Agent S)** | None | GUI + terminal + API agent, local or cloud VM, pauses for approval on sensitive actions | Screenshot GUI agent | Trial | Agent S open source; Sai closed [37] |

### 1.3 Feature matrix

Legend: ● strong / shipped · ◐ partial / beta / limited · ○ absent · ? unclear

| Capability | Wispr | Super-whisper | VoiceInk | Fluid-Voice | Open-Whispr | Aqua | Talon | Siri macOS 27 | ChatGPT desk | Claude (Cowork/CU/Chrome) | Raycast | Perplexity PC | Littlebird / Screenpipe | **InstructFlow (today)** |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Dictation-grade insertion in any app | ● | ● | ● | ● | ● | ● | ● | ◐ | ○ | ◐ | ◐ | ○ | ○ | ● |
| Intent/app-aware cleanup | ● | ● | ● | ● | ◐ | ● | ○ | ◐ | ○ | ○ | ◐ | ○ | ○ | ● (7 modes + fidelity guard) |
| Voice edit of selection | ● | ◐ | ◐ | ● | ◐ | ● | ● | ◐ | ○ | ○ | ○ | ○ | ○ | ○ (planned) |
| Multi-step local tool use (files, shell) | ○ | ○ | ○ | ◐ | ○ | ○ | ◐ (scripts) | ◐ | ● (Codex) | ● | ● | ● | ○ | ● |
| MCP client (mount arbitrary servers) | ○ | ○ | ○ | ○ | ○ | ◐ | ○ | ◐? | ● | ● | ● | ? | ○ | ○ (planned) |
| Exposes itself as MCP server | ◐ (read-only notes) | ○ | ○ | ○ | ○ | ● | ○ | n/a | n/a | n/a | ○ | ○ | ● | ○ |
| Typed effect policy + audit log | ○ | ○ | ○ | ○ | ○ | ○ | ○ | ○ | ◐ | ◐ (classifier; controls per tool) | ◐ | ◐ ("auditable") | ○ | ● |
| Voice approval of risky steps | ○ | ○ | ○ | ○ | ○ | ○ | n/a | ◐ | ? | ○ | ○ | ? | ○ | ○ (click only) |
| Screen-aware deixis ("this", "that file") | ○ | ○ | ○ | ○ | ○ | ◐ | ○ | ◐ (read-only) | ◐ (Appshots) | ◐ | ◐ | ◐ | ◐ | ◐ (app/window title) |
| Parallel background agents with voice status | ○ | ○ | ○ | ○ | ○ | ○ | ○ | ○ | ● | ◐ (Dispatch) | ○ | ◐ | ○ | ○ |
| Steering multiple coding agents by voice | ○ | ○ | ○ | ○ | ○ | ○ | ○ | ○ | ● (Codex only) | ◐ (/voice in one session) | ○ | ○ | ○ | ◐ (claude_code_task) |
| Spoken output (TTS) | ○ | ○ | ○ | ○ | ○ | ○ | ○ | ● | ● | ◐ | ○ | ? | ○ | ○ |
| Activity timeline memory | ○ | ○ | ◐ (history) | ◐ | ◐ | ○ | ○ | ◐ | ○ | ○ | ○ | ○ | ● | ◐ (audit log) |
| On-device / offline path | ○ | ● | ● | ● | ● | ○ | ● | ● | ○ | ○ | ◐ (Ollama) | ○ | ◐ (Screenpipe) | ● (Parakeet fallback) |
| Published reliability evals | ○ | ○ | ○ | ○ | ○ | ◐ (vendor ASR bench) | ○ | ○ | ○ | ○ | ○ | ○ | ○ | ● (bench/) |
| Open source | ○ | ○ | ● | ● | ● | ○ | ◐ | ○ | ○ | ○ | ◐ | ○ | ◐ | ● (Apache-2.0) |

### 1.4 Gaps that nobody, or almost nobody, fills well

1. **Dictation-grade voice combined with governed local agency.** The voice-input apps have no tool runtime. The agent platforms treat voice as an add-on chat. No product does both with typed effects, an allowlist and an audit log. FluidVoice's Command Mode and OpenWhispr's agent are the nearest, and both stop at launching things or chatting.
2. **Published, reproducible reliability numbers for voice-to-action.** Vendors publish ASR accuracy at most (Aqua's self-run AISpeak-10). No one publishes task success rates, false-action rates or latency percentiles per intent.
3. **Approval UX designed for voice.** Claude in Chrome removed per-step approval in favour of a classifier [22]. Academic work shows approval dialogs that the agent writes itself can lie ("Lies-in-the-Loop") [38]. No product renders approvals from the actual action, keeps them glanceable, and allows a spoken yes only for low-risk classes.
4. **Deixis across apps.** Siri's on-screen awareness is read-only [16]. ChatGPT's Appshots covers only the frontmost window. Nobody resolves "this", "these three files", "that PR" or "the email I just read" into typed entities across Finder, Mail, the browser and terminals.
5. **One voice channel for many agents.** ChatGPT steers Codex threads by voice, but only OpenAI's agents. Nobody orchestrates *Claude Code sessions, local scripts and MCP tools* together, with a spoken status line and interruptible updates.
6. **Learning from repetition.** No product turns repeated voice tasks into reusable, named and testable macros.
7. **Local-first memory you own and agents can use.** Rewind is gone [32], Granola locked its cache [33], and Littlebird stores memory on AWS [30]. Screenpipe is open but records everything and has no voice agent.
8. **Hands-free power use with LLMs.** Talon 1.0 is excellent for hands-free control but has no LLM [14]. LLM dictation apps are poor at commanding the computer. macOS Voice Control still has no text-editing commands [39].

---

## 2. Voice UX research

### 2.1 When voice beats typing, and when it loses

**Voice wins:**
- **Raw text entry.** In a controlled study, speech was about 3.0x faster than a phone keyboard in English and 2.8x in Mandarin, with 20% fewer errors in English and 63% fewer in Mandarin [40]. On a desktop keyboard the speed gap is smaller but still real for prose. Wispr's thesis and its retention numbers (about 80% at six months, per [3]) back this up.
- **Commands that state an intent rather than a location.** "Move every PDF in Downloads from last week into Taxes/2026" is one sentence spoken and many clicks by hand. Voice gains most when one utterance replaces many GUI steps.
- **Hands busy or hurting.** RSI, a cast, holding a baby (relevant to the user: a new father), cooking, or standing at a whiteboard.
- **Delegating to agents.** Prompts for Claude Code or Codex are long, mostly prose, and tolerate small errors. OpenAI's July 2026 launch of voice for steering Codex [19] shows the category has noticed.

**Voice loses:**
- **Precise editing and navigation.** Character-level edits, cursor placement and selection. Even Talon users depend on careful grammars. A heavy user of macOS Voice Control found no text-editing commands and frequent errors with homonyms, plurals and quotes [39].
- **Symbol-dense content.** Code syntax, regexes, file paths and numbers. Here voice should *describe* and an agent should *write*.
- **Open-plan offices and private content.** Social cost and eavesdropping. Always-on listening picks up other people in the room [39].
- **Reading out output.** Speech is linear and transient. NN/g found that assistants work only for "very limited queries with simple, short answers" [41]. Lists, diffs and tables belong on screen.
- **Undiscoverable commands.** Voice offers no affordances, and recall-heavy command sets add memory load [42].

**Design rule for InstructFlow:** speak the *intent*, look at the *evidence*, and touch or glance to *commit* when the stakes are high.

### 2.2 Latency expectations

- In human conversation the median gap between turns is about **200 ms** across 10 languages (Stivers et al., 2009, as summarised in [43]). Voice agent practitioners use about **800 ms** voice-to-voice as the limit for feeling natural [44].
- For **command-and-act** systems, as opposed to conversation, the usual HCI thresholds apply: under 100 ms feels instant (keypress to HUD state change), under 1 s keeps the flow of thought (first visible acknowledgement), and under 10 s holds attention (task completion, or else show progress).
- Recommended budgets for InstructFlow:

| Stage | Target p50 / p95 |
|---|---|
| Hotkey release to HUD "heard you" | < 100 ms |
| Final transcript (streaming STT) | < 300 / 600 ms |
| Intent and plan shown ("I'll do X, Y, Z") | < 1.2 / 2.5 s |
| First tool result or spoken acknowledgement | < 2 / 4 s |
| Long tasks | Move to the background immediately, with a voice and HUD status channel |

- Techniques: overlap the stages and start reasoning speculatively on partial transcripts [43]; acknowledge slow steps based on *real system state* such as "searching 1,240 files..." rather than LLM filler [43]; cache plans for macros.

### 2.3 Confirmation and approval design for risky actions

- **Choose confirmation by risk, not by habit.** Conversation-design practice: implicit confirmation ("Opening Figma") for reversible low-risk actions; explicit confirmation for irreversible or external effects; *no* voice-only confirmation for spend, delete or send. This matches InstructFlow's current policy.
- **Approval fatigue is real, and an approval written by the agent can lie.** Weng (2026) shows that a compromised agent can describe a harmless action while running a different one. The fix is *Consent Integrity*: a trusted mediator renders the approval from the actual action [38]. InstructFlow's typed ToolContracts allow exactly this: render the card from the arguments, never from the model's narration.
- **The industry is drifting toward classifiers instead of per-step consent** (Claude in Chrome [22]). That is a positioning opening: "you always see what will actually run."
- **Voice-specific rules:**
  - Read back the *object* and the *effect*, not the plan. Say "Send to Priya, subject 'Q3 numbers', 2 attachments", not "I'll send the email."
  - Never accept "yes" as approval for send, spend or delete. Require a glance plus a key, or a spoken one-time token shown on the HUD ("say *blue seven*"). The token defeats accidental "yeah" and audio from other people.
  - Use speaker verification for any voice approval (Talon 1.0 ships a speaker-verification model, Tone [14], so this is now practical on device).
  - Show a diff preview for writes, a dry-run file list for moves, and the exact command line for shell steps.

### 2.4 Barge-in, interruption and undo

- Barge-in in two layers: (1) on the media side, stop TTS and flush buffers the moment the user speaks, with echo cancellation; (2) on the logic side, cancel pending generations *and tool calls*, and record the interrupted turn [43].
- Measure **barge-in latency**: first interrupting sound to the agent going silent, target under 150 ms.
- Treat "stop", "wait" and "no, the other one" as protected local keywords spotted on device, never routed through the cloud LLM.
- **Undo as a primitive.** Every write_local or move records an inverse operation (a journal or APFS snapshot), so "undo that" reverts the last agent action. Perplexity markets "reversible" actions [27]; nobody exposes undo by voice.

### 2.5 Ambient and hands-free use

- Wake words are risky on a desktop (false triggers, privacy). Prefer push-to-talk by default and offer an optional **"conversation window"** (as Wispr's "Flow Sessions" do [3]): a few seconds after a reply during which follow-ups need no hotkey.
- For fully hands-free users (RSI or motor impairment), add Talon-style local command grammars for navigation alongside LLM intent for everything else. Eye tracking can be a selection signal ("this one").

### 2.6 Spoken results (TTS) or visual HUD

- Default to **visual**: lists, diffs, file sets, tables.
- Speak only (a) short confirmations, (b) background-task status ("tests passed, PR ready for review"), (c) briefings when the user is away from the screen, and (d) questions that block progress.
- Keep spoken output to two sentences or less, with an option to "show me" that expands on the HUD.

### 2.7 Multi-turn voice clarification

- Ask only when it is *cheap and decisive*. Offer two or three options with numbers on the HUD ("1: Taxes/2026, 2: Taxes/2025?") so the user can answer "one" or glance and click.
- Carry state forward: "the other one" and "same for last month" should resolve against the previous plan.
- Measure the clarification rate per intent, and turn repeated clarifications into a learned default.

### 2.8 Accessibility as a real market

- Musculoskeletal disorders are common: about 511k affected workers and 7.1M lost days in Great Britain in 2024/25 (HSE) [45]. Wispr reports users with ADHD, dyslexia, paralysis and carpal tunnel syndrome [3].
- WHO estimates about 1.3 billion people (16%) live with significant disability [46].
- Incumbents leave clear gaps. macOS Voice Control has no text-editing commands, an overlay that adds clutter, and commands that demand heavy recall [39][42]. Talon is powerful but takes weeks to learn and has no LLM [14]. **"Talon power without Talon's learning curve"** is an underserved niche with intense loyalty, and it is a strong story for a portfolio piece.

---

## 3. Moat features for InstructFlow (22)

Difficulty: S = days, M = 1-3 weeks, L = more than a month (solo developer).

### A. Trust and reliability (core brand)

**1. Public Reliability Ledger (evals as the brand).**
- *Description:* Extend `bench/` to measure voice-to-action as well as STT. Report task success, false-action rate, unsafe-action attempts blocked, clarification rate, and latency p50/p95 by intent and effect class. Re-run in CI on every release and publish a versioned dashboard plus a badge in the README.
- *Why competitors lack it:* Closed vendors cannot publish failure rates without hurting marketing; at most they publish ASR benchmarks [11].
- *Value:* Users can see the tool is trustworthy, and it showcases the user's evaluation expertise to frontier labs.
- *Difficulty:* M. *Depends on:* the scenario harness, deterministic tool mocks, and recorded audio fixtures.

**2. Consent-Integrity approval cards.**
- *Description:* The approval UI is rendered by the Swift app from the typed ToolContract arguments: exact recipient, file list, command line, diff. It is never rendered from model text. A hash links each approval to the exact call that executes [38].
- *Why competitors lack it:* Most show the agent's own narration, or skip consent and rely on a classifier [22].
- *Value:* Defeats "Lies-in-the-Loop" attacks and prompt injection hidden in emails or web pages.
- *Difficulty:* S-M. *Depends on:* the existing Effects schema and AgentPanel.

**3. Approval by glance plus spoken challenge.**
- *Description:* Steps that only write or execute can be approved by looking at the card (gaze from the camera or the mouse position) and saying a one-time token shown on the card ("approve *amber four*"), with on-device speaker verification. Send, spend and delete still require a click.
- *Why competitors lack it:* Nobody has designed voice consent beyond "yes/no."
- *Value:* Truly hands-free governed agents without accidental approvals.
- *Difficulty:* M. *Depends on:* local keyword spotting, an optional speaker-embedding model, and policy classes.

**4. Plan-only dry run with a voice diff.**
- *Description:* Say "dry run" or "what would you do" and agentd runs every read for real, simulates writes, and shows a visual diff of the planned changes (moves, edits, emails) to approve as a batch.
- *Why competitors lack it:* Agents usually interleave thinking and acting.
- *Value:* Safe bulk operations such as reorganising folders or triaging mail.
- *Difficulty:* M. *Depends on:* tool contracts with a `simulate()` path.

**5. Voice undo journal.**
- *Description:* Every local effect records an inverse (move back, restore from a journal or APFS snapshot, delete a created draft). Saying "undo that" or "undo the last three" reverts it, and the audit log links to the inverse.
- *Why competitors lack it:* "Reversible" is marketing at Perplexity [27]; nobody offers undo by voice.
- *Value:* Users experiment more readily, which speeds adoption.
- *Difficulty:* M. *Depends on:* write_local/move tools and a snapshot store.

**6. Local-first privacy guarantees, verified by evidence.**
- *Description:* A "Private mode" pins STT to Parakeet, the LLM to a local model, and network egress to an allowlist. A live egress monitor in the HUD and a signed report per session ("0 bytes left the machine") prove it.
- *Why competitors lack it:* The agent platforms depend on the cloud; Cluely and Littlebird send screens upstream [30][34].
- *Value:* Finance, health and work-secret tasks become possible (the user's own investments and health workflows).
- *Difficulty:* M. *Depends on:* the FluidAudio fallback, an Ollama/MLX model, and a network-extension or proxy check.

### B. Context and understanding

**7. Screen-aware deixis resolver.**
- *Description:* Resolve "this", "these", "that file", "the PR I'm looking at" and "the email above" into typed entities, using the AX tree, Finder selection, the browser URL and DOM (via Chrome or Safari), the terminal cwd and recent clipboard. Show a chip on the HUD with the resolved entity before acting.
- *Why competitors lack it:* Siri's screen context is read-only and limited to App Intents [16]; Appshots is one window [19].
- *Value:* Removes the biggest cost of voice commands, which is having to name things.
- *Difficulty:* L. *Depends on:* AX field-role detection (planned), Finder AppleScript bridges, and a browser extension or MCP.

**8. "What was I doing?" timeline memory (event-based, not screen recording).**
- *Description:* A local, encrypted timeline of *events* (app focus, window titles, files touched, agent runs, dictations, URLs), not screenshots. Queries like "what was I working on before lunch", "reopen everything from the Acme debugging session" or "summarise my day" work across it.
- *Why competitors lack it:* Rewind is dead [32]; Screenpipe records everything (heavy and invasive); Littlebird's memory is in the cloud [30].
- *Value:* Lets the user resume work after interruptions (very relevant for a new parent), and feeds the briefings.
- *Difficulty:* M. *Depends on:* NSWorkspace notifications, the audit log, and SQLite FTS plus embeddings.

**9. Auto-learning personal dictionary and style.**
- *Description:* Watch edits made after insertion (diff the AX value about 10 s later) and the corrections the user speaks. Promote recurring fixes into the dictionary and the cleanup prompts per mode, with a review queue. Show each learned rule with its provenance.
- *Why competitors lack it:* Wispr and Willow learn inside a black box; open apps rely on manual dictionaries.
- *Value:* Accuracy keeps improving on names and jargon (vendor names, Parakeet, team names).
- *Difficulty:* M. *Depends on:* AX read-back and the CleanupKit rule prepass.

**10. Spoken @-mentions and entity grammar.**
- *Description:* "At file auth middleware", "at repo agentd" or "at Sam" resolve by fuzzy match to files, repos and contacts, shown as chips before sending to Claude Code or Mail.
- *Why competitors lack it:* Dictation tools insert text, not references.
- *Value:* Precise prompts for coding agents by voice.
- *Difficulty:* S-M. *Depends on:* find_files and a contacts index.

### C. Orchestration (the "agentic OS" core)

**11. Parallel background agents with a voice status channel.**
- *Description:* Tasks go to the background by default. A small queue in the menu bar shows each task's state. A short spoken bulletin plays at natural pauses, never while the user is dictating ("Folder cleanup done: 42 files moved. Tests still running."). "Status?" gives a spoken roll-up.
- *Why competitors lack it:* ChatGPT does this only for its own Codex threads [19]; dictation apps run one task at a time and synchronously.
- *Value:* The user can delegate and keep working.
- *Difficulty:* M. *Depends on:* agentd job queue, ElevenLabs TTS, and a "safe-to-speak" detector (no dictation or call in progress).

**12. Voice conductor for multiple Claude Code sessions.**
- *Description:* Name the sessions ("backend", "evals", "docs"). Utterances like "backend: fix the failing auth test; evals: rerun suite B and tell me the delta" route to the right session. Questions from sessions arrive as voice-and-HUD cards; "approve backend's plan" works too. Built on the Claude Code CLI/SDK with git worktrees.
- *Why competitors lack it:* Claude Code `/voice` works inside one terminal [20]; ChatGPT works only with Codex.
- *Value:* The flagship demo for Anthropic, and directly useful to the user's daily work.
- *Difficulty:* L. *Depends on:* claude_code_task, worktree management and session naming.

**13. MCP mounting with effect inference.**
- *Description:* Mount any MCP server (Gmail, Calendar, GitHub, Robinhood-style brokers, Granola, Wispr notes). On mount, classify each tool's Effect from its schema and annotations, with an LLM suggestion that the user confirms, so the existing policy engine governs third-party tools.
- *Why competitors lack it:* MCP clients mostly treat tools as trusted or not; dictation apps do not mount MCP (Superwhisper's request is still pending [6]).
- *Value:* Huge reach with safety intact.
- *Difficulty:* M. *Depends on:* MCP TS SDK in agentd and an Effects mapping UI.

**14. Cross-app voice workflows (Shortcuts, AppleScript and App Intents bridges).**
- *Description:* Tools `run_shortcut`, `applescript` (sandboxed templates) and App Intents invocation, plus MCP if Apple opens it [18]. Examples: "Draft replies to the three unread emails from work in Mail, put them in drafts, and remind me at 4," or "Export this Numbers sheet as CSV into the research folder."
- *Why competitors lack it:* Siri covers about 13 domains and only through App Intents [16]; Raycast is extension-bound.
- *Value:* Real tasks spanning several apps, which is the defining "OS" capability.
- *Difficulty:* M-L. *Depends on:* Automation permissions and template libraries.

**15. Voice macros learned from repetition.**
- *Description:* Detect repeated plans in the audit log (same tool sequence with different arguments). Offer: "You've done this 4 times. Save it as 'file receipts'?" Each macro is a parameterised, version-controlled YAML plan with its own eval test, runs deterministically without the LLM when possible, and is invoked as "file receipts for October."
- *Why competitors lack it:* No product learns macros from voice-driven agent traces.
- *Value:* Faster, cheaper and more reliable over time, which sets up a compounding moat.
- *Difficulty:* M. *Depends on:* structured audit log and plan replay.

**16. Voice-first code review.**
- *Description:* "Review Sam's PR" fetches the diff (gh MCP). Claude summarises the risks on the HUD and reads at most two sentences aloud. The user speaks comments ("on line 40, ask why we retry three times"), which are converted into anchored review comments, held as drafts, and posted only after a click.
- *Why competitors lack it:* Voice tools dictate prose but do not anchor comments to code.
- *Value:* A daily mentorship workflow (the user reviews a junior engineer's work).
- *Difficulty:* M. *Depends on:* GitHub MCP and the deixis resolver for line anchors.

**17. Edit mode with structural targets.**
- *Description:* Command Mode extended beyond "rewrite selection" to targets like "make the second paragraph shorter", "turn these bullets into a table" or "fix the function name everywhere in this file", applied through AX or the editor's API and shown as an inline diff.
- *Why competitors lack it:* Wispr and FluidVoice operate on the selection only [2][8]; macOS Voice Control has no editing commands [39].
- *Value:* Removes one of voice's weakest points (Section 2.1).
- *Difficulty:* M. *Depends on:* AX text ranges and the CleanupKit fidelity guard.

### D. Proactive and personal

**18. Spoken daily briefing (ElevenLabs TTS) built from local signals.**
- *Description:* A 60-90 second morning audio brief from Calendar, flagged mail, overnight agent results, CI status, a portfolio delta (read-only), and yesterday's timeline ("you left off in agentd/policy.ts"). It is also exported as a podcast-style file for the commute. Interrupt with "skip" or "more on that".
- *Why competitors lack it:* Littlebird Routines are text and cloud-based [30]; Siri does not compose across agents.
- *Value:* A daily habit that makes the product sticky.
- *Difficulty:* M. *Depends on:* the timeline (#8), connectors and the ElevenLabs API.

**19. Accessibility profile: "Talon-lite plus LLM."**
- *Description:* A fully hands-free mode. Local keyword grammar for navigation (click, scroll, switch, select) through on-device KWS, LLM intent for everything else, an optional eye-tracking target, fatigue-aware pacing, and a "never require a click" policy profile backed by challenge-token approvals (#3).
- *Why competitors lack it:* Talon has no LLM [14]; LLM dictation apps cannot drive the GUI.
- *Value:* A loyal niche with a real need, strong press and portfolio story.
- *Difficulty:* L. *Depends on:* AX actions, #3, and a KWS model.

**20. Risk-aware finance co-pilot (read-mostly).**
- *Description:* "How did my portfolio move this week and why?" uses brokerage MCP or CSV exports with read-only effects. Trade-like actions are permanently BLOCKED (spend_money). The tool can prepare an order ticket for manual entry, but never submit it.
- *Why competitors lack it:* General agents avoid finance; dictation apps can't.
- *Value:* Personally useful to the user (FIRE tracking), and a showcase for strict policy.
- *Difficulty:* M. *Depends on:* MCP mounting (#13) and Private mode (#6).

### E. Platform and ecosystem

**21. InstructFlow as an MCP server ("voice I/O for any agent").**
- *Description:* Expose `ask_user_by_voice`, `speak_status`, `get_focused_context`, `request_approval` (rendered with Consent Integrity) and `get_timeline` as MCP tools. Claude Code, Cursor or Codex can then interrupt the user by voice and get a governed approval.
- *Why competitors lack it:* Wispr's MCP is read-only notes [4]; nobody offers an approval channel or a human-in-the-loop voice channel as MCP.
- *Value:* InstructFlow becomes infrastructure that other agents depend on.
- *Difficulty:* M. *Depends on:* the agentd socket and the HUD.

**22. Reproducible "trace cards" for sharing and debugging.**
- *Description:* Every task produces a redacted, shareable trace (audio, transcript, mode decision, plan, tool calls, approvals, outcome, latency waterfall). One click turns a failure into a new `bench/` scenario.
- *Why competitors lack it:* Closed apps hide their pipelines.
- *Value:* Closes the loop from bug to eval to fix, and gives material for the Substack "Evals-Driven Development" series.
- *Difficulty:* S-M. *Depends on:* the audit log and bench schema.

### Prioritisation

| Rank | Feature | Why first |
|---|---|---|
| 1 | #1 Reliability Ledger + #22 Trace cards | Uniquely the user's strength; builds on assets that already exist |
| 2 | #2 Consent-Integrity cards + #4 Dry run + #5 Undo | Turns the existing policy engine into a visible advantage |
| 3 | #13 MCP mounting with effect inference | Unlocks Gmail, Calendar, GitHub and finance at once |
| 4 | #12 Multi-session Claude Code conductor + #11 Voice status channel | The flagship demo for Anthropic and OpenAI audiences |
| 5 | #7 Deixis + #17 Structural edit | Fixes voice's weakest UX points |
| 6 | #15 Learned macros + #8 Timeline + #18 Briefing | Compounding moat and a daily habit |
| Later | #3 Glance approval, #19 Accessibility profile, #21 MCP server, #6 Private mode proof | Differentiators once the core is solid |

**Positioning line:** *"The open-source voice layer for your Mac that does things, shows you exactly what it will do before it does it, and publishes how often it gets things right."*

---

## Sources

1. Voibe, "Wispr Flow Pricing 2026" (updated Oct 15, 2026): https://www.getvoibe.com/resources/wispr-flow-pricing/
2. Wispr Flow Docs, "How to use Command Mode": https://docs.wisprflow.ai/articles/4816967992-how-to-use-command-mode
3. Wikipedia, "Wispr Flow": https://en.wikipedia.org/wiki/Wispr_Flow
4. Wispr Flow Docs, "Connect an MCP client to Wispr Flow (remote MCP server)": https://docs.wisprflow.ai/articles/9551372685-connect-an-mcp-client-to-wispr-flow-remote-mcp-server
5. Voibe, "Superwhisper Review" (updated Oct 12, 2026): https://www.getvoibe.com/resources/superwhisper-review/
6. Superwhisper feature board, "Tool calling via MCP": https://superwhisper.userjot.com/board/p/tool-calling-via-mcp
7. Voibe, "VoiceInk Review 2026": https://www.getvoibe.com/resources/voiceink-review/
8. GitHub, altic-dev/FluidVoice: https://github.com/altic-dev/FluidVoice
9. OpenWhispr Docs, "Agent mode": https://docs.openwhispr.com/guides/agent-mode
10. NewReleases, OpenWhispr v1.6.0: https://newreleases.io/project/github/OpenWhispr/openwhispr/release/v1.6.0
11. Voibe, "Aqua Voice Review 2026" (updated Oct 30, 2026): https://www.getvoibe.com/resources/aqua-voice-review/
12. Voibe, "Willow Voice Review 2026": https://www.getvoibe.com/resources/willow-voice-review/
13. Voibe, "Monologue Review 2026": https://www.getvoibe.com/resources/monologue-review/
14. Talon changelog (Talon 1.0, Sep 20, 2026): https://talonvoice.com/dl/latest/changelog.html
15. Macworld, "macOS 27 Golden Gate has arrived": https://www.macworld.com/article/3139330/macos-27-golden-gate-has-arrived-heres-what-s-new-on-your-mac.html
16. Elephas, "macOS 27 Siri Apps" (Aug 2026): https://elephas.app/resources/macos-27-siri-apps
17. Stork.ai, "WWDC 2026, Graded" (reports system-wide MCP; unverified): https://stork.ai/blog/wwdc-2026-graded-what-apple-shipped-ios-27
18. 9to5Mac, "macOS Tahoe 26.1 beta 1 MCP integration": https://9to5mac.com/2025/09/22/macos-tahoe-26-1-beta-1-mcp-integration/
19. Digital Applied, "ChatGPT Voice on desktop + Codex" (Jul 25, 2026): https://www.digitalapplied.com/blog/chatgpt-voice-desktop-codex-hands-free-agentic-coding
20. VoiceDash, "Claude Voice Input in 2026": https://voicedash.ai/?p=13702
21. eWeek, "Claude Cowork general availability": https://www.eweek.com/fr/news/claude-cowork-general-availability-enterprise-controls/
22. Tech Bytes, "Claude in Chrome is generally available": https://techbytes.app/posts/claude-in-chrome-is-generally-available/
23. Buttondown/Verified, "Anthropic's Computer Use and Dispatch rollout": https://buttondown.com/verified/archive/anthropics-computer-use-and-dispatch-rollout-ai
24. iClarified, "Google launches native Gemini app for Mac": https://www.iclarified.com/100564/google-launches-native-gemini-app-for-mac-with-window-sharing-instant-context
25. Android Authority, "Gemini Mac app: Magic Pointer, Gemini Live, voice dictation": https://www.androidauthority.com/gemini-mac-app-magic-pointer-gemini-live-voice-dictation-3681280/
26. Raycast macOS changelog: https://www.raycast.com/changelog/macos
27. MacRumors, "Perplexity's New Mac App Brings Personal Computer to Pro Users": https://www.macrumors.com/2026/05/07/perplexity-mac-app-personal-computer/
28. VoiceOS blog, "Voice operating system": https://www.voiceos.com/blog/voice-operating-system-thought-to-action
29. ToolDirectory, "Highlight AI": https://tooldirectory.ai/tools/highlight-ai
30. Just Being Resourceful, "Littlebird AI Review (2026)": https://justbeingresourceful.com/2026/09/21/littlebird-ai-review-the-assistant-that-already-knows-what-youre-working-on-2026/
31. Screenpipe MCP listing: https://mcpservers.org/es/servers/mediar-ai/screenpipe
32. 9to5Mac, "Rewind / Limitless Meta acquisition": https://9to5mac.com/2025/12/05/rewind-limitless-meta-acquisition/
33. TechCrunch (via reader), "Granola raises $125M": https://hn.jakechampion.name/reader/https://techcrunch.com/2026/03/25/granola-raises-125m-hits-1-5b-valuation-as-it-expands-from-meeting-notetaker-to-enterprise-ai-app
34. Dupple, "Cluely review": https://dupple.com/reviews/cluely
35. FeedBagel, "Clicky: free open-source macOS AI assistant": https://feedbagel.com/post/clicky-free-open-source-macos-ai-assistant-powered-by-claude-assemblyai-and-elev
36. ToolDirectory, "Open Interpreter": https://tooldirectory.ai/tools/open-interpreter
37. ToolDirectory, "Simular": https://tooldirectory.ai/tools/simular
38. Weng, "What You Approve Is What Executes: Consent Integrity for Black-Box LLM Agents" (arXiv 2606.02668): https://arxiv.org/html/2606.02668
39. TidBITS, "What a broken wrist taught me about iOS 27 dictation and macOS Voice Control" (Sep 21, 2026): https://tidbits.com/2026/09/21/what-a-broken-wrist-taught-me-about-ios-27-dictation-and-macos-voice-control/
40. Ruan, Wobbrock, Liou, Ng, Landay, Stanford HCI, speech vs. typing study: https://hci.stanford.edu/research/speech/paper.html
41. Nielsen Norman Group, "Intelligent Assistants: Where We Are and Where We Should Be": https://www.nngroup.com/videos/intelligent-assistants-where/
42. Pratt IxD, "Assistive Technology: Voice Control on Mac OS" (Sep 2026): https://ixd.prattsi.org/2026/09/assistive-technology-voice-control-on-mac-os/
43. Picovoice, "Voice UX: Latency, Turn-Taking, and Barge-In" (cites Stivers et al. 2009, PNAS): https://picovoice.ai/guide/voice-agents/voice-ux-latency-turn-taking/
44. Twig, "Latency Budgets for Voice AI Agents: The 800ms Rule": https://www.twig.so/blog/voice-ai-agents-latency-budget-800ms
45. Yaps, "Voice input for RSI and accessibility" (cites HSE 2024/25, BLS): https://www.yaps.ai/de/blog/voice-input-rsi-accessibility
46. WHO disability statistics summary: https://scienceinsights.org/who-disability-statistics-global-numbers-and-trends/

*Source caveats: several product reviews (Voibe, Spokenly, Yaps) are published by competing dictation vendors, and their figures come from vendor pricing pages on the dates stated. Claims that macOS 27 ships system-wide MCP come from third-party commentary [17], with only beta-code evidence from Apple [18]; check Apple developer documentation before building on them. Some vendor homepages (wisprflow.ai, superwhisper.com, screenpipe.com) could not be fetched in this session, so secondary sources were used.*
