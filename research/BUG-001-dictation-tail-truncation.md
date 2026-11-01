# BUG-001: Last words are cut off on longer dictations

| Field | Value |
|---|---|
| Status | Fixed 2026-10-31 (root cause H1 confirmed from the dictation log); see section 0 |
| Reported by | Shekhar (own observation while dictating) |
| Reported | 2026-10-31 |
| Component | Dictation path: AudioKit -> STTKit -> AloudCore (STTRace) -> CleanupKit -> InsertKit |
| Severity | High. Silent data loss: the text looks complete, so the loss goes unnoticed. |
| Affects | Dictation mode (Right Shift). Task mode (Right Shift + Right Cmd) shares the same STT path, so check it too. |

## 0. Resolution (2026-10-31)

**Root cause: H1.** `~/Library/Logs/Aloud/dictations.jsonl` already had the evidence. The four
longest dictations (30 to 62 s) all used cloud STT and reported key-up to transcript times of
**12, 26, 38 and 143 ms**. A real final segment can't arrive that fast. `finish()` had returned the
segments Scribe had committed on its own during the recording, without waiting for the final one.
The heard text itself ends mid-phrase: "So, what I'm thinking about is", "let me know your",
"I leave you to it, and". So the words were lost before cleanup. Scribe does split long realtime
audio into its own commits even with `commit_strategy=manual`.

| Hypothesis | Verdict | Change |
|---|---|---|
| H1 early return | **Cause** | `ScribeTranscript` (new, in `STTKit/ScribeRealtime.swift`): segments committed before key-up are kept, and `finish()` returns only when the segment for our final commit arrives. If it never does (3 s), it returns what was committed. |
| H2 token cap | Not seen; hardened | `finish_reason=length` / `stop_reason=max_tokens` now throw `LLMError.truncated`, so the chain falls back. `max_tokens` grows with the input. The guardrail rejects output missing 2 of the last 3 content words (`dropped the ending`), except for corrections. |
| H3 local race | Hardened | The cloud window grows by 10 ms per second of audio past 10 s, capped at +350 ms (`Session.raceWindow`), because the real final segment now takes ~100 to 250 ms. |
| H4 key-up clip | Hardened | Recording continues 120 ms after key-up (`Session.tailPad`), so the end of the last word and the buffered audio are kept. |
| H5 insertion | Not seen | No change. |

**Instrumentation:** every dictation now logs `scribe: segments=N early=M final=yes|timeout|no`. It
appears in `aloud.log` and as `stt_notes` in `dictations.jsonl`. `early>0` with `final=yes`
means the old code would have dropped words.

**Tests:**
- `STTKitTests/TailTruncationTests`: an early segment followed by the final one; the final segment arriving before the wait; timeout; an empty final segment.
- `CleanupKitTests/TailTruncationTests`: truncated Groq and Claude responses; the token cap; the guardrail's ending check.
- `AloudCoreTests` (race window).
- `bench/scenarios.jsonl`: two long dictations with end markers (`long-notes-tail-marker`, `long-agent-tail-marker`, tag `tail`).

**To confirm with real speech:**
- run `uv run python bench/scenario_eval.py run --tags tail`, or dictate for 40 s or more with a marker phrase at the end;
- the log line should show `early>=1 final=yes`, and STT latency should be in the hundreds of milliseconds, not the tens.

## 1. Observation

On longer dictations, the final word or words of what was said are missing from the inserted text. Short dictations seem fine. Update 2026-10-31: the loss is the **last 3 to 4 words**, roughly 1 to 1.5 seconds of speech. Still unmeasured: the "longer" threshold and which pipeline stage loses them.

What 3 to 4 words tells us: this is too much audio for H4 (a 20 to 100 ms clip at key-up) to explain on its own, and it is a whole trailing phrase, not a clipped syllable. That points at H1 (final segment dropped), H2 (output truncated) or H3 (local engine tail). H4 and H5 are unlikely to be the main cause.

Expected: every spoken word up to key-up is inserted, in order.

## 2. Pipeline and where a tail can be lost

Key-up -> `AudioRecorder.end()` -> `ScribeRealtimeSession.finish()` raced against local Parakeet (`STTRace`, 250 ms window) -> cleanup (Groq, then Claude Haiku, fidelity guardrail) -> `TextInserter`.

Each stage can drop the end of the text. Suspects are ranked by how well they fit "only long dictations, only the end".

### H1 (most likely): `finish()` returns early with partial text

In `ScribeRealtimeSession.finish()`, after sending the final commit, the continuation checks `else if !committed.isEmpty` and returns the text collected so far straight away. It does not wait for the transcript that the final commit produces.

If the server has already emitted any `committed_transcript` during the recording, `committed` is non-empty at key-up. `finish()` then returns that earlier text and discards the final segment, which holds the last words. `handle(.committed)` only resumes a waiter that is already registered, so the late final transcript arrives after the result was returned and is dropped.

Why it fits: it only happens when an intermediate commit exists, which is more likely on long audio (server-side segmenting at a length limit, or a pause-based commit despite `commit_strategy=manual`). Unverified: whether Scribe v2 realtime emits intermediate commits under manual strategy. The log will show it.

### H2: Cleanup output is truncated by the token cap

`LLMClients.swift` sets `max_tokens` to 1200 (Groq, gpt-oss-120b) and 1024 (Claude Haiku). gpt-oss-120b is a reasoning model, and reasoning tokens usually count against the cap. A long transcript can therefore hit `finish_reason: length` and return text that stops early. The fidelity guardrail should reject a result with low word recall and fall back to the rule-cleaned text, but it is not confirmed that it does for a truncated tail. A tail of only a few words may stay above the recall threshold.

Why it fits: the loss would grow with transcript length and always hit the end.

### H3: Race falls through to local Parakeet on long clips

`STTRace` gives the cloud 250 ms after key-up. That window was tuned (p95 of 203 ms) on short utterances. Scribe's final transcript on a long clip may take longer, so local wins. Parakeet transcribes the whole clip in one call, and its behaviour on long audio (internal chunking, a maximum length, tail handling) is unverified.

Why it fits: it makes long clips use the local engine more often, so engine-specific tail behaviour shows up exactly there.

### H4: Audio tail lost at key-up

`AudioRecorder.end()` removes the tap and stops the engine immediately. Audio still in the 1024-frame tap buffer and the hardware buffer (roughly 20 to 100 ms) is not delivered. The streaming side keeps up to 100 ms unsent in `pending`, which `takeTail()` does flush, but only what the tap has already delivered. Releasing the key in the middle of the last word, which is common at the end of a long thought, would clip it.

Why it is less likely: it should cost at most one word and should not depend on length. Include it because it is cheap to fix.

### H5 (low): Insertion drops the end

`TextInserter` types in 20-UTF-16-unit chunks via `keyboardSetUnicodeString`. Some apps drop events under load, which would clip long text. Check whether the missing words are also missing from the clipboard fallback.

## 3. Reproduction

1. Dictate a numbered script of about 60 seconds that ends with a distinctive marker phrase, e.g. "... and the final marker is blue seven nine."
2. Repeat at about 10 s, 30 s, 60 s and 120 s, 5 runs each.
3. Run each length with the cloud key set and with it unset (forces local only).
4. Record for each run: inserted text, whether the marker survived, and the log lines below.

Compare cloud-only against local-only. If the loss disappears with the key unset, suspect H1 or H3 (cloud path). If it persists, suspect H4 or H5. Run once with cleanup disabled (verbatim mode, no LLM) to separate H2.

## 4. Instrumentation to add first (about 30 minutes)

Log to `DiagLog` for every dictation:
- audio seconds, sample count, key-up to finish latency;
- Scribe: number of `committed_transcript` events, timestamp of each relative to key-up, and whether `finish()` took the early-return branch;
- race result: winner (cloud or local), and both texts' word counts if both complete;
- cleanup: provider used, `finish_reason` / `stop_reason`, completion tokens, input and output word counts, guardrail verdict;
- inserted text word count and last 5 words.

Then diff the last five words at each stage. The first stage where the marker is gone is the culprit.

## 4b. Logging to add (concrete)

Add one structured line per dictation to `DiagLog` (`~/Library/Logs/Aloud/aloud.log`), keyed by a short `dictationId`, so a single `grep` reconstructs the whole path. Log word counts and the last 5 words only, not full text, to keep the log small and less sensitive; add full text behind a debug flag when needed.

```
[dictation <id>] audio   secs=62.4 samples=998400 keyUpToFinishMs=...
[dictation <id>] scribe  commitEvents=2 firstCommitAtMs=41200 earlyReturn=true|false finalCommitReceived=true|false
[dictation <id>] race    winner=cloud|local cloudWords=148 localWords=152 cloudMs=... localMs=...
[dictation <id>] cleanup provider=groq finish=stop|length completionTokens=... inWords=148 outWords=144 guardrail=pass|fail(reason)
[dictation <id>] insert  words=144 tail="...last five words..."
[dictation <id>] tails   stt="...last 5..." cleaned="...last 5..." inserted="...last 5..."
```

Where to hook each line:
- `audio`: in `Session.process` (has `samples`, `keyUp`).
- `scribe`: in `ScribeRealtimeSession.handle(.committed)` (count and timestamp every commit) and in `finish()` (record which branch was taken: early return vs waiter).
- `race`: in `STTRace.run` (winner, and let the loser finish in the background just for logging while the flag is on).
- `cleanup`: in `LLMClients.swift` after each response (`finish_reason` / `stop_reason`, usage tokens) and in the guardrail result.
- `tails`: in `Session.process` after insert, comparing the last 5 words at each stage.

Reading the log:
- `earlyReturn=true` with `commitEvents>=1` before key-up: H1 confirmed.
- `finish=length` or `outWords` much lower than `inWords` with the guardrail passing: H2 confirmed.
- `winner=local` on the failing runs and the cloud tail is intact: H3 confirmed.
- STT tail intact, cleaned tail missing: cleanup. STT tail already missing: STT or audio.

Run the repro in section 3 with this on; the first stage whose tail differs from the spoken marker is the culprit.

## 5. Proposed fixes (apply after confirming)

- H1: in `finish()`, wait for the committed transcript that follows the final commit, with a timeout (for example 2 s, longer for long audio), and join it with earlier segments. Never return on `!committed.isEmpty` alone. Track "committed after finish" explicitly.
- H2: treat `finish_reason == length` / `stop_reason == max_tokens` as failure and fall back to the rule-cleaned text. Size `max_tokens` from the input (about 1.5x input tokens plus headroom, and more for reasoning models, or set reasoning effort to low). Add a tail check to the guardrail: the last 3 to 5 input words must appear in the output, otherwise reject.
- H3: scale the race window with audio length (for example 250 ms plus a small amount per 10 s of audio), or wait for cloud on clips over about 20 s. Test Parakeet on 60 s and 120 s clips and chunk it if needed.
- H4: keep recording for 150 to 300 ms after key-up (trailing pad), or flush the engine before stopping. Show it as part of "finishing" in the UI.
- H5: verify with the clipboard fallback; add a post-insert check only if this proves to be the cause.

## 6. Tests

- Unit: `ScribeRealtimeSession.finish()` with a mock socket that emits an early `committed_transcript` before the final one. Assert the result contains both segments.
- Unit: cleanup client mock returning `finish_reason: length`. Assert fallback to rule-cleaned text.
- Guardrail: output that drops only the last 4 words must be rejected.
- Bench: add long-form (60 s and 120 s) scenarios with end markers to `bench/scenarios.jsonl`, and report tail-word recall per stage alongside the existing metrics.

## 7. Acceptance

Across 20 dictations of 60 s or longer, in both cloud and local-only modes, the final 5 words are present in every inserted result, and a mismatch is logged at the stage where it occurred.

## 8. Open questions

- Roughly how long is "longer" (seconds or words)? (still open)
- Answered: the last 3 to 4 words are lost.
- Does it happen with the network off (local only)?
- Which app was in front? Does the clipboard copy of the text have the same tail missing?
