# Aloud benchmarks

Measured 2026-10-31 with the scenario eval harness ([`bench/scenario_eval.py`](bench/scenario_eval.py)). Interactive version: [`docs/results/index.html`](docs/results/index.html) (served at https://slm-llm-research.github.io/aloud/results/). Regenerate everything with `cd bench && uv run python export_results.py`.

## Behavior evals (2026-11-01)

660 labelled transcripts: per app, positives (the change should happen) and hard negatives (look-alikes
that must be left alone), split 40/30/30 into train (prompt construction), dev (choosing prompt variants and
settings) and a held-out test split scored only for the baseline (commit `22bf7db`) and the final build.

| Held-out test, 198 cases | Baseline | Final |
|---|---|---|
| App chain (Groq, then Haiku), all | 84% | **92%** |
| Groq alone / Haiku alone | 82% / 87% | **92% / 94%** |
| Self-corrections | 56% | **85%** |
| Lists vs sentences | 85% | **92%** |
| Prompt vs free speech (coding agents) | 97% | **100%** |
| Misheard words | 85% | **100%** |
| Hard cases | 79% | **89%** |
| To-do apps / Claude Code / chat apps | 53% / 82% / 76% | **88% / 100% / 88%** |
| Fidelity (negations, numbers, hedges kept) | 88% | 76% (known gap, next) |
| Latency p50 / p95 (app chain) | 513 / 1341 ms | 480 / 1186 ms |

Full breakdowns (category × polarity, difficulty, length, app), the tuning log with rejected experiments,
and limits: [`bench/results/BEHAVIOR.md`](bench/results/BEHAVIOR.md).

## Before and after

### Real voice (27 scenarios)

Identical speech-to-text transcripts from the author's voice, cleaned by the build under test and by the current code.

| Metric | Before | After |
|---|---|---|
| Pass | 85.2% | **92.6%** (+7.4 pts ✓) |
| STT WER | 2.7% | **2.7%** (±0) |
| Output WER | 11.8% | **10.3%** (−1.5 pts ✓) |
| Output CER | 5.5% | **3.8%** (−1.7 pts ✓) |
| Strict CER | 12.4% | **10.5%** (−2.0 pts ✓) |
| Novel words | 2.5% | **2.5%** (±0) |
| Kept words | 92.4% | **93.4%** (+1.0 pts ✓) |
| Layout | 100.0% | **100.0%** (±0) |
| Mode | 100.0% | **100.0%** (±0) |
| Negations kept | 100.0% | **100.0%** (±0) |
| Numbers kept | 100.0% | **100.0%** (±0) |
| Latency p50 / p95 | 413 / 789 ms | 375 / 1701 ms |

### Synthetic voice (37 scenarios)

All 37 scenarios spoken by macOS text-to-speech; noise scenarios mix in a second speaker at 5 dB SNR.

| Metric | Before | After |
|---|---|---|
| Pass | 73.0% | **83.8%** (+10.8 pts ✓) |
| STT WER | 4.5% | **4.3%** (−0.2 pts ✓) |
| Output WER | 10.0% | **9.8%** (−0.2 pts ✓) |
| Output CER | 4.8% | **5.3%** (+0.6 pts ✗) |
| Strict CER | 9.5% | **7.7%** (−1.7 pts ✓) |
| Novel words | 4.4% | **4.8%** (+0.4 pts ✗) |
| Kept words | 93.7% | **94.7%** (+1.0 pts ✓) |
| Layout | 94.6% | **100.0%** (+5.4 pts ✓) |
| Mode | 100.0% | **100.0%** (±0) |
| Negations kept | 97.3% | **97.3%** (±0) |
| Numbers kept | 100.0% | **100.0%** (±0) |
| Latency p50 / p95 | 424 / 607 ms | 425 / 831 ms |

Error rates (WER, CER, novel words): lower is better. Everything else: higher is better.

## Every run

| Run | Voice | Scenarios | Pass | STT WER | Output WER | Strict CER | Novel words | Negations kept | p50 ms | p95 ms |
|---|---|---|---|---|---|---|---|---|---|---|
| Field test, before any fixes | Real voice | 6 | 50.0% | 2.6% | 7.6% | 9.2% | 6.7% | 83.3% | 433 | 1906 |
| Real voice, build under test | Real voice | 27 | 85.2% | 2.7% | 11.8% | 12.4% | 2.5% | 100.0% | 413 | 789 |
| Real voice, current code | Real voice | 27 | 92.6% | 2.7% | 10.3% | 10.5% | 2.5% | 100.0% | 375 | 1701 |
| Synthetic voice, first run | Synthetic voice | 37 | 73.0% | 4.5% | 10.0% | 9.5% | 4.4% | 97.3% | 424 | 607 |
| Synthetic voice, current code | Synthetic voice | 37 | 83.8% | 4.3% | 9.8% | 7.7% | 4.8% | 97.3% | 425 | 831 |

## By app (real voice)

Where each scenario was actually dictated, and how it did before and after on the same transcripts.

| App | Modes | Scenarios | Pass before | Pass after | Output WER before | Output WER after | STT WER | p50 ms |
|---|---|---|---|---|---|---|---|---|
| Notes | Lists, Notes / prose | 12 | 83.3% | **100.0%** | 7.4% | 4.4% | 1.3% | 519 |
| Gmail (Chrome) | Email | 4 | 100.0% | **100.0%** | 1.7% | 1.7% | 0.0% | 476 |
| WhatsApp | Chat | 4 | 75.0% | **75.0%** | 8.1% | 8.1% | 8.1% | 393 |
| Claude Code (Terminal) | Coding agent | 4 | 75.0% | **75.0%** | 31.3% | 30.1% | 5.8% | 340 |
| Claude desktop | AI chat | 3 | 100.0% | **100.0%** | 0.0% | 0.0% | 0.0% | 152 |

## By mode

| Mode | Real voice, build under test | Real voice, current code | Synthetic voice, first run | Synthetic voice, current code |
|---|---|---|---|---|
| Notes / prose | 87.5% (8) | 100.0% (8) | 100.0% (9) | 100.0% (9) |
| Email | 100.0% (4) | 100.0% (4) | 80.0% (5) | 80.0% (5) |
| Chat | 75.0% (4) | 75.0% (4) | 60.0% (5) | 60.0% (5) |
| Lists | 75.0% (4) | 100.0% (4) | 60.0% (5) | 80.0% (5) |
| AI chat | 100.0% (3) | 100.0% (3) | 100.0% (3) | 100.0% (3) |
| Coding agent | 75.0% (4) | 75.0% (4) | 66.7% (6) | 100.0% (6) |
| Shell | – | – | 25.0% (4) | 50.0% (4) |

Pass rate (scenarios scored).

## Quiet room vs background noise (synthetic voice)

| Run | Condition | Scenarios | Pass | STT WER | Output WER | Novel words |
|---|---|---|---|---|---|---|
| Synthetic voice, first run | Quiet room | 32 | 81.2% | 4.1% | 10.6% | 3.7% |
| Synthetic voice, first run | Background noise | 5 | 20.0% | 6.8% | 6.9% | 8.8% |
| Synthetic voice, current code | Quiet room | 32 | 90.6% | 2.9% | 8.8% | 3.4% |
| Synthetic voice, current code | Background noise | 5 | 40.0% | 12.2% | 15.1% | 13.7% |

## How it was tested

- **Scenarios:** [`bench/scenarios.jsonl`](bench/scenarios.jsonl), 37 lines to speak across Notes, Gmail, WhatsApp, ChatGPT, Claude Code and a shell. They cover self-corrections, negations, numbers, names, slang, stutters, lists, email layout, shell symbols, and five background-noise variants. Each has the expected text and checks.
- **Real voice:** the author spoke each scenario into the named app with the installed app build. The app records what speech-to-text heard and what it typed (`~/Library/Logs/Aloud/dictations.jsonl`), and `scenario_eval.py run` pairs each record with its scenario.
- **Before/after on identical input:** `scenario_eval.py reclean` runs the current cleanup code over the transcripts speech-to-text produced in the real-voice session, so speech recognition is held fixed.
- **Synthetic voice:** `scenario_eval.py replay` speaks every scenario with macOS text-to-speech, streams it to live speech-to-text with the app's settings, and runs the app's cleanup code (the `ScenarioReplay` Swift test). It skips only the mic and typing into the app.
- **Pass:** required phrases present, banned phrases absent, layout right for the app (list, email, single line, Goal/Context/Constraints), every negation and number kept, and the right mode chosen.
- **Not scored:** a scenario dictated into a different app than it names (for example a shell scenario said into Claude Code) tests that other app's mode, so it is left out and listed below.

| Environment | |
|---|---|
| Mac | Apple M1 Pro (MacBookPro18,1) |
| Macos | macOS 15.7.4 |
| Speech to text | ElevenLabs Scribe v2 realtime (filter_background_audio on, dictionary + chat keyterms) |
| Cleanup | Groq openai/gpt-oss-120b (1.5 s timeout), then Claude Haiku 5.5 (2.5 s), then rule-based fallback |
| Synthetic voice | macOS `say -v Samantha`, 16 kHz; noise scenarios add a LibriSpeech speaker plus hiss at 5 dB SNR |
| Latency | Real voice: key release to text typed. Synthetic: speech-to-text commit to result, plus cleanup. |

### Not scored

| Run | Scenario | Asked for | Dictated in | Routed as |
|---|---|---|---|---|
| baseline-1031 | ai-question | ChatGPT or Claude in the browser (message box) | Codex app | Notes / prose |
| baseline-1031 | code-thinking | Claude Code running in Terminal | Terminal (zsh) | Coding agent |
| 20261031 | code-thinking | Claude Code running in Terminal | Claude desktop | AI chat |
| 20261031 | shell-git | Terminal at a plain zsh prompt (no agent running) | Claude Code (Terminal) | Coding agent |
| 20261031 | shell-ls | Terminal at a plain zsh prompt (no agent running) | Claude Code (Terminal) | Coding agent |
| 20261031 | shell-cd | Terminal at a plain zsh prompt (no agent running) | Claude Code (Terminal) | Coding agent |
| 20261031 | shell-npm | Terminal at a plain zsh prompt (no agent running) | Claude Code (Terminal) | Coding agent |
| 20261031-reclean | code-thinking | Claude Code running in Terminal | Claude desktop | AI chat |
| 20261031-reclean | shell-git | Terminal at a plain zsh prompt (no agent running) | Claude Code (Terminal) | Coding agent |
| 20261031-reclean | shell-ls | Terminal at a plain zsh prompt (no agent running) | Claude Code (Terminal) | Coding agent |
| 20261031-reclean | shell-cd | Terminal at a plain zsh prompt (no agent running) | Claude Code (Terminal) | Coding agent |
| 20261031-reclean | shell-npm | Terminal at a plain zsh prompt (no agent running) | Claude Code (Terminal) | Coding agent |

## Scenario by scenario (real voice)

| Scenario | App | Heard (speech-to-text) | Typed before | Typed after | Before | After |
|---|---|---|---|---|---|---|
| `code-multi-ask` | Claude Code (Terminal) | The login page is broken on Safari. The redirect after sign-in goes to a blank page. Can you fix the redirect in auth, check.ts, and a test for it? And please don't touch the database schema. I already migrated it yesterday, and it's fine. | Goal: Fix the redirect in `auth`, `check.ts`, and add a test for it.<br>Context: The login page is broken on Safari; the redirect after sign-in goes to a blank page.<br>Constraints: Don't touch the database schema. I already migrated it yesterday, and it's fine. | Goal: Fix the redirect in `auth.ts` and add a test for it.<br>Context: The login page is broken on Safari. The redirect after sign-in goes to a blank page.<br>Constraints: Don't touch the database schema. I already migrated it yesterday, and it's fine. | ✅ | ✅ |
| `list-correction` | Notes | To-do list email the landlord, fix the bike, no wait, book the bike service and water the plants. | - To-do list email the landlord<br>- Fix the bike<br>- Book the bike service<br>- Water the plants | - Email the landlord<br>- Book the bike service<br>- Water the plants | ❌ | ✅ |
| `list-packing` | Notes | Packing list: passports, chargers, sunscreen, and two swimsuits. | - Passports<br>- Chargers<br>- Sunscreen<br>- Two swimsuits | Packing list:<br>- Passports<br>- Chargers<br>- Sunscreen<br>- Two swimsuits | ✅ | ✅ |
| `prose-correction` | Notes | Mm, so I was thinking that we should, uh, move the meeting to Thursday because... No, wait, Friday works better. | So I was thinking that we should move the meeting to Friday works better. | So I was thinking that we should move the meeting to Friday, because Friday works better. | ✅ | ✅ |
| `prose-stutter` | Notes | The, the sub-sub-agent should handle the, the retries. | The sub-sub-agent should handle the retries. | The sub-agent should handle the retries. | ❌ | ✅ |
| `chat-omg` | WhatsApp | Oh my God, did you see the game last night? | Oh my God, did you see the game last night? | Oh my God, did you see the game last night? | ❌ | ❌ |
| `code-identifiers` | Claude Code (Terminal) | Can you fetch user to load user in the profile server? | Can you fetch user to load user in the profile server? | Can you fetch user to load user in the profile server? | ❌ | ❌ |
| `ai-haiku` | Claude desktop | Write a haiku about autumn. | Write a haiku about autumn. | Write a haiku about autumn. | ✅ | ✅ |
| `ai-instruction` | Claude desktop | Explain like I'm five how vaccines work, and, um, keep it short. | Explain like I'm five how vaccines work, and keep it short. | Explain like I'm five how vaccines work, and keep it short. | ✅ | ✅ |
| `ai-question` | Claude desktop | What's the difference between a process and a thread? | What's the difference between a process and a thread? | What's the difference between a process and a thread? | ✅ | ✅ |
| `chat-btw` | WhatsApp | Btw, I pushed the fix. Can you review it when you get a chance? | Btw, I pushed the fix. Can you review it when you get a chance? | Btw, I pushed the fix. Can you review it when you get a chance? | ✅ | ✅ |
| `chat-lol` | WhatsApp | Lol, yeah, that works for me. See you at 5:00. | Lol, yeah, that works for me. See you at 5. | Lol, yeah, that works for me. See you at 5. | ✅ | ✅ |
| `chat-sorry-not-correction` | WhatsApp | Running 10 minutes late. Sorry. | Running 10 minutes late. Sorry. | Running 10 minutes late. Sorry. | ✅ | ✅ |
| `code-as-a-prompt` | Claude Code (Terminal) | Add dark mode to the settings page and keep the existing colors as the default as a prompt. | Goal: Add dark mode to the settings page.<br>Constraints: Keep the existing colors as the default. | Goal: Add dark mode to the settings page.<br>Constraints: Keep the existing colors as the default. | ✅ | ✅ |
| `code-short-question` | Claude Code (Terminal) | What does the retry function in the uploader do? | What does the retry function in the uploader do? | What does the retry function in the uploader do? | ✅ | ✅ |
| `email-checkin` | Gmail (Chrome) | Hi, Sarah. Just checking in on the contract. Let me know if you need anything. Thanks. Shekhar. | Hi Sarah,<br><br>Just checking in on the contract. Let me know if you need anything.<br><br>Thanks,<br>Shekhar | Hi Sarah,<br><br>Just checking in on the contract. Let me know if you need anything.<br><br>Thanks,<br>Shekhar | ✅ | ✅ |
| `email-correction` | Gmail (Chrome) | Hello, team. The launch is moved to March 5th, sorry, March 12th. Please update your calendars. Best regards, Shekhar. | Hello team,<br><br>The launch is moved to March 12. Please update your calendars.<br><br>Best regards,<br>Shekhar | Hello team,<br><br>The launch is moved to March 12. Please update your calendars.<br><br>Best regards,<br>Shekhar | ✅ | ✅ |
| `email-no-greeting` | Gmail (Chrome) | The deck looks great. I left two comments on slide four. Can we sync tomorrow at 10:00? | The deck looks great. I left two comments on slide four. Can we sync tomorrow at 10:00? | The deck looks great. I left two comments on slide four. Can we sync tomorrow at 10:00? | ✅ | ✅ |
| `email-short` | Gmail (Chrome) | Hey, Mark, can you send me the invoice? | Hey Mark,<br><br>Can you send me the invoice? | Hey Mark,<br><br>Can you send me the invoice? | ✅ | ✅ |
| `list-cue` | Notes | Call mom, pick up the dry cleaning, and book flights. Make this a list. | - Call mom<br>- Pick up the dry cleaning<br>- Book flights | - Call mom<br>- Pick up the dry cleaning<br>- Book flights | ✅ | ✅ |
| `list-grocery` | Notes | Grocery list: eggs, milk, two loaves of bread, and spinach. | Grocery list:<br>- Eggs<br>- Milk<br>- Two loaves of bread<br>- Spinach | Grocery list:<br>- Eggs<br>- Milk<br>- Two loaves of bread<br>- Spinach | ✅ | ✅ |
| `prose-instruction-not-executed` | Notes | Write a summary of the meeting notes and send it to the team. | Write a summary of the meeting notes and send it to the team. | Write a summary of the meeting notes and send it to the team. | ✅ | ✅ |
| `prose-names` | Notes | Remind me to call Priya and Anand about the Q3 roadmap. | Remind me to call Priya and Anand about the Q3 roadmap. | Remind me to call Priya and Anand about the Q3 roadmap. | ✅ | ✅ |
| `prose-negation` | Notes | I don't think we should ship this before the security review is done. | I don't think we should ship this before the security review is done. | I don't think we should ship this before the security review is done. | ✅ | ✅ |
| `prose-number-correction` | Notes | The budget is two thousand dollars, sorry I mean two thousand five hundred dollars | The budget is two thousand five hundred dollars. | The budget is two thousand five hundred dollars. | ✅ | ✅ |
| `prose-question` | Notes | What time does the pharmacy close on Sundays? | What time does the pharmacy close on Sundays? | What time does the pharmacy close on Sundays? | ✅ | ✅ |
| `prose-thinking` | Notes | Honestly, I'm not sure the new design is better. It feels busier, but maybe I just need to get used to it. | Honestly, I'm not sure the new design is better. It feels busier, but maybe I just need to get used to it. | Honestly, I'm not sure the new design is better. It feels busier, but maybe I just need to get used to it. | ✅ | ✅ |

Failures that remain are mostly speech-to-text mishearings that reach the cleanup already wrong ("omg" spelled out as "Oh my God", "rename" heard as "Can you"). The cleanup does not guess at those: a guess would break the promise to keep the speaker's words. Full per-scenario reports: [`bench/results/`](bench/results/).
