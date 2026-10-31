# 01 — Review of `morluto/rea` as a base for a local voice-to-action tool

Reviewed: `/Users/mle/Documents/MLEngineering/Agentic_2026/rea` at commit `69bf61f` (latest commit 2026-10-30, `fix(browser): preserve event coverage for failed requests (#8158)`). This was a read-only review: nothing was installed, built, or run. All numbers come from `git ls-files`, `wc`, `grep` and `git log`.

**Short answer:** rea is a large, carefully engineered **reverse-engineering** CLI and MCP server. It contains **no voice, audio, hotkey, STT, LLM-cleanup, or text-insertion code**. It should not be the product base. At most it is an optional MCP tool server that the agent layer can call, and a research tool for studying open-source Electron dictation apps. A few small pieces are worth reading as reference: the Swift Accessibility helper, the process-ownership and lifecycle design, and the tool-effects metadata.

---

## 1. What rea is

**"REA: Reverse Engineer Anything"** is npm package `rea-agents` v6.8.0, MIT license, binaries `rea` / `rea-agents` dispatched by `scripts/rea.mjs`. One set of shared application workflows sits behind two adapters:

- **CLI**: `src/cli.ts`, `src/cli/`. One-shot commands such as `rea inspect-electron-page …`.
- **MCP server**: `src/main.ts`, `src/main/`, `src/server/`. Uses stdio by default; streamable HTTP is opt-in (`src/server/http/serveStreamableHttp.ts`).

It drives or wraps analysis engines: Hopper (`bridge/hopper_bridge.py`), Ghidra (`bridge/ghidra/*.java`), IDA (through ida-pro-mcp), Cutter/rizin, GDB/pwndbg/LLDB, Frida (optional dependency), JADX/apktool/adb for Android, Playwright/CDP for browser and Electron, and many format parsers (Mach-O/ELF/PE, WASM, EVM, IL2CPP, Go, Rust, Flutter, pcap, SQLite, firmware). Every result is returned as a provenance-tracked **Evidence** record (`structuredContent.normalized_result`, `evidence_id`), with the agent's token budget treated as a main design goal (`AGENTS.md` § Performance).

### Top-level layout

| Path | Contents |
|---|---|
| `src/` | 3,443 files, ~922k LOC TypeScript (82 top-level entries, one directory per provider/format plus `domain/`, `application/`, `contracts/`, `composition/`, `server/`, `cli/`, `process/`) |
| `bridge/` | 35 files of in-engine scripts and native helpers: Hopper/Cutter Python, Ghidra/JADX/NativeAOT Java, pwntools/pwndbg/mitmproxy Python, and **3 Swift files** (`bridge/native/ReaNativeUI*.swift`, `bridge/process/ProcessRunTokenReader*.swift`, 661 LOC in total) |
| `native/` | Only `native/windows/` (a C++ Node addon for Job Objects, handles and process control). **No macOS native module.** |
| `tests/` | 2,288 files, ~555k LOC TS: `acceptance/`, `boundary/`, `composition/`, `conformance/` (includes Swift/ObjC fixtures), `evaluation/`, `process-global/`, `fixtures/` |
| `scripts/` | 530 files, ~92k LOC: build, `verify:*` real-provider checks, catalog and docs generators |
| `website/`, `docs/` | VitePress site plus 100+ markdown references (e.g. `docs/mcp-contracts.md` is 1,720 lines) |
| `.agents/skills/`, `.claude-plugin/`, `.codex-plugin/` | Agent skill and plugin packaging |

**LOC by language (git-tracked):** TypeScript about 1.48M (src about 922k, tests about 555k), `.mjs` about 94k, Python about 17.5k, Java about 10k, C about 1k, Swift about 1.7k (mostly test fixtures), ObjC about 100.

### Layering and composition

`docs/architecture.mermaid` and `AGENTS.md` § Architecture describe the rule: dependencies flow inward. The order is **domain semantics/contracts → provider adapters → shared application workflows → CLI/MCP adapters**. `src/composition/` (about 40 factory modules such as `binary.ts`, `electronScenario.ts`, `desktop.ts`) builds typed provider and session objects. `AnalysisProviderRegistry` and `SessionProviderRouter` bind exactly one deep provider to each target, chosen deterministically with no silent fallback. Expected failures use a tagged error algebra plus `Result` (`src/domain/result.ts`, `src/domain/analysisError*.ts`).

### How MCP tools are registered and contracted

- **Single source of truth per tool**: `ToolContract` in `src/contracts/toolContractTypes.ts`. It holds `name`, `title`, `description`, `kind`, zod `inputSchema`/`outputSchema`, `effects`, derived `annotations`, `returnsTargetContent` (which marks results as untrusted target text), and validated `examples`.
- **Effects audit**: `src/contracts/toolEffects.ts` lists `TOOL_EFFECTS` explicitly for every public tool (about 120 entries). The flags are `mutatesTarget`, `mutatesSession`, `writesFilesystem`, `launchesProcess`, `accessesNetwork`, `changesUiState`, `mayDiscardData`, `executesForeignCode`, `mutatesDevice` and `idempotent`. MCP `readOnlyHint`/`destructiveHint`/`idempotentHint`/`openWorldHint` are derived from these flags and never written by hand.
- **Registration**: there are 114 files in `src/server/` (`register*Tools.ts`), and about 170 distinct `toolContract("…")` bindings. The usual pattern is in `src/server/registerDesktopApplicationTool.ts`: `toolContract(name)` → `createContractToolHandler` / `createRetainedSummaryToolHandler` (`src/server/contractToolHandler.ts`) → `server.registerTool(contract.name, options, handler)`. The shared handler runs log → admit → execute → record Evidence → deliver.
- **Contract doc** (`docs/mcp-contracts.md`): Evidence delivery, retained summaries plus paging (`inspect_analysis_view`), progress and cancellation with partial-result retention, transports, and schema advertising. Advertised JSON Schemas are validated against real clients. `REA_MCP_TOOL_FAMILIES` limits which tool families are advertised, to cut schema-token cost.
- **Permissions stance** (`docs/mcp-contracts.md` § "Request scope and local effects"): *"REA does not require permission grants or per-call approval flags … MCP clients control their own confirmation UI."* Annotations are hints, not authorization. The only interactive approval is `rea setup` (`src/cli/interactiveSetup.ts`, using `@clack/prompts` `confirm`).

### AGENTS.md conventions (worth copying)

`AGENTS.md` asks for these conventions:

- Fail closed when scope or authority is unclear.
- Additive, idempotent config changes with backups.
- Installers must never install unrelated software.
- Keep observations, inferences and unknowns separate ("unknown ≠ absent").
- Normalize once at the owning boundary.
- Reuse the `src/process/` ownership primitives ("a PID and path alone do not establish ownership").
- Explain any speculative security complexity to the user before adding it.
- Conventional Commits.
- Every AI-assisted PR needs a human owner.

### Dependencies, toolchain, release cadence

- **Node**: `engines` `^22.23.4 || ^24.22.1 || >=26.12.1`; `.nvmrc` = `24.22.1`; ESM (`"type": "module"`).
- **Runtime dependencies (43, exact pins)**: `@modelcontextprotocol/server` and `client` 2.3.1, `zod` 4, `pino`, `playwright-core`, `@lydell/node-pty`, `@xterm/headless`, `@electron/asar`, `@babel/parser`, `isomorphic-git`, `openpgp`, `ws`, `ajv`, `plist`, `cross-spawn`, and others. Optional: `frida`. `node_modules` is **740 MB** and `dist/` is **54 MB**.
- **Dev tooling**: TypeScript (plus `typescript6` and `tsrs`), oxlint (with `oxlint-tsgolint` type-aware rules), oxfmt, knip (dead code), jscpd (duplication), husky with lint-staged, turbo (task caching), rolldown, release-please, vitest with `@fast-check/vitest` (property tests), Stryker.
- **History**: 6,261 commits. The first commit is dated 2026-04-14, but 5,442 commits landed in **October 2026 alone** (about 175 per day). There are 40 tags; majors went 4.1.0 → 5.0.0 → 6.0.0 between 2026-10-07 and 2026-10-08, and 6.1 → 6.8 followed in about two weeks. `CHANGELOG.md` is 461 KB. Contributors are morluto (3,817 commits) plus about 4 regular others. Commit trailers show heavy AI-agent authorship: about 1,400 `Co-Authored-By: Claude …`, about 120 Cursor Agent, and about 60 factory-droid.

### Test infrastructure and CI

- **Vitest** (`vitest.config.ts`): multi-project lanes (`domain`, `services`, `adapters`, `composition`, `boundary`, `cli-boundary`, plus built-artifact projects from `scripts/lib/test-projects.mjs`) with a custom `CiTestSequencer`. Workers are capped at 2. Coverage uses v8 with thresholds: global 65/60/60/68 (stmts/branches/fns/lines), `src/domain/**` 80/75/75/80, `src/contracts/**` 85/80/80/85. Extra configs: `vitest.reverse-tools.config.ts` and `vitest.reverse-tools-semantics.config.ts`.
- There are 1,118 co-located `src/**/*.test.ts` files and 1,763 `tests/**/*.test.ts` files, for about 2,325 non-test source files.
- **Stryker** (`stryker.config.mjs`, `stryker.semantics.config.mjs`): mutation testing is aimed at specific *methods* (e.g. `ReverseEngineeringService.inspectWithObjdump`, `executeRizinCommand`) through `mutationRanges(...)`, with the TypeScript checker and per-test coverage. `thresholds.break: null` means it reports but never fails the build. A `mutation.yml` workflow runs it.
- **CI**: 34 workflows in `.github/workflows/`. These include `ci.yml`, `ci-full-pr.yml`, `pr-readiness.yml` and `pr-title.yml`, plus about 20 `real-*.yml` jobs that run against real providers (Hopper on self-hosted macOS/Linux runners, Ghidra on a self-hosted Windows runner, browser, Termux, Android, and others). Runners are mostly `ubuntu-latest` and `ubuntu-24.04`, with one `macos-15`, Windows runners, and self-hosted machines.

---

## 2. Quality assessment

**Strengths**

- **Typing is very strict.** `tsconfig.json` sets `strict`, `exactOptionalPropertyTypes`, `noUncheckedIndexedAccess`, `noImplicitOverride`, `noImplicitReturns` and `verbatimModuleSyntax`. In about 922k LOC of src there are only 29 `any` matches, **0** `@ts-ignore`/`@ts-expect-error`, and 5 lint-disable comments.
- **Errors are explicit values.** About 2,700 `err(...)` Result returns sit next to about 2,750 `throw new` (mostly typed `AnalysisError` subclasses). Cancellation keeps partial observations (`src/server/externalMutationAdmission.ts`: `retainExternalMutationCancellation`). Failure codes are stable and actionable; the Swift helper's codes include `accessibility-denied` and `screen-recording-denied`, with System Settings instructions.
- **Contracts are single-sourced.** Schemas, effects, annotations, examples and the docs catalog all come from one `ToolContract`. Catalogs, docs and the error schema are generated and then checked in CI (`docs:check`, `mcp-catalog:check`, `metadata:check`).
- **Lifecycle and process ownership are rigorous.** `src/process/ProcessOwnership.ts` (1,915 LOC) has about 15 targeted test files: identity, lineage, run-id, final sweep, PID reuse. Leases (`OwnedLease.ts`, `AnalysisCleanupLease`) and bounded output (`ExecFileBoundedOutput.ts`, `BoundedControlLines.ts`) are used consistently. Linux cgroup and rlimit helpers are included.
- **Hygiene tooling** goes well beyond the norm: knip, jscpd, todo scanning, architecture-guard and module-boundary verifiers (`verify:architecture-guards`, `verify:module-boundaries`), and test-temp hygiene checks.
- **Docs** are extensive and precise about limits; for example, `docs/process-capture.md` states plainly "This is not a sandbox."

**Weaknesses and risks**

- **Scale versus team.** About 1.5M LOC of TS, 170 tools and 82 src subsystems, maintained by about 5 humans at about 175 commits a day with heavy AI co-authorship. The architecture rules are sound, but the volume is hard for humans to review. The churn (three major versions in two days) makes it a risky upstream to build on.
- **Some files are very large**: `src/adb/AdbProvider.ts` (3,306 LOC), `src/gdb/GdbSessionManager.ts` (2,445), `src/domain/javascript/javascriptSemanticMemberMutations.ts` (2,378), `src/native/NativeMacOSProvider.ts` (2,094), `src/process/ProcessOwnership.ts` (1,915). They go against the repo's own "clear owner" guidance and are hard to mutation-test.
- **Docs are dense and legalistic.** Paragraphs in `docs/mcp-contracts.md` and `AGENTS.md` are exact but hard for newcomers to follow; the docs need a separate quick-start layer.
- **Mutation testing never fails the build** (`thresholds.break: null`) and covers only a few reverse-tool methods.
- **Coverage thresholds are modest globally** (65% statements). The high test count partly reflects a style of many narrow regression files, e.g. `ProcessOwnership.part2.test.ts` / `part3.test.ts`.
- **Very heavy footprint for any consumer**: 740 MB of `node_modules`, Playwright, node-pty native builds, and a pinned recent Node version.

---

## 3. What is reusable for voice-to-action

| Candidate | Location | Reuse value |
|---|---|---|
| **macOS Accessibility and ScreenCaptureKit helper** | `bridge/native/ReaNativeUI.swift` (176 LOC) + `NativeUIChildren.swift`, `NativeUIValues.swift`; driven by `src/native/NativeUiHelperRuntime.ts`, `NativeUiObservation.ts` | **Moderate, as a reference.** It shows `AXIsProcessTrusted`, `AXUIElementCreateApplication`, `AXUIElementSetMessagingTimeout`, AX tree walking with node and depth budgets, `AXUIElementPerformAction(kAXPressAction)`, **setting `kAXValueAttribute` for text entry**, `CGPreflightScreenCaptureAccess`, and `SCScreenshotManager` window capture. It also verifies target identity (PID + launch time + executable SHA-256) before acting. But it targets a caller-selected window, not the **focused element**: there is no `kAXFocusedUIElementAttribute`, no `kAXSelectedTextRange`, no `CGEventPost` and no pasteboard. Setting `AXValue` replaces the whole field, which is the wrong behavior for dictation. It is a one-shot CLI process compiled with `swiftc` on every observation (see §5). Use it as reading material; a voice app needs its own resident Swift/AppKit process. |
| **Process run-token and identity reader** | `bridge/process/ProcessRunTokenReader.swift` (397 LOC, `sysctl KERN_PROC_ALL`), `src/process/*` | **Low to moderate.** Useful if the agent layer spawns long-running shell or agent jobs and must reliably kill their whole process trees. The concepts (owned leases, deadline signals, bounded output, PID-reuse-safe identity) are worth copying; the code is too entangled with Evidence and sessions to lift directly. |
| **Process capture (PTY)** | `src/process/capture/*`, tool `capture_process_scenario` | **Low.** It runs a command in a PTY with `@lydell/node-pty` + `@xterm/headless` and records terminal output and filesystem effects. That could show what an agent's shell command did, but per its own docs it is **not a sandbox**. |
| **MCP server scaffolding** | `src/server/createServer.ts` (1,245 LOC), `contractToolHandler.ts`, `toolContractTypes.ts`, `toolEffects.ts`, `src/server/http/*` | **Patterns, not code.** The `ToolContract` + `ToolEffects` → derived annotations design is a good template for the voice tool's own "backend action" MCP server. Every action would declare `launchesProcess`, `writesFilesystem`, `accessesNetwork`, `changesUiState`, `mayDiscardData`, and the UI would use those flags to decide when to ask for confirmation. Reimplement it in about 200 LOC on `@modelcontextprotocol/server` rather than forking rea's EvidenceMcpServer, which is tied to binary sessions. |
| **Safety and confirmation patterns** | `src/cli/interactiveSetup.ts`, `src/server/externalMutationAdmission.ts`, `AGENTS.md` | **Conceptual only.** rea deliberately has **no runtime permission or approval layer**; it leaves that to the MCP client. The voice product must build its own: preview spoken intent → confirm → execute, with an allow-list per effect class. Copy the "show plan, require approval before writing" setup pattern and the effect taxonomy. |
| **Electron and JS analysis** | `inspect_electron_fuses`, `list_electron_targets`, `inspect_electron_page`, `capture_electron_scenario`, `analyze_javascript_application` (ASAR/directory static analysis, no code execution); docs `docs/electron-observation.md`, `docs/electron-fuses.md`, `docs/javascript-application-*.md`, `docs/desktop-applications.md` | **Useful as a research tool.** `analyze_javascript_application` on an *open-source* app (e.g. OpenWhispr's ASAR or source) can map its modules, IPC routes and native-module handoffs, including how it does hotkeys, audio capture and paste. `inspect_desktop_application` triages a `.app` directory. |

**Legal note:** Wispr Flow is proprietary. Its EULA/ToS almost certainly forbids reverse engineering, decompiling and derivative works, and rea's own `DISCLAIMER.md` disclaims "copying proprietary software or reproducing its protected code and assets". Interoperability exceptions are narrow and depend on jurisdiction. Recommendation: **do not** decompile or copy from Wispr Flow. Study it only through public, observable behavior (UX, docs, marketing) and do a clean-room design. For OpenWhispr and other OSS apps, just read the source; rea adds little over `git clone` + grep, except perhaps fast dependency and route mapping. Follow those projects' licenses (check whether any are copyleft before copying code).

---

## 4. What is missing for the voice product (everything core)

rea has **no matches** for whisper, microphone, AVAudio, CoreAudio, speech, CGEventTap/CGEventPost, NSPasteboard, pbcopy or RegisterEventHotKey anywhere in `src/` or `bridge/`. To be built (or taken from other projects):

1. **Global push-to-talk hotkey**: hold-to-talk and toggle modes, including modifier-only keys (Fn/Globe, right-⌥). Needs a `CGEventTap` (Input Monitoring permission) or `NSEvent.addGlobalMonitorForEvents`; Fn handling needs `flagsChanged`.
2. **Audio capture**: AVAudioEngine/AVCaptureDevice at 16 kHz mono, device selection, VAD/silence trimming, a pre-roll buffer, a level meter, and Microphone permission (`NSMicrophoneUsageDescription`).
3. **Local STT**: whisper.cpp (Metal/Core ML), WhisperKit, Parakeet/MLX, or Apple `SpeechAnalyzer`/`SFSpeechRecognizer`. Plus model download and management, streaming or partial results, and a custom vocabulary or prompt.
4. **LLM cleanup**: a local LLM (llama.cpp/MLX/Ollama) or an optional API. Removes filler words, fixes punctuation and self-corrections, applies per-app tone and formatting (e.g. code vs Slack vs email), a personal dictionary, and snippets. Needs a latency budget of roughly 1 s or less end to end.
5. **Text insertion into the focused app**: read `kAXFocusedUIElement`, then either (a) pasteboard swap + synthesized ⌘V via `CGEventPost` with clipboard restore, (b) AX `kAXSelectedTextAttribute` insertion, or (c) `CGEventKeyboardSetUnicodeString` typing as a fallback. Needs per-app quirks (Electron, terminals, secure input fields) and the Accessibility permission. rea's `key-entry` (whole-value replacement on a pre-selected window) is not enough.
6. **Context capture** (optional): app bundle ID, selected text, and window title, used for tone and formatting.
7. **Intent routing**: classify "dictation" vs "command/task". For tasks, call backend agents (Claude Agent SDK / MCP clients) with tool allow-lists, a confirmation UI, cancellation, logs and undo where possible.
8. **Menubar UI**: an `NSStatusItem` app (SwiftUI/AppKit, or Tauri/Electron), a recording HUD overlay, history, settings, and per-app rules.
9. **Permissions onboarding**: Microphone, Accessibility, Input Monitoring, optionally Screen Recording and Automation (AppleEvents). Includes deep links to System Settings panes, re-check loops, and a signed and notarized app with a stable bundle ID so TCC grants persist.
10. **Packaging**: code signing, notarization, launch at login, auto-update (Sparkle), crash and telemetry opt-in.

---

## 5. Improvement suggestions for rea itself

1. **Cache the compiled Swift helpers.** `src/native/NativeUiHelperRuntime.ts` builds `ReaNativeUI.swift` with `xcrun swiftc` in a fresh temp dir for every observation or scenario, and process-ownership inspection does the same. Compile once per (helper source digest, swiftc version, arch) into the existing private runtime root, or ship prebuilt universal binaries in the npm package. This removes seconds of cold latency per call and the hard dependency on Xcode CLT at runtime.
2. **Make the native UI helper resident.** A long-lived helper speaking NDJSON over stdio (the repo already has `DecodedNdjsonLineBuffer.ts`) would avoid relaunching it and rechecking TCC on every call, and would allow AX observers (`AXObserverCreate`) for event-driven UI tracing instead of polling snapshots.
3. **Fix text entry semantics in `ReaNativeUI.swift`.** `key-entry` replaces the whole `kAXValueAttribute`. Add an insert-at-selection mode (`kAXSelectedTextRangeAttribute` + `kAXSelectedTextAttribute`) and report when the AX value is not settable, rather than only returning `action-failed`.
4. **Split the monolith files** (`AdbProvider.ts`, `GdbSessionManager.ts`, `NativeMacOSProvider.ts`, `ProcessOwnership.ts`) along their existing owner seams (discovery, transport, lifecycle, projection), so each fits a focused mutation target. Merge `ProcessOwnership.part2/part3.test.ts` into named behavior files.
5. **Make mutation testing gate something.** Set a `thresholds.break` for the targeted reverse-tool methods and add `src/process/ProcessOwnership*` and `src/domain/result`/error projection to the mutate set, because these are the most safety-critical invariants.
6. **Package and footprint.** Move Playwright, node-pty, isomorphic-git, openpgp and similar to lazily loaded optional providers or sub-packages (e.g. `@rea/browser`, `@rea/android`) so that an MCP consumer wanting a few tools doesn't pull 740 MB. `REA_MCP_TOOL_FAMILIES` already trims schemas; trim installs too.
7. **Add an opt-in approval hook.** The "MCP clients control confirmation" stance is defensible, but many clients auto-approve. An optional server-side policy (e.g. `REA_REQUIRE_CONFIRM=executesForeignCode,mayDiscardData` using MCP elicitation) would reuse the existing `ToolEffects` data at little cost.
8. **Control the churn.** Three major versions in two days and about 175 commits a day are hard on downstream users. Consider batching releases weekly, keeping a stable LTS line, and publishing a short human-written "what changed for integrators" note next to the 461 KB generated changelog.
9. **Docs layering.** Add a one-page "concepts in 5 minutes" (Evidence, retained summary, session, effects) before the 1,700-line `docs/mcp-contracts.md`, and a contributor-oriented layer diagram that is simpler than `docs/architecture.mermaid`.
10. **Expand macOS CI.** Only one `macos-15` hosted job plus a self-hosted Hopper runner exist, while about 52 jobs run on Ubuntu. The Swift helpers (`verify:native-ui`, `verify:native-ui:permissions`) need a regular macOS lane, including a TCC-denied path test.

---

## 6. Verdict

**rea is unrelated as a product base. It is optional as a component and occasionally useful as a research tool.**

- **Not the base.** It shares none of the voice product's core: no audio, hotkeys, STT, LLM text cleanup, focused-element insertion, menubar UI or TCC onboarding. Its runtime (Node 24, 740 MB of dependencies, Evidence/session model for binary analysis) is the wrong shape for a low-latency resident macOS app, which should be Swift/AppKit (or Tauri/Electron with a Swift helper) around whisper.cpp/WhisperKit and a local LLM. Forking it would mean deleting about 99% of it and inheriting a very fast-moving, AI-generated upstream.
- **Optional component.** The voice app's agent layer can register `rea mcp` as **one of many MCP servers**, scoped with `REA_MCP_TOOL_FAMILIES`, for spoken tasks like "analyze this binary" or "what does this Electron app's preload do". That is a niche capability for most users, so it should be an opt-in plugin and not a dependency.
- **Patterns to copy, not code.** Copy the `ToolContract` + `ToolEffects` → derived annotations design (to drive the voice app's confirm-before-execute UI), the process-ownership and lifecycle invariants for supervising agent subprocesses, the fail-closed and "unknown ≠ absent" conventions in `AGENTS.md`, and the Accessibility/TCC error-reporting style in `bridge/native/ReaNativeUI.swift`.
- **Research tool, with limits.** `analyze_javascript_application` and `inspect_desktop_application` can map open-source Electron dictation apps such as OpenWhispr quickly. Do not use it to decompile proprietary Wispr Flow; use clean-room design from public behavior instead.

**Next step for voice-flow:** start from an OSS dictation codebase (e.g. OpenWhispr, VoiceInk, or a WhisperKit/whisper.cpp menubar app) as the product base. Build a small, purpose-built MCP "actions" server modeled on rea's contract and effects pattern.
