# InstructFlow: The Simple Version

*InstructFlow is a placeholder name. The full plan with all the details is in [PLAN.md](PLAN.md).*

## What we're building

A small Mac app that lives in your menu bar.

1. **Hold a key and talk.** Clean text appears wherever your cursor is: Slack, Cursor, Claude, a terminal, anywhere.
2. **Use a different key combo to give it a task** ("open my project and run the tests"). An AI agent does it on your Mac, but asks before doing anything risky.

It's yours. There are no credits or word limits, and it works offline.

## How you use it

| You do | It does |
|---|---|
| **Hold Right Shift** and talk, then let go | Types what you said, cleaned up |
| **Double-tap Right Shift** | Keeps the mic on hands-free; tap again to stop |
| **Esc** | Cancels |
| **Right Shift + Right Option** with text selected | Edits the selected text ("make this shorter") |
| **Hold Right Shift + Right ⌘**, talk, let go | Sends a *task* to the agent instead of typing |

Fn stays with Wispr Flow. All of these keys can be changed in settings.

**Shift still types normally:**
- Only the *right* Shift key triggers, and only after you've held it for a quarter of a second without pressing any other key.
- Typing a capital letter (Shift + a letter) does nothing special.
- Tab is never intercepted, so Shift + Tab (Claude Code's mode switch, reverse-Tab in forms) always works. The task chord uses Right ⌘, which types nothing on its own.

## What "cleaned up" means

- Removes "um", "uh", "like" and "you know".
- Fixes punctuation and capital letters.
- Handles self-corrections: "Thursday, no wait, Friday" becomes "Friday".
- Spells code words correctly: "use state" becomes `useState`.
- **In coding apps** (Claude Code, Cursor, terminal), long rambling requests are turned into a clear instruction:

  ```
  Goal: ...
  Requirements: ...
  Steps: ...
  ```

## System architecture

```
                         ┌───────────────────────────────────────────────┐
   YOU                   │            MURMUR APP (on your Mac)           │
                         │                                               │
  hold Right Shift ─────►│  1. KEY LISTENER                              │
                         │     hold = talk · double-tap = latch          │
                         │     Right Shift + Right ⌘ = task              │
                         │                │                              │
  speak ────────────────►│  2. MICROPHONE                                │
                         │                │                              │
                         │                ▼                              │
                         │  3. SPEECH → TEXT  (two run at once)          │
                         │     ┌─────────────────┐  ┌─────────────────┐  │
                         │     │ ElevenLabs      │  │ Parakeet        │  │
                         │     │ (cloud, most    │  │ (on your Mac,   │  │
                         │     │  accurate)      │  │  fast, offline) │  │
                         │     └────────┬────────┘  └────────┬────────┘  │
                         │              └─── best one wins ──┘           │
                         │                        │                      │
                         │  4. WHICH APP ARE YOU IN?                     │
                         │     Slack? Cursor? Terminal? Zoom?            │
                         │                        │                      │
                         │            ┌───────────┴───────────┐          │
                         │            ▼                       ▼          │
                         │  5a. CLEANUP                5b. TASK MODE     │
                         │   AI removes fillers,        (R-Shift + R-⌘)  │
                         │   fixes punctuation;               │          │
                         │   coding apps get the              │          │
                         │   Goal/Steps format                │          │
                         │            │                       │          │
                         │            ▼                       │          │
                         │  6. TYPE IT IN                     │          │
                         │     pastes into your app,          │          │
                         │     restores your clipboard        │          │
                         └────────────┼───────────────────────┼──────────┘
                                      │                       │
  text appears ◄──────────────────────┘                       ▼
                         ┌───────────────────────────────────────────────┐
                         │          AGENT HELPER (separate program)      │
                         │                                               │
                         │  plans the task → checks the risk of          │
                         │  each step → ASKS YOU → does it → logs it     │
                         │                                               │
                         │  Can: open apps/files, run allowed commands,  │
                         │  run Claude Code in your repos, Shortcuts     │
                         │  Blocked: rm -rf, sudo, force-push, etc.      │
                         └───────────────────────────────────────────────┘
```

**Why there are two programs:** typing has to be instant and must never break. Agent tasks are slow and riskier. Keeping them apart means a stuck agent can't freeze your dictation.

## The tech, in plain words

| Part | What we use | Why |
|---|---|---|
| The app | Swift (Apple's own language) | Fastest and lightest on a Mac; about 50 MB of memory instead of about 750 MB |
| Speech → text (cloud) | ElevenLabs Scribe | Most accurate available, and you already have keys |
| Speech → text (local) | Parakeet | About 0.2 s on your Mac, works offline, accuracy equal to Whisper |
| Cleanup AI | Groq (gpt-oss-120b), with Claude Haiku as backup | Tested: 100% correct, about 0.25 s |
| Agent | Claude | Plans and runs the tasks |

## Safety rules for the agent

- It **only** runs tasks when you use Right Shift + Right ⌘. Normal talking never triggers it.
- It **asks before** anything that changes files, runs commands or sends messages.
- Dangerous things are **always blocked**, e.g. deleting everything, `sudo`, force-push.
- It works only in folders you allow.
- Every action is **logged**, and a **kill-switch key** stops everything.

## Speed and accuracy targets

| Goal | Target |
|---|---|
| Plain dictation: key release to text | **under 0.5 s** |
| With AI cleanup | **under 0.9 s** |
| Wrong words | under 4 in 100 |
| Code words spelled right | 95%+ |

## Build steps

| Step | What you get | Time |
|---|---|---|
| **0. Test** | Measure which engines are fastest and most accurate on *your* Mac *(done; your own voice recordings still to do)* | ✅ mostly done |
| **1. Basic dictation** | Hold Right Shift, talk, text appears; works offline | ~1 week |
| **2. Cloud speed boost** | Add ElevenLabs, race it against local | ~4 days |
| **3. Smart cleanup** | Fillers, corrections, dictionary, undo | ~1 week |
| **4. Coding mode** | Goal/Steps format in Claude Code, Cursor and terminals | ~1 week |
| **5. Edit by voice** | Select text and say "make it formal" | ~3 days |
| **6. Agent tasks** | Right Shift + Right ⌘ tasks with approvals | ~1.5 weeks |
| **7. Polish** | Test in every app, package it | ~1 week |

## What we learned from testing so far

- **Parakeet is great:** about 0.2 s and 1.4% wrong words.
- **Code words are the hard part.** "FastAPI" came out as "FastAppy". We'll fix this with a custom word list and by passing your file names to the AI.
- **ElevenLabs is the fastest:** text arrives about 0.12 s after you let go of the key, with 1.5% wrong words.
- **Groq's gpt-oss-120b is the best cleanup AI:** 100% correct on our test cases in about 0.25 s. Claude Haiku was also 100% correct but about 3× slower, so it's the backup.
- **Expected total time with cleanup: about 0.4 s typical, 0.8 s worst case.** That's within the target.
- **Small offline AI models aren't good enough for cleanup.** They missed self-corrections, and one followed a dictated "write a poem" command. So the main cleanup uses cloud AI, and offline mode only does light cleanup.

## Decisions for you

1. Build our own app (recommended), or adapt OpenWhispr?
2. ~~Main key~~: decided. Right Shift for dictation, Right Shift + Right ⌘ for tasks (changed from Shift + Tab, which clashed with Claude Code).
3. Do you have an Apple Developer account ($99/yr), or is this just for your Mac?
4. ~~Cloud tests~~: done.
