# Voice-to-Action for macOS: Research Report (Phase 1)

*2026-10-30. This synthesizes five detailed reports in this folder; see them for sources and evidence:*

| # | Report | Covers |
|---|---|---|
| 01 | [01-rea-review.md](01-rea-review.md) | morluto/rea architecture, quality, fit, improvement suggestions |
| 02 | [02-wispr-flow.md](02-wispr-flow.md) | Wispr Flow feature catalog (claims carry [H]/[M]/[L] confidence marks) |
| 03 | [03-openwhispr.md](03-openwhispr.md) | OpenWhispr in depth (read-only source review at v1.11.0, b9e9ebef) |
| 04 | [04-stt-llm-options.md](04-stt-llm-options.md) | STT and LLM latency/accuracy options; benchmark method |
| 05 | [05-macos-integration-and-oss.md](05-macos-integration-and-oss.md) | macOS hotkey/audio/insertion APIs; app compatibility; other open-source tools |

Nothing was built, installed, or benchmarked. All numbers come from published sources and are tagged vendor-claimed vs. independent in report 04.

---

## 1. Headline findings

1. **`rea` is not a dictation codebase.** It is "REA: Reverse Engineer Anything", a 1.5M-line TypeScript CLI and MCP server for binary and Electron reverse engineering. It contains no audio, hotkey, STT, or text-insertion code. It is not a sensible product base. Its **tool contract + declared side-effects design** is the right template for the agent-execution layer, and it can be plugged in as an optional MCP toolset. Details are in §5.
2. **Wispr Flow** sets the bar: Fn hold-to-talk, double-tap to latch, under 700 ms p99 latency, strong cleanup (fillers, self-corrections, lists), per-app styles, auto-learning dictionary, Command Mode, and Cursor/Windsurf variable recognition. It is cloud-only, closed, about $12–15/mo, with a 2,000-word/week free tier. It has had privacy controversies and outages.
3. **OpenWhispr** is a capable, MIT-licensed, very active Electron app (about 250k lines of `src/`, about 7 commits/day). It has good Fn/Globe handling and good paste code. It **lacks hold + double-tap latch** (PR #2084 is open), **lacks ElevenLabs**, does **local STT batch-only**, and has no coding-agent mode and no undo or paste-last. It also carries a lot of product you don't need: accounts, billing, sync, meetings, iOS.
4. **The latency-optimal stack differs from what any existing app ships:**
   - Streaming cloud STT (ElevenLabs Scribe v2 Realtime) runs in a race with on-device Parakeet on the Apple Neural Engine (via FluidAudio, a Swift library).
   - A skippable fast-LLM cleanup pass follows.
   - All of it sits inside a native Swift menubar app (about 30–80 MB idle versus 750 MB+ for Electron).

## 2. Feature matrix: Wispr Flow vs. OpenWhispr

Legend: ✅ yes · ◐ partial or caveated · ❌ no · — not applicable

### Common to both

| Feature | Wispr Flow | OpenWhispr | Notes |
|---|---|---|---|
| Global hold-to-talk on Fn/Globe (macOS) | ✅ | ✅ | Both suppress the Globe system action. OpenWhispr uses the private `TISUpdateFnUsageType` API. |
| Hands-free / toggle mode | ✅ Fn+Space, or double-tap | ◐ only as a *global* "tap" mode, not combined with hold | |
| LLM cleanup (fillers, punctuation) | ✅ fine-tuned Llama | ✅ any provider, or local llama.cpp | |
| Per-app tone / style | ✅ Styles (4 categories, English only) | ◐ "Tone & Style", off by default | |
| Custom dictionary with auto-learn from corrections | ✅ | ✅ (AX text monitor) | |
| Snippets (voice shortcuts) | ✅ | ✅ | |
| History | ✅ with audio playback | ✅ SQLite | |
| Edit selected text by voice | ✅ Command Mode | ✅ via the Voice Assistant hotkey | |
| Floating recording pill / HUD | ✅ Flow Bar | ✅ | |
| Multilingual + auto-detect | ✅ ~99–100+ | ✅ ~60 | |
| Meeting notes product | ✅ Notetaker (separate) | ✅ built-in, with diarization | |
| MCP server | ✅ notes/meetings only | ✅ notes/transcripts | |
| Mouse-button triggers | ✅ buttons 4–10 | ✅ | |

### Unique to Wispr Flow (or clearly better there)

| Feature | Notes |
|---|---|
| **Hold + double-tap-latch on the same key** (~500 ms window) | This is your requested behavior. OpenWhispr's most-requested missing hotkey feature. |
| Self-correction ("backtrack") handling, cleanup levels None→High | OpenWhispr's prompt does some of this; Wispr has dedicated tuning. |
| Esc cancel with Undo/retry; audio kept on failure for retry | |
| Paste-last-transcript hotkey | OpenWhispr #1704 is open. |
| **Developer features:** Variable Recognition and @file tagging in Cursor/Windsurf | Uses the editors' accessibility tree. |
| Context from text near the cursor feeding name spelling | OpenWhispr only has opt-in screenshots for its *assistant*. |
| Whisper mode (quiet speech) | |
| Measured latency target: under 700 ms p99 | |
| Windows, iOS, Android parity | |

### Unique to OpenWhispr

| Feature | Notes |
|---|---|
| **Fully offline STT and LLM** (whisper.cpp with Metal, Parakeet/Nemotron via sherpa-onnx, llama.cpp) | |
| **Bring-your-own-key** across about 12 STT and about 10 LLM providers, plus a custom OpenAI-compatible endpoint | No ElevenLabs. |
| **MIT source**, Linux support | |
| Agent tools with approval cards (Gmail, Slack, Linear, GitHub), Agent Skills, local CLI bridge | Connectors and agent mode are Pro/paid. Official OAuth secrets only ship in official builds. |
| Translation hotkey | |
| Cost: free locally, $80/yr Pro | |

### Missing from both (needed for your goals)

| Feature | Why it matters to you |
|---|---|
| **Coding-agent restructure mode** (rambling speech → Goal / Context / Constraints / Steps, in Claude Code, Cursor, and terminal agents) | Explicit requirement. Neither has it. |
| **ElevenLabs Scribe** support | You already have keys, and it has the top independent accuracy (2.2% WER on Artificial Analysis). |
| **Cloud-streaming + local race** to cut tail latency | Latency is your top priority. |
| **Spoken tasks routed to local agents** with declared-effects safety gating | Explicit requirement. OpenWhispr's agent is a chat assistant with SaaS connectors, not a local executor. |
| Latency instrumentation and a WER benchmark harness | Needed to prove the targets. |

## 3. Build vs. adopt

**Recommendation: build our own lean native macOS app, using OpenWhispr as a reference and parts donor rather than as a fork base.** Run stock OpenWhispr meanwhile (local Parakeet plus Groq cleanup, signed out) as a free daily driver until our app overtakes it.

Options considered:

| Option | For | Against | Verdict |
|---|---|---|---|
| **A. Use OpenWhispr as-is** | Free, works today, offline | No latch, no coding mode, no agent execution, no ElevenLabs, no Scribe streaming; Electron overhead | Use as the interim tool only |
| **B. Fork OpenWhispr** | About 70% of features exist; MIT; tested decision modules | 250k lines with an untyped 14k-line IPC file; about 7 upstream commits/day to rebase on; heavy build (about 14 native helpers, many sidecars); Electron footprint; local path is batch-only; accounts, billing, and sync to strip out. Each of our core differentiators (streaming race, ElevenLabs, coding mode, agent safety) touches its most coupled files. | Viable but expensive to *own* |
| **C. Fork FluidVoice (Swift, GPL-3)** | Closest native match: Parakeet, command and rewrite modes, screen context | GPL-3 (fine for personal use, constrains licensing later); its local AI enhancement runtime is closed-source; smaller community | Worth studying, not basing on |
| **D. Build a lean Swift app + small agent daemon** ✅ | Latency-first architecture from day one; all needed APIs are native; about 30–80 MB idle; only the features you want; you own and understand all of it | More upfront work: hotkeys, insertion, and settings have to be written. This is mitigated by borrowing proven MIT patterns. | **Recommended** |

Why D wins for your priorities:

- **Latency.** The best path needs streaming STT while the key is held, plus on-device Parakeet on the ANE (FluidAudio is Swift-native), plus parallel racing. Electron adds IPC hops and a separate audio pipeline (MediaRecorder → WebM → IPC → temp file). Native Swift removes all of that.
- **Precision.** Dictionary keyterms flow into Scribe (up to 50 realtime terms / 1,000 batch) and into Parakeet vocabulary boosting. AX context (focused element text, file names in the IDE) feeds both STT and the LLM.
- **The unique features are numerous and sit in the core.** These are the latch state machine, the streaming race, ElevenLabs, the coding-agent mode, and agent execution with safety. With a fork, every one becomes a deep patch on a fast-moving upstream.
- **Borrowing cuts the cost of D.** Copy *patterns* (and MIT code where useful):
  - OpenWhispr: Globe-key suppression with crash-safe restore, promised-pasteboard paste with read-confirmed clipboard restore, typed fallback for Chromium.
  - Handy: Secure-Input fallback, promise pasteboard.
  - Legacy Hex: hotkey timing thresholds.
  - VoiceInk and FluidVoice (GPL): ideas only, no code copied.

If you'd rather take option B to get to daily use faster, the plan below still applies at the module level. Tell me and I'll re-cut it as a fork plan.

## 4. Key technical conclusions feeding the plan

- **Primary STT: ElevenLabs Scribe v2 Realtime over WebSocket.**
  - Open the socket on key-down, stream PCM while held, and send a manual commit on key-up.
  - Independent accuracy is top-tier (2.2% WER); latency is about 150 ms (vendor-claimed). Cost is about $0.39/h plus $0.08/h for keyterms.
  - Its streaming time-to-final is **not independently measured yet**, so it is the first thing to benchmark.
- **Local STT: Parakeet TDT 0.6B v2 (English) via FluidAudio on the ANE.** A community M4 test measured 0.19 s for a clip, versus about 1.0–1.2 s for the best Whisper setups. It also serves as the offline mode. Benchmark candidates: Qwen3-ASR 0.6B/1.7B, Apple SpeechTranscriber (macOS 26; no custom vocabulary), and WhisperKit large-v3-turbo.
- **Race policy:** run both on the same audio. Take cloud if it finalizes within about 350 ms of key-up, otherwise take local. This takes network spikes out of p95.
- **Cleanup LLM:** Groq `gpt-oss-20b` (about 850–1,000 tok/s) or **Claude Haiku 5.5** (`claude-haiku-5-5`, $0.10 / $0.50 per MTok, thinking can be disabled at effort ≤ high). Both are benchmarked.
  - Skip the LLM for short, already-clean utterances.
  - Cache the system prompt and keep connections warm.
  - Offline fallback: Qwen3-4B 4-bit via MLX (about 135 tok/s on an M4 Max). This is acceptable for light cleanup, slow for restructuring.
- **Coding-agent restructure:** a stronger model (Claude Sonnet 5.5 at low effort, or Cerebras `gpt-oss-120b`), with output streamed. Only for long utterances in coding-agent apps.
- **Insertion:**
  - Default: promised pasteboard + synthesized ⌘V, then restore the clipboard after the target app reads it.
  - Chromium: AX "Edit › Paste" menu press, or typed text.
  - Native Cocoa fields: optional AX `kAXSelectedTextAttribute` set.
  - Never type a trailing newline into terminals.
- **Hotkey:** an active `CGEventTap` on a dedicated thread (re-enabled on timeout), watching `flagsChanged` for Fn (63), Right ⌥ (61), and Right ⌘ (54). Modifier-only keys keep working under Secure Keyboard Entry.
- **Distribution:** Developer ID + Hardened Runtime + notarization, outside the App Store. Use a **stable signing identity even for dev builds**, or TCC permissions reset on every rebuild.

## 5. `rea` review summary (full report: [01-rea-review.md](01-rea-review.md))

**What it is:**
- `rea-agents` v6.8.0, MIT, Node 24.
- About 170 MCP tools wrapping Hopper, Ghidra, IDA, rizin, LLDB, Frida, Playwright/CDP, and format parsers.
- Clean inward-flowing layers: domain/contracts → providers → application → CLI/MCP adapters.
- Very strict TypeScript (29 `any`, zero `@ts-ignore` in `src/`), `Result`-typed errors, rigorous process-ownership cleanup.
- Vitest lanes with coverage thresholds, plus Stryker mutation testing.

**Concerns:**
- Extreme churn: 5,442 commits in October 2026 and three majors in two days, largely agent-authored.
- 740 MB `node_modules`.
- Several files of 2–3.3k lines.
- CI is almost entirely Ubuntu.

**Reusable for this project:**

| Asset | Use |
|---|---|
| `src/contracts/toolContractTypes.ts` + `toolEffects.ts` (each tool declares its side effects; MCP hints are derived) | **Template for the agent layer's safety model.** |
| `bridge/native/ReaNativeUI.swift` | Reference for AX tree walking and permission-error UX. It is not directly usable: it targets a chosen window and replaces the whole field. |
| `rea mcp` with `REA_MCP_TOOL_FAMILIES` | Optional plugin toolset for the agent backend ("analyze this binary"). |
| Electron analysis tools | Can study *open-source* apps such as OpenWhispr. **Do not** use it on Wispr Flow: proprietary, ToS, and rea's own DISCLAIMER. |

**Suggested improvements to rea:**

1. Cache compiled Swift helpers by source hash instead of running `swiftc` on every call.
2. Make the native UI helper a long-lived process.
3. Add an insert-at-cursor text action (AX selected-text set + paste fallback) beside the whole-field set-value.
4. Split the 2–3.3k-line files along their existing seams.
5. Make Stryker fail the build on regression (`thresholds.break` is currently `null`).
6. Slim the install: optional provider deps, a lazy Playwright download.
7. Add an opt-in **runtime approval hook** driven by the effects metadata (today, confirmation is entirely left to the MCP client).
8. Add macOS CI lanes for the native bridge.
9. Slow the release cadence or add an LTS channel so downstream users can pin.

**How "build on rea" maps into the plan:**
- The new app lives beside rea in `voice-flow/`.
- Its agent daemon reuses rea's contract/effects *design* and can mount rea as an MCP toolset.
- The improvements above can go upstream as PRs.

If you meant a different repo, tell me.
