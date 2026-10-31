# InstructFlow scenario eval: baseline-1031

8 of 37 scenarios, spoken into the real app on 2026-10-31. Lower is better for error rates; higher for the rest.

| | Pass | STT WER | Output WER | Output CER | Strict CER | Novel words | Kept words | Layout | Mode | p50 ms | p95 ms |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **All** (8) | 50.0% | 1.8% | 5.1% | 3.0% | 7.0% | 5.0% | 96.9% | 87.5% | 87.5% | 479 | 1906 |
| aiChat (1) | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 100.0% | 100.0% | 0.0% | 142 | 142 |
| chat (1) | 0.0% | 10.0% | 10.0% | 5.1% | 11.6% | 40.0% | 75.0% | 100.0% | 100.0% | 167 | 167 |
| codingAgent (1) | 100.0% | 0.0% | 0.0% | 0.0% | 0.9% | 0.0% | 100.0% | 100.0% | 100.0% | 479 | 479 |
| email (1) | 0.0% | 0.0% | 0.0% | 0.0% | 9.5% | 0.0% | 100.0% | 0.0% | 100.0% | 429 | 429 |
| list (2) | 100.0% | 0.0% | 0.0% | 0.0% | 4.2% | 0.0% | 100.0% | 100.0% | 100.0% | 433 | 592 |
| prose (1) | 0.0% | 0.0% | 25.0% | 18.8% | 25.6% | 0.0% | 100.0% | 100.0% | 100.0% | 1906 | 1906 |
| terminal (1) | 100.0% | 14.3% | 0.0% | 0.0% | 0.0% | 0.0% | 100.0% | 100.0% | 100.0% | 525 | 525 |
| quiet room (7) | 57.1% | 1.0% | 4.5% | 2.7% | 6.4% | 0.0% | 100.0% | 85.7% | 85.7% | 479 | 1906 |
| background noise (1) | 0.0% | 10.0% | 10.0% | 5.1% | 11.6% | 40.0% | 75.0% | 100.0% | 100.0% | 167 | 167 |

Negations kept: 87.5%. Numbers kept: 100.0%. Cleanup path: fallback 1, groq 5, skipped 2.

## Scenarios

### ❌ ai-question (aiChat)

- **Said:** what's the difference between a process and a thread
- **Heard:** What's the difference between a process and a thread?  (STT WER 0%)
- **Expected:**

```
What's the difference between a process and a thread?
```
- **Observed:**

```
What's the difference between a process and a thread?
```
- Output WER 0%, strict CER 0%, mode prose, 142 ms, cleanup skipped [mode=prose (default)]
- **Issues:** mode

### ❌ chat-lol-noise (chat)

- **Said:** lol yeah that works for me see you at 5
- **Heard:** Love, yeah, that works for me. See you at 5:00.  (STT WER 10%)
- **Expected:**

```
Lol, yeah, that works for me. See you at 5.
```
- **Observed:**

```
Love, yeah, that works for me. See you at 5:00.
```
- Output WER 10%, strict CER 12%, mode chat, 167 ms, cleanup skipped [mode=chat (app: chat)]
- **Issues:** missing lol; has love, 5:00; novel words: love, 00

### ❌ email-checkin (email)

- **Said:** hi Sarah just checking in on the contract let me know if you need anything thanks Shekhar
- **Heard:** Hi, Sarah. Just checking in on the contract. Let me know if you need anything. Thanks. Shekhar.  (STT WER 0%)
- **Expected:**

```
Hi Sarah,

Just checking in on the contract. Let me know if you need anything.

Thanks,
Shekhar
```
- **Observed:**

```
Hi, Sarah. Just checking in on the contract. Let me know if you need anything. Thanks. Shekhar.
```
- Output WER 0%, strict CER 9%, mode email, 429 ms, cleanup groq [mode=email (web: email)]
- **Issues:** layout

### ❌ prose-correction (prose)

- **Said:** um so I was thinking that we should uh move the meeting to Thursday because no wait Friday works better
- **Heard:** Hmm. So I was thinking that we should, uh, move the meeting to Thursday because... No, wait, Friday works better.  (STT WER 0%)
- **Expected:**

```
So I was thinking that we should move the meeting to Friday because that works better.
```
- **Observed:**

```
So I was thinking that we should, move the meeting to Thursday because... No, wait, Friday works better.
```
- Output WER 25%, strict CER 26%, mode prose, 1906 ms, cleanup fallback [mode=prose (default)]
- **Issues:** negations; has Thursday

### ✅ code-thinking (codingAgent)

- **Said:** I'm not sure why the tests are flaky, maybe it's the timeout, or maybe the mock server isn't shutting down
- **Heard:** Um, I'm not sure why the tests are flaky. Maybe it's the timeout or maybe the mock server isn't shutting down.  (STT WER 0%)
- **Expected:**

```
I'm not sure why the tests are flaky. Maybe it's the timeout, or maybe the mock server isn't shutting down.
```
- **Observed:**

```
I'm not sure why the tests are flaky. Maybe it's the timeout or maybe the mock server isn't shutting down.
```
- Output WER 0%, strict CER 1%, mode codingAgent, 479 ms, cleanup groq [mode=codingAgent (app: terminal running an agent)]

### ✅ list-cue (list)

- **Said:** call mom pick up the dry cleaning and book flights make this a list
- **Heard:** Call mom, pick up the dry cleaning, and book flights. Make this a list.  (STT WER 0%)
- **Expected:**

```
- Call mom
- Pick up the dry cleaning
- Book flights
```
- **Observed:**

```
- Call mom
- Pick up the dry cleaning
- Book flights
```
- Output WER 0%, strict CER 0%, mode list, 433 ms, cleanup groq [restructured; mode=list (spoken cue: list)]

### ✅ list-grocery (list)

- **Said:** grocery list eggs milk two loaves of bread and spinach
- **Heard:** Grocery list: eggs, milk, two loaves of bread, and spinach.  (STT WER 0%)
- **Expected:**

```
Grocery list:
- Eggs
- Milk
- Two loaves of bread
- Spinach
```
- **Observed:**

```
- Grocery list: eggs
- Milk
- Two loaves of bread
- Spinach
```
- Output WER 0%, strict CER 8%, mode list, 592 ms, cleanup groq [restructured; mode=list (spoken cue: grocery list)]

### ✅ shell-git (terminal)

- **Said:** git checkout dash b fix slash auth
- **Heard:** Get checkout dash b fix slash auth.  (STT WER 14%)
- **Expected:**

```
git checkout -b fix/auth
```
- **Observed:**

```
git checkout -b fix/auth
```
- Output WER 0%, strict CER 0%, mode terminal, 525 ms, cleanup groq [mode=terminal (app: terminal at a shell prompt)]
