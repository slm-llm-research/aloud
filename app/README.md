# InstructFlow (macOS app)

## Build, test, run

```bash
cd voice-flow/app
swift test                                            # unit tests (fast, no permissions needed)
INSTRUCTFLOW_INTEGRATION=1 swift test --filter STTKitTests  # real Parakeet model (first run downloads ~600 MB)
scripts/bundle.sh                                     # -> build/InstructFlow.app (release, signed)
open build/InstructFlow.app
```

On first launch, macOS asks for the **Microphone**, **Input Monitoring** and **Accessibility** permissions. Grant all three in System Settings → Privacy & Security. InstructFlow picks the permissions up within a few seconds; the menu-bar ⏦ icon's menu shows "Ready".

Ad-hoc signing (the default) changes the app's identity on every rebuild, so macOS asks again after each `bundle.sh`. To avoid that, use `SIGN_ID="<your identity>" scripts/bundle.sh`.

## Use

| Keys | Action |
|---|---|
| Hold **Right Shift**, talk, release | Dictate into the focused app |
| **Double-tap Right Shift** | Latch the mic open; tap Right Shift again to finish |
| **Esc** while recording | Cancel |
| Hold **Right Shift**, then also hold **Right ⌘**, talk, release | Task mode: the spoken task goes to the agent (with approvals) instead of being typed. The order of the two keys doesn't matter. |

Tab is never intercepted, so Shift + Tab (either Shift) always reaches the app, for example Claude Code's mode switch. Right Shift + Right ⌘ types nothing on its own, so no app sees it as a shortcut.

## Modules

| Module | What it does | Tests |
|---|---|---|
| `HotkeyKit` | Right Shift (+ Right ⌘ / Right Option chords) state machine, key classification, CGEventTap | 30 (incl. a 5,000-keystroke typing fuzz) |
| `AudioKit` | Mic capture, 16 kHz mono resampling, sample buffer | 5 |
| `STTKit` | Parakeet TDT 0.6B v2 on the Neural Engine (FluidAudio 0.18.0) | 2 integration |
| `InsertKit` | Clipboard snapshot/restore, transient pasteboard, Cmd-V / Unicode typing, terminal sanitizing | 12 |
| `InstructFlowCore` | Session: record → transcribe → insert; task-mode routing | 11 |
| `InstructFlow` | Menu-bar app, HUD, permissions, wiring | manual |
