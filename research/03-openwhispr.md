# OpenWhispr: deep-dive for adopt/fork decision (macOS, local Wispr Flow alternative)

Researched 2026-10-30. Sources: https://openwhispr.com/, https://openwhispr.com/pricing, https://github.com/OpenWhispr/openwhispr (README, CHANGELOG, releases and issues via `gh`), and a read-only shallow clone (`--depth 200`, HEAD `b9e9ebef`, 2026-10-29, v1.11.0) at
`/private/tmp/claude-501/-Users-mle-Documents-MLEngineering-Agentic-2026/8b038a3a-5d77-40cb-b632-43bb681be5a7/scratchpad/openwhispr-src/repo`. File paths below are relative to that clone. Nothing was installed, built or run.

---

## TL;DR

- **What it is:** a large, fast-moving **Electron 43 + React 19 + TypeScript** desktop app (plus an Expo iOS app in the same repo). It does dictation into any app, cleanup with an LLM, a voice assistant/agent with tools, meeting transcription with diarization, notes, and team workspaces. It is **MIT**-licensed and has **10.4k stars and 1.3k forks**. The app has shipped **84 releases** since 2025-07-24, and there were **200 commits in October 2026 alone**.
- **Local-first is real but not the default.** It bundles whisper.cpp (Metal/CUDA/Vulkan), sherpa-onnx (Parakeet/Nemotron/Cohere/"Orukeet"), and llama.cpp `llama-server` for local cleanup with GGUF models. It also accepts any OpenAI-compatible custom endpoint (Ollama, LM Studio). However, **OpenWhispr Cloud is the default after onboarding** (`docs/network-allowlist.md`), so you have to pick local during setup.
- **macOS hotkeys:** a native Swift helper (`resources/macos-globe-listener.swift`) gives first-class **Globe/Fn** support and makes it the default dictation key on macOS. It also handles right-side modifiers and mouse buttons. Activation is **one global mode: Tap (toggle) OR Hold (push-to-talk)**. **No hybrid hold + double-tap latch** has shipped. That is the most-requested hotkey feature (#1860, #356, #362, #2238). One community PR, #2084 ("Both" mode, 400 ms threshold), has been open since 2026-09-09 without review. A more ambitious PR, #1978, was closed unmerged on 2026-10-27.
- **Pasting** is very carefully engineered. A Swift helper (`resources/macos-fast-paste.swift`) posts ⌘V through CGEvent and puts a "promised" pasteboard item on the clipboard. The old clipboard is restored only after the target app actually reads the transcript. Chromium browsers get typed unicode instead of ⌘V. AppleScript is the fallback.
- **Forkability: feasible but heavy.** Code quality and test coverage are good: 963 test files, pure "policy" modules, and a 1,071-line `CLAUDE.md` written for AI coding agents. But it is huge (≈140k lines of TS/TSX plus ≈108k lines of JS in `src/` alone, `ipcHandlers.js` is 14.3k lines, `audioManager.js` 6.7k). It is a product with accounts, billing, sync, enterprise SSO and connectors, and upstream changes daily. A fork that adds a double-tap latch or a coding-agent mode is quite doable. Keeping that fork rebased on upstream will be the real cost.

---

## 1. Features

### 1.1 Hotkeys
- **Named slots:** `dictation`, `voiceAgent` (voice assistant), `translation`, `meeting` (`src/helpers/hotkeyManager.js`; CLAUDE.md §"hotkeyManager.js").
- **Defaults:** `GLOBE` on macOS and `Control+Super` on Windows/Linux, with automatic fallback to F8/F9 (`hotkeyManager.js:117`, `:1336`).
- **Activation mode:** `"tap" | "push"`. It is a single setting (`src/stores/settingsStore.ts:1755`, default `tap`; onboarding switches it to `push` when the hotkey supports it, `src/components/OnboardingFlow.tsx:467`). Only the **dictation** slot honours push; the voice-agent hotkey is tap-to-toggle only (CLAUDE.md §17).
- **Hold logic on macOS** (`main.js:1546-1660`):
  - `MIN_HOLD_DURATION_MS = 150` before recording starts, and a 300 ms post-stop cooldown.
  - Releasing before 150 ms cancels preparation.
  - Fn + another key interrupts and cancels the hold (`FN_INTERRUPTED`), so Fn shortcuts don't record noise.
- **Keys that can Hold on macOS** (`lacksMacReleaseSignal`, `hotkeyManager.js:84`):
  - Globe/Fn, right-side modifiers (RightCommand/Option/Control/Shift), mouse buttons, and modifier chords.
  - A lone regular key goes through Electron `globalShortcut`, which never reports key-up, so it can only Tap.
  - `Fn+X` combos are rejected (`hotkeyManager.js:750`).
  - Modifier-only chords such as ⌥⌘ are not supported (open issue #2669).
- **Globe key system action:** macOS fires the emoji/input-switch/dictation action from WindowServer, so it can't be consumed. The helper temporarily sets `AppleFnUsageType` to "Do Nothing" via the private `TISUpdateFnUsageType` and restores it later (`macos-globe-listener.swift:55-80`).
- **Missing:**
  - Hybrid tap-latch/hold on the same key: #1860 "working on it"; PR #2084 open.
  - Double-tap hotkeys: #362, #2238.
  - Cancel during push-to-talk: #1400 (Windows).
  - "Paste last transcription" hotkey: #1704.
  - Separate raw vs. cleaned hotkeys: #2407.

### 1.2 Cleanup / LLM post-processing ("reasoning")
- **Routing:** a finished dictation takes one of three routes, `agent | cleanup | skip` (`src/helpers/dictationRouting.js`). The cleanup prompt wraps input in `<transcript>` tags (`src/config/prompts/index.ts:32`).
- **Providers:** OpenAI (Responses API), Anthropic (called from the main process over IPC), Gemini, Groq, Tinfoil, Corti, OpenRouter (through Cloud tiers), Bedrock/Azure/Vertex for enterprise, **local GGUF through llama.cpp `llama-server`** (Qwen 3.x, Gemma 4, Llama 3.x, Mistral, gpt-oss-20b, LFM), and a **"custom"/self-hosted OpenAI-compatible endpoint** (`src/helpers/providerConnectionTest.js:190`).
  - The registry is in `src/models/modelRegistryData.json`.
  - The vercel `ai` SDK packages are dependencies (`package.json`).
- **Tone & Style:** cleanup adapts its tone to the category of the target app (personal / work / email / other). The app is detected through accessibility (bundle id, window title, browser host) by `resources/macos-text-monitor.swift --app-context` and classified by `src/helpers/toneAppCategories.js`. It is **off by default** (CLAUDE.md §20). This is the closest thing to Wispr-Flow-style app-aware context.
- **Known rough edges:**
  - Silent cleanup failures (#1003).
  - Anthropic 5.5 cleanup is truncated (#3007).
  - Model prompt leakage: #2108, and #2734 (fixed).

### 1.3 Voice assistant / agent / command mode
- **How it's invoked:** a dedicated Voice Assistant hotkey with no wake word, or the "Hey <AgentName>" wake phrase inside normal dictation (CLAUDE.md §7, §17).
- **Selection editing:** highlighted text plus a spoken command gets edited in place ("make this formal"). A question about the selection goes to the assistant panel instead.
- **Standalone commands:** these stream into a floating panel. The answer is pasted at the caret if a writable caret was verified when the recording started; otherwise it is copied to the clipboard.
- **Tools:**
  - Notes search/create/update, calendar, web search, clipboard, snippets/dictionary edits, RAG memory.
  - **Skills** in Agent Skills format (`SKILL.md`, `src/helpers/skills/`).
  - Connectors with approval cards: Gmail send, Slack, Linear, GitHub issues and PRs (`src/helpers/connectors/`).
  - Connectors and agent mode are **paid features** according to the pricing page.
- **Screen context:** opt-in. It attaches a screenshot of the cursor's display (needs Screen Recording permission; `src/helpers/screenContextCapture.js`).
- **Public API & MCP server** for notes and transcriptions. There is also a local CLI bridge on 127.0.0.1:8200-8219 with a bearer token (`cliBridge.js`), which can transcribe a file path with the local model. That bridge is a useful hook for agent routing.

### 1.4 Dictionary, snippets, history
- **Custom dictionary:** passed to Whisper as the `prompt` and injected into the cleanup/agent prompts (CLAUDE.md §13).
  - **Auto-learn** from your corrections is on by default (`ipcHandlers.js:726`). It uses the AX text monitor to watch edits after a paste.
  - Business/Enterprise get a shared team dictionary (1.11.0).
  - Bugs: dictionary echo or hallucination on silence (#851, #1636); the dictionary skews language detection (#2628).
- **Snippets:** spoken trigger → replacement text (`src/utils/snippets.ts`; 100-character trigger cap).
- **History:** SQLite (`better-sqlite3`) table `transcriptions` with original and processed text (CLAUDE.md §4). There are also Insights/word-count stats.

### 1.5 Meetings
Auto-detects Zoom/Teams/FaceTime through process and mic listeners (`resources/macos-mic-listener.swift`). It captures system audio with a Core Audio tap (`resources/macos-audio-tap.swift`), runs local diarization with pyannote segmentation plus 3D-Speaker embeddings via ONNX, and does voice fingerprinting. It has optional WebRTC AEC3 echo cancellation, Google/Microsoft/Apple calendar integration, and note templates/actions. Granola-like. Free tier: 5 h/month of meeting recording.

### 1.6 Languages
60 languages are in `src/config/languageRegistry.json` (59 Whisper, 26 Parakeet, 7 AssemblyAI), plus auto-detect. The website claims "100+". There is also a dedicated **translation hotkey** (dictate in one language, paste in another). The UI is fully i18n'd (`src/locales`).

---

## 2. Architecture

| Layer | Implementation (evidence) |
|---|---|
| Shell | Electron 43 (`package.json` devDeps `electron ^43.8.3`; README still says 41). Context isolation, `preload.js` bridge, a main process (`main.js`, 2,215 lines) and an ONNX utility process (`src/workers/onnxWorker.js`) |
| UI | React 19, Vite 8, Tailwind 4, shadcn/Radix, TipTap for notes. Two windows: an always-on-top dictation "pill" overlay and a control panel (CLAUDE.md "Dual Window Architecture") |
| Main-process logic | Plain **CommonJS JS** in `src/helpers/` (e.g. `ipcHandlers.js` 14,297 lines, `audioManager.js` 6,697, `clipboard.js` 2,677, `hotkeyManager.js` 1,795). Only the renderer is TypeScript (`npm run typecheck` = `cd src && tsc --noEmit`) |
| Native helpers (macOS, Swift, spawned as child processes and talking over stdout) | `macos-globe-listener.swift` (Fn/Globe, right modifiers, mouse buttons via `NSEvent` global monitor + `CGEvent.tapCreate`), `macos-fast-paste.swift` (CGEvent ⌘V / unicode typing, `postToPid`), `macos-text-monitor.swift` (AX observer for auto-learn and app context), `macos-mic-listener.swift`, `macos-audio-tap.swift`, `macos-calendar-listener.swift` (EventKit), `macos-window-bounds.swift`, `macos-media-remote.swift`. Windows and Linux have C equivalents in `resources/*.c` |
| Sidecars | `whisper-server` (whisper.cpp HTTP server on ports 8178-8199, from the **OpenWhispr/whisper.cpp fork** releases, `scripts/download-whisper-cpp.js:19`), `llama-server` (upstream `ggml-org/llama.cpp`), sherpa-onnx CLI, Qdrant (vector DB for semantic note search) with MiniLM embeddings, ffmpeg-static, yt-dlp |
| Storage | SQLite (Kysely + better-sqlite3); API keys encrypted with Electron `safeStorage` under `userData/secure-keys/`; settings in localStorage plus `.env` |

**Audio capture:**
1. The renderer uses `MediaRecorder` (WebM).
2. For local engines it also keeps a 16 kHz mono PCM copy from mic-open, including pre-roll and capped at 4 minutes (`pcmTap.js`), so whisper.cpp/sherpa can skip the FFmpeg decode.
3. The audio goes over IPC to main, which writes a temp file and sends it to the local server or cloud (CLAUDE.md §2).

**Text insertion on macOS** (CLAUDE.md `clipboard.js` notes; `resources/macos-fast-paste.swift`):
- **Main path:** the helper checks `AXIsProcessTrusted()`, puts the transcript on the pasteboard as a *promised* `NSPasteboardItemDataProvider` item, and posts ⌘V with CGEvent.
  - The item is marked `org.nspasteboard.TransientType` so clipboard managers ignore it, and is kept off Universal Clipboard.
  - The original clipboard is restored about 50 ms after the target reads it (never sooner than 450 ms). `PASTE_NOT_READ` after 3 s and `PASTE_REPLACED` are handled. This fixed #1740/#2251 in 1.11.0.
- **Chromium browsers** (Chrome, Arc, Dia, Brave, …): synthetic ⌘V gets dropped at random, so text is *typed* as unicode key events posted to that process in chunks of ≤20 UTF-16 units. Multi-line text still uses ⌘V.
- **Fallback:** AppleScript (`osascript`) with a fixed 450 ms restore.
- **Known failures:** remote-desktop sessions paste "v" (#1641); non-QWERTY layouts (#1478, fixed); skipping Accessibility makes it silently copy-only (#2606); "auto paste stopped working" (#2384, can't reproduce).

**Permissions** (`electron-builder.json:173-177`; `src/helpers/permissionGuideManager.js`):
- Requests Microphone, Accessibility (`isTrustedAccessibilityClient`), system audio capture (meetings), Calendars, and Screen Recording (optional, for assistant screen context).
- There is no Input Monitoring prompt: Fn listening uses `NSEvent` global monitors, which ride on the Accessibility grant.
- Onboarding shows a guided overlay anchored to the System Settings window.

---

## 3. Speech-to-text and LLM providers

**Local STT:**
- **whisper.cpp** GGML models: tiny 75MB, base 142MB, small 466MB, medium 1.5GB, large 3GB, large-q5 1.1GB, turbo 1.6GB, turbo-q5 574MB (`modelRegistryData.json` `whisperModels`).
  - GPU: Metal on macOS; CUDA and Vulkan on Win/Linux, with a verified fallback ladder to CPU (1.11.0).
  - Optional Whisper VAD model.
- **sherpa-onnx** models:
  - `parakeet-tdt-0.6b-v3` (680MB, multilingual), `parakeet-unified-en-0.6b`, `parakeet-tdt-110m-en` (136MB).
  - `nemotron-speech-streaming-en-0.6b` and `nemotron-3.5-asr-streaming-0.6b` (runtime "online" = streaming).
  - `cohere-transcribe-03-2026` (2.7GB).
  - **`orukeet-v0.1.0`**: their own Parakeet fine-tune, 672MB, 25 European languages, **CC-BY-SA-4.0**, marked "recommended".
- **Streaming:** local dictation is effectively **batch on stop** (`audioManager.shouldUseStreaming()` returns false when `useLocalWhisper`, `audioManager.js:4875`). Batch with Parakeet on Apple Silicon is typically sub-second after stop. Streaming applies to cloud (and to Orukeet on OpenWhispr Cloud or a self-hosted server).

**Cloud STT (BYOK)** (`transcriptionProviders`):
- OpenAI (gpt-transcribe, gpt-4o(-mini)-transcribe, whisper-1), Groq (whisper-large-v3 / turbo), xAI grok-stt, Mistral Voxtral, Gemini 3.5 transcribe and Live, Corti, Tinfoil (Voxtral realtime), **Deepgram nova-3** (streaming), and **AssemblyAI** Universal/streaming.
- There is also a "self-hosted" OpenAI-compatible transcription endpoint (`examples/custom-asr-shim/`).
- Streaming clients: `openaiRealtimeStreaming.js`, `deepgramStreaming.js`, `assemblyAiStreaming.js`, `geminiLiveStreaming.js`, and others in `src/helpers/`.
- **Not supported:** ElevenLabs STT.

**LLMs for cleanup/agent:** see §1.2. Local GGUF models run through llama-server, which unloads after 5 idle minutes unless `keepLocalModelLoaded` is set. Ollama/LM Studio work through the "custom" OpenAI-compatible provider.

**OpenWhispr Cloud tiers** (`openwhisprCloudModels.tiers`): Fast = Groq Llama 3.3 70B / 3.1 8B; Balanced and Quality = OpenRouter (Claude Sonnet 4.6, Opus 4.8, Gemini 2.5 Flash, GPT-4.1).

---

## 4. Platforms, license, pricing, telemetry

- **Platforms:**
  - macOS arm64 and Intel. On Intel, diarization and semantic search are degraded because ONNX Runtime 1.24 dropped x86_64 mac builds.
  - Windows (.exe; winget), Linux (AppImage/deb/rpm/tar.gz, Nix flake, very deep Wayland support), and iOS/iPadOS (`openwhispr-mobile/`, Expo, with a keyboard extension).
  - A community Homebrew cask exists: `brew install --cask openwhispr`.
  - **macOS floor issue:** bundled binaries target newer macOS than the app does. #2943 is the local LLM's `libggml-metal.dylib` built for macOS 26 and failing on Sonoma; #1414 is related.
- **License:** `LICENSE` is the plain **MIT License**, "Copyright (c) 2024 OpenWhispr Team"; `package.json` `"license": "MIT"`. Caveats:
  - The Orukeet model weights are CC-BY-SA-4.0.
  - Some connectors need OAuth client secrets that only official builds have (Gmail/Slack/Linear/GitHub rows hide when env vars are absent).
- **Pricing** (https://openwhispr.com/pricing):
  - Free: unlimited local models, BYOK, dictionary, 2,000 words/week of OpenWhispr Cloud STT, 5 h/month of meetings.
  - Pro: $80/yr ($6.67/mo); adds unlimited cloud STT, **agent mode**, sync, API/MCP, and iOS.
  - Business: $160/yr; adds chat over your data.
  - Enterprise: custom; SSO/SCIM, audit logs.
  - Gating is server-side through accounts (better-auth).
- **Telemetry:** the README says "No data collection, no telemetry". I found no PostHog/Sentry/Mixpanel SDKs.
  - There is an `AnalyticsService` (`src/services/AnalyticsService.ts`, `src/helpers/analytics.js`) that, **for signed-in users**, uploads per-dictation events to the OpenWhispr API: `word_count`, `spoken_duration_ms`, `mode`, `provider`, `model`, `local_date` (`src/types/electron.ts:333`). The text is not uploaded. These feed "Insights" and a leaderboard (`LeaderboardService.ts`).
  - Auto-update contacts GitHub.
  - Fully local operation is possible if you never sign in and choose local models.

---

## 5. Release history and project health

- **Repo:** created 2025-06-19; **10,372 stars, 1,345 forks**; 244 open issues and 219 open PRs on the web UI (`gh api` `open_issues_count` = 463, which counts issues + PRs); 2,528 commits on main; last push 2026-10-30.
- **Releases:** 96 GitHub releases. **84 are app versions (`v*`)**; the rest are native-helper releases such as `windows-fast-paste-v2.0.0`.
  - v1.0.0 shipped 2025-07-24, then a slow 2025 (1.0.x).
  - Burst in Jan-Feb 2026 (39 releases: v1.1 to v1.5).
  - Since then, roughly 3-5 releases a month.
  - Minor versions: 1.1.0 (2026-01-11), 1.2.0 (01-13), 1.3.0 (01-27), 1.5.0 (02-23), 1.6.0 (03-07), 1.7.0 (05-04), 1.8.0 (07-30), 1.9.0 (08-24), 1.10.0 (09-11), 1.11.0 (2026-10-29).
  - Patch releases come roughly weekly (1.10.3 on 10-12, 1.10.4 on 10-22).
- **Recent notable changes** (`CHANGELOG.md`, 2,881 lines and very detailed):
  - 1.11.0: team dictionary, Skills library, the macOS paste-restore fix, verified GPU fallback, new models.
  - 1.10.x: connectors (Gmail/Slack/Linear/GitHub), Tone & Style, Orukeet streaming.
  - 1.8-1.9: meeting AEC and diarization, enterprise providers.
- **Contributors:** in the last 200 commits (all of October 2026), 27 authors. Commits are dominated by Chad Piha (75, founder), "Joshua" (37) and "void" (28), plus dependabot and around 20 occasional contributors. The bus factor is effectively a small core team, but the team is very active.
- **CI** (`.github/workflows/`): `npm test` runs in `release.yml` and `build-and-notarize.yml`. CodeQL, lockfile-lint, **LLM canary** and **STT canary** workflows, and native-helper builds. Releases are notarized.

---

## 6. Code quality and forkability

**Positives**
- 963 `*.test.*` files under `test/` (531 in `test/helpers/` alone), run with `node --test` plus tsx.
  - Decision logic is pulled into pure, unit-tested modules: `dictationRouting.js`, `dockPolicy.js`, `autoStartPolicy.js`, `meetingMicGate.js`, and others.
- Renderer in strict TS; ESLint and Prettier; i18n checks.
- `CLAUDE.md` (1,071 lines) is a thorough architecture map aimed at AI coding agents. That fits a "fork with Claude Code" workflow well.
- Pluggable registries:
  - Models and providers: `src/models/modelRegistryData.json` plus `ModelRegistry.ts`.
  - Prompts: `src/config/prompts/registry.ts`.
  - Connectors: `CONNECTOR_FACTORIES`.
  - Skills.

**Negatives**
- **Size and coupling:** about 250k lines in `src/` alone, plus the mobile app. Main-process core is untyped JS with god-files (`ipcHandlers.js` 14k lines). Comments and CLAUDE.md are dense with edge-case history, so the cognitive load is high.
- **Product surface you may not want:** accounts, billing, sync, enterprise MDM/SSO, workspaces, connectors, notes and meetings. Stripping them out is a big job; leaving them in means carrying them.
- **Build:** `prestart`/`predev` download many binaries (whisper.cpp fork, llama-server, sherpa-onnx, Qdrant, yt-dlp, AEC helper, models) and compile around 14 native helpers. Node 24 is pinned. For a personal macOS fork you also need your own code signing. Without a stable signature, macOS revokes Accessibility on every rebuild.
- **Upstream velocity:** around 7 commits a day. Rebasing a fork that touches `main.js`, `hotkeyManager.js` or `audioManager.js` will conflict often.

**Specific extensions**

| Extension | Where | Effort |
|---|---|---|
| **Double-tap latch / hybrid hold** | Release sites in `main.js` (Globe ~1546-1660, right-mod ~1700-1830), `windowManager.js` (`handleMacPushModifierUp`, Windows push), `hotkeyManager.setActivationMode`, `settingsStore.activationMode`, `ActivationModeSelector.tsx`. **PR #2084 already implements "hybrid" (400 ms tap-vs-hold) through pure `src/helpers/activationMode.js` plus tests**, so a fork could cherry-pick it. A true double-tap needs a timer state machine in the same pure module. | Low-medium |
| **Coding-agent formatting mode** (e.g. Markdown/code-aware cleanup when the target is Cursor, VS Code, iTerm or Claude Code) | Add a category to `src/helpers/toneAppCategories.js` (bundle-id/title → category), a tone/prompt in `src/config/prompts/toneStyle.ts` and `prompts/registry.ts`, and route it in `dictationRouting.js`. A terminal check already exists (`selectionManager` refuses terminals for assistant paste). | Medium |
| **Backend agent routing** (send the transcript to your own agent/HTTP backend instead of pasting) | Option A: add a "custom" reasoning provider with an OpenAI-compatible endpoint (no code change). Option B: a new connector in `src/helpers/connectors/` (prepare/commit pattern) or a new route kind in `dictationRouting.js`. Option C: drive it externally through the local CLI bridge `cliBridge.js` or the MCP/API. | Low (A) to medium (B) |

---

## 7. Known limitations (open issues) and gaps vs. Wispr Flow

**Open-issue themes**
- **Hotkeys:**
  - No hybrid or double-tap (#1860, #356, #362, #2238, PR #2084 open).
  - No modifier-only chords on macOS (#2669).
  - Left/right Ctrl/Shift not recordable (#2368).
  - No cancel during hold (#1400).
  - Fn conflicts with system shortcuts (#865).
- **Paste:**
  - Remote desktop pastes "v" (#1641).
  - Accessibility skip leaves it silently copy-only (#2606).
  - Windows long-text paste failures (#829).
  - Wayland edge cases.
  - Right Alt makes Chrome lose focus on Windows (#2983).
- **Latency:**
  - About 17 open and 33 closed issues match "latency". Examples: CPU-only Whisper small takes 12-16 s (#1055); Windows hotkey-to-record delay (#2765); a 26.5 s cleanup caused by a duplicate request (#2660, fixed).
  - Local LLM cold start after the 5-minute unload. You can pin it, which costs memory.
- **Accuracy:**
  - Whisper hallucinates on silence (#462).
  - The dictionary pasted on silent input (#851).
  - The dictionary breaks language detection (#2628).
  - Local meeting-mic transcripts are worse than dictation (#2998).
- **Stability:**
  - SIGILL on non-AVX2 CPUs (Win/Linux).
  - The macOS 14 local LLM failure (#2943).
  - A Linux Electron SIGTRAP (#2260).
  - Few macOS crash reports otherwise.
- **Memory:** llama-server mmap double usage (#2325). The thread count is hardcoded to 4 (#2808).

**Vs. Wispr Flow**

| Area | Gaps and status | Source |
|---|---|---|
| Undo or edit last dictation | No undo-last-dictation hotkey | #1047 meta gap map |
| Auto-stop on silence | Missing | #937, #896 |
| Spoken punctuation and commands | Weak | #888, #1320 |
| Dictation modes/profiles and profile hotkeys | Missing | #2773, #233 |
| Live streaming text for local engines | Batch only | |
| Per-app styling | Shipped as Tone & Style, off by default; coarser than Flow's | |
| Edit selection by voice | Now exists through the Voice Assistant hotkey | |
| iOS app | Exists, Pro tier | |
| "Paste last" and "Enter after paste" | Missing | #1704, #1174 |

Areas where OpenWhispr is ahead of Wispr Flow:
- Fully offline STT and LLM.
- BYOK.
- Linux.
- MIT source.
- MCP/API.
- Meeting diarization.

---

## 8. Verdict

**Adopt as a user:** a reasonable choice today for local macOS dictation. Install it (DMG or `brew install --cask openwhispr`), pick **local Parakeet v3 or Orukeet** for STT and either a local Qwen/Gemma GGUF or a BYOK fast model for cleanup, set Hold mode on Globe, and stay signed out if you want no network calls beyond update checks. The parts you'll miss versus Flow: hybrid hold plus double-tap latch, auto-stop on silence, undo-last, and live local streaming.

**Fork:** the license (MIT) and the engineering (tests, pure policy modules, AI-oriented `CLAUDE.md`) make it the most capable base of its kind. But it is a big, fast-moving product codebase rather than a lean dictation core. The recommended strategy:
- Keep the fork **thin**: cherry-pick PR #2084 for the hold/latch behaviour; add a coding-agent tone category and prompt; route to your backend through a custom OpenAI-compatible provider or a connector.
- Avoid deep surgery in `ipcHandlers.js`, `audioManager.js` and `main.js`.
- Try to upstream changes. #1860 is "working on it", so maintainers may accept hybrid mode.

If you want a small, fully owned codebase instead, treat OpenWhispr as a **reference implementation** and lift specific pieces into a leaner app: the Swift globe listener, fast-paste with read-aware clipboard restore, and the whisper-server/sherpa integration.

### Key URLs
- Repo: https://github.com/OpenWhispr/openwhispr
- Releases: https://github.com/OpenWhispr/openwhispr/releases
- Pricing: https://openwhispr.com/pricing
- Docs: https://docs.openwhispr.com
- Hybrid hotkey request: https://github.com/OpenWhispr/openwhispr/issues/1860
- Hybrid PR: https://github.com/OpenWhispr/openwhispr/pull/2084
- Closed hands-free PR: https://github.com/OpenWhispr/openwhispr/pull/1978
- Parity gap map vs. Wispr Flow and others: https://github.com/OpenWhispr/openwhispr/issues/1047
- Vendor comparison (marketing): https://openwhispr.com/compare/wisprflow
- Third-party roundup: https://www.assemblyai.com/blog/best-wispr-flow-alternatives
