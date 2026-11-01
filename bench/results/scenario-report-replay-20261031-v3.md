# Aloud scenario eval: replay-20261031-v3

37 of 37 scenarios. Source: replay: say -v Samantha, replay: say -v Samantha, noise 5.0 dB SNR.  Replay = text-to-speech into live speech-to-text and the app's cleanup code (no mic, no typing into the app). Lower is better for error rates; higher for the rest.

| | Pass | STT WER | Output WER | Output CER | Strict CER | Novel words | Kept words | Layout | Mode | p50 ms | p95 ms |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **All** (37) | 83.8% | 4.3% | 9.8% | 5.3% | 7.7% | 4.8% | 94.7% | 100.0% | 100.0% | 425 | 831 |
| aiChat (3) | 100.0% | 0.0% | 0.0% | 0.0% | 0.6% | 0.0% | 100.0% | 100.0% | 100.0% | 245 | 330 |
| chat (5) | 60.0% | 19.1% | 19.1% | 11.6% | 12.1% | 14.8% | 91.7% | 100.0% | 100.0% | 445 | 1423 |
| codingAgent (6) | 100.0% | 0.8% | 17.8% | 6.3% | 7.2% | 0.0% | 100.0% | 100.0% | 100.0% | 375 | 827 |
| email (5) | 80.0% | 1.3% | 2.7% | 0.7% | 2.3% | 5.7% | 94.1% | 100.0% | 100.0% | 512 | 686 |
| list (5) | 80.0% | 1.6% | 12.8% | 10.7% | 10.3% | 0.0% | 90.0% | 100.0% | 100.0% | 606 | 831 |
| prose (9) | 100.0% | 1.7% | 1.8% | 0.9% | 5.6% | 0.0% | 100.0% | 100.0% | 100.0% | 392 | 1422 |
| terminal (4) | 50.0% | 35.0% | 15.4% | 9.3% | 16.7% | 18.8% | 81.2% | 100.0% | 100.0% | 366 | 520 |
| quiet room (32) | 90.6% | 2.9% | 8.8% | 3.4% | 6.4% | 3.4% | 96.2% | 100.0% | 100.0% | 392 | 827 |
| background noise (5) | 40.0% | 12.2% | 15.1% | 17.8% | 16.1% | 13.7% | 85.3% | 100.0% | 100.0% | 512 | 1423 |

Negations kept: 97.3%. Numbers kept: 100.0%. Cleanup path: fallback 1, groq 22, haiku 1, skipped 13.

## Scenarios

### ❌ chat-btw (chat)

- **Said:** btw I pushed the fix can you review it when you get a chance
- **Heard:** By the way, I pushed the fix. Can you review it when you get a chance?  (STT WER 21%)
- **Expected:**

```
Btw, I pushed the fix. Can you review it when you get a chance?
```
- **Observed:**

```
By the way, I pushed the fix. Can you review it when you get a chance?
```
- Output WER 21%, strict CER 11%, mode chat, 445 ms, cleanup groq [mode=chat (app: chat); long]
- **Issues:** missing btw; novel words: way

### ❌ chat-lol-noise (chat)

- **Said:** lol yeah that works for me see you at 5
- **Heard:** I don't know how yet that works for me. See you at 5:00.  (STT WER 60%)
- **Expected:**

```
Lol, yeah, that works for me. See you at 5.
```
- **Observed:**

```
I don't know how yet that works for me. See you at 5.
```
- Output WER 60%, strict CER 40%, mode chat, 1423 ms, cleanup fallback [mode=chat (app: chat); long; groq rejected: dropped a number; haiku rejected: dropped a number]
- **Issues:** negations; missing lol; novel words: don, know, how, yet

### ❌ email-checkin-noise (email)

- **Said:** hi Sarah just checking in on the contract let me know if you need anything thanks Shekhar
- **Heard:** Hi, Sarah. Just checking in on the contract. Let me know if you need anything. Thanks. Shekar.  (STT WER 6%)
- **Expected:**

```
Hi Sarah,

Just checking in on the contract. Let me know if you need anything.

Thanks,
Shekhar
```
- **Observed:**

```
Hi Sarah,

Just checking in on the contract. Let me know if you need anything.

Thanks,
Shekar
```
- Output WER 6%, strict CER 1%, mode email, 512 ms, cleanup groq [mode=email (web: email); long]
- **Issues:** missing Shekhar; novel words: shekar

### ❌ list-grocery-noise (list)

- **Said:** grocery list eggs milk two loaves of bread and spinach
- **Heard:** Grocery list of milk, two loaves of bread, and spinach.  (STT WER 10%)
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
- Milk
- Two loaves of bread
- Spinach
```
- Output WER 33%, strict CER 36%, mode list, 725 ms, cleanup groq [restructured; mode=list (spoken cue: grocery list)]
- **Issues:** missing eggs

### ❌ shell-git (terminal)

- **Said:** git checkout dash b fix slash auth
- **Heard:** Git checkout dash b fix slash off.  (STT WER 14%)
- **Expected:**

```
git checkout -b fix/auth
```
- **Observed:**

```
git checkout -b fix/off
```
- Output WER 20%, strict CER 17%, mode terminal, 520 ms, cleanup groq [mode=terminal (app: terminal at a shell prompt)]
- **Issues:** missing git checkout -b fix/auth; novel words: off

### ❌ shell-ls (terminal)

- **Said:** ls dash la
- **Heard:** LS-Law.  (STT WER 67%)
- **Expected:**

```
ls -la
```
- **Observed:**

```
ls-Law
```
- Output WER 50%, strict CER 50%, mode terminal, 318 ms, cleanup skipped [mode=terminal (app: terminal at a shell prompt)]
- **Issues:** missing ls -la; novel words: law

### ✅ ai-haiku (aiChat)

- **Said:** write a haiku about autumn
- **Heard:** Write a haiku about autumn.  (STT WER 0%)
- **Expected:**

```
Write a haiku about autumn.
```
- **Observed:**

```
Write a haiku about autumn.
```
- Output WER 0%, strict CER 0%, mode aiChat, 330 ms, cleanup skipped [mode=aiChat (app: AI chat)]

### ✅ ai-instruction (aiChat)

- **Said:** explain like I'm five how vaccines work and um keep it short
- **Heard:** Explain like I'm five how vaccines work and, um, keep it short.  (STT WER 0%)
- **Expected:**

```
Explain like I'm five how vaccines work, and keep it short.
```
- **Observed:**

```
Explain like I'm five how vaccines work and keep it short.
```
- Output WER 0%, strict CER 2%, mode aiChat, 232 ms, cleanup skipped [mode=aiChat (app: AI chat); hesitations]

### ✅ ai-question (aiChat)

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
- Output WER 0%, strict CER 0%, mode aiChat, 245 ms, cleanup skipped [mode=aiChat (app: AI chat)]

### ✅ chat-lol (chat)

- **Said:** lol yeah that works for me see you at 5
- **Heard:** LOL, yeah, that works for me. See you at 5:00.  (STT WER 0%)
- **Expected:**

```
Lol, yeah, that works for me. See you at 5.
```
- **Observed:**

```
LOL, yeah, that works for me. See you at 5.
```
- Output WER 0%, strict CER 5%, mode chat, 276 ms, cleanup skipped [mode=chat (app: chat)]

### ✅ chat-omg (chat)

- **Said:** omg did you see the game last night
- **Heard:** Omg, did you see the game last night?  (STT WER 0%)
- **Expected:**

```
OMG, did you see the game last night?
```
- **Observed:**

```
Omg, did you see the game last night?
```
- Output WER 0%, strict CER 5%, mode chat, 322 ms, cleanup skipped [mode=chat (app: chat)]

### ✅ chat-sorry-not-correction (chat)

- **Said:** running ten minutes late sorry
- **Heard:** Running 10 minutes late, sorry.  (STT WER 0%)
- **Expected:**

```
Running 10 minutes late, sorry.
```
- **Observed:**

```
Running 10 minutes late, sorry.
```
- Output WER 0%, strict CER 0%, mode chat, 448 ms, cleanup groq [mode=chat (app: chat); correction/filler phrase]

### ✅ code-as-a-prompt (codingAgent)

- **Said:** add dark mode to the settings page and keep the existing colors as the default as a prompt
- **Heard:** Add dark mode to the settings page and keep the existing colors as the default as a prompt.  (STT WER 0%)
- **Expected:**

```
Goal: Add dark mode to the settings page.
Constraints: Keep the existing colors as the default.
```
- **Observed:**

```
Goal: Add dark mode to the settings page.
Constraints: Keep the existing colors as the default.
```
- Output WER 0%, strict CER 0%, mode codingAgent, 375 ms, cleanup groq [restructured; mode=codingAgent (spoken cue: prompt); long; no final punctuation]

### ✅ code-identifiers (codingAgent)

- **Said:** rename fetch user to load user in the profile service
- **Heard:** Rename fetch user to load user in the profile service.  (STT WER 0%)
- **Expected:**

```
Rename `fetchUser` to `loadUser` in the profile service.
```
- **Observed:**

```
Rename fetch user to load user in the profile service.
```
- Output WER 50%, strict CER 8%, mode codingAgent, 150 ms, cleanup skipped [mode=codingAgent (app: terminal running an agent)]

### ✅ code-multi-ask (codingAgent)

- **Said:** the login page is broken on Safari, the redirect after sign in goes to a blank page, can you fix the redirect in auth check dot ts and add a test for it, and please don't touch the database schema, I already migrated it yesterday and it's fine
- **Heard:** The login page is broken on Safari. The redirect after sign-in goes to a blank page. Can you fix the redirect in auth_check.ts and add a test for it? And please don't touch the database schema. I already migrated it yesterday and it's fine.  (STT WER 2%)
- **Expected:**

```
Goal: Can you fix the redirect in `authCheck.ts` and add a test for it.
Context: The login page is broken on Safari. The redirect after sign in goes to a blank page. I already migrated it yesterday and it's fine.
Constraints: Please don't touch the database schema.
```
- **Observed:**

```
Goal: Fix the redirect in `auth_check.ts` and add a test for it.
Context: The login page is broken on Safari. The redirect after sign-in goes to a blank page.
Constraints: Don't touch the database schema. I already migrated it yesterday and it's fine.
```
- Output WER 38%, strict CER 35%, mode codingAgent, 827 ms, cleanup groq [restructured; mode=codingAgent (app: terminal running an agent); long]

### ✅ code-short-question (codingAgent)

- **Said:** what does the retry function in the uploader do
- **Heard:** What does the retry function in the uploader do?  (STT WER 0%)
- **Expected:**

```
What does the retry function in the uploader do?
```
- **Observed:**

```
What does the retry function in the uploader do?
```
- Output WER 0%, strict CER 0%, mode codingAgent, 294 ms, cleanup skipped [mode=codingAgent (app: terminal running an agent)]

### ✅ code-thinking (codingAgent)

- **Said:** I'm not sure why the tests are flaky, maybe it's the timeout, or maybe the mock server isn't shutting down
- **Heard:** I'm not sure why the tests are flaky. Maybe it's the timeout, or maybe the mock server isn't shutting down.  (STT WER 0%)
- **Expected:**

```
I'm not sure why the tests are flaky. Maybe it's the timeout, or maybe the mock server isn't shutting down.
```
- **Observed:**

```
I'm not sure why the tests are flaky. Maybe it's the timeout, or maybe the mock server isn't shutting down.
```
- Output WER 0%, strict CER 0%, mode codingAgent, 425 ms, cleanup groq [mode=codingAgent (app: terminal running an agent); long]

### ✅ code-thinking-noise (codingAgent)

- **Said:** I'm not sure why the tests are flaky, maybe it's the timeout, or maybe the mock server isn't shutting down
- **Heard:** I'm not sure why the tests are flaky. Maybe it's the timeout, or maybe the mock server isn't shutting down.  (STT WER 0%)
- **Expected:**

```
I'm not sure why the tests are flaky. Maybe it's the timeout, or maybe the mock server isn't shutting down.
```
- **Observed:**

```
I'm not sure why the tests are flaky. Maybe it's the timeout, or maybe the mock server isn't shutting down.
```
- Output WER 0%, strict CER 0%, mode codingAgent, 419 ms, cleanup groq [mode=codingAgent (app: terminal running an agent); long]

### ✅ email-checkin (email)

- **Said:** hi Sarah just checking in on the contract let me know if you need anything thanks Shekhar
- **Heard:** Hi, Sarah. Just checking in on the contract. Let me know if you need anything. Thanks, Shekhar.  (STT WER 0%)
- **Expected:**

```
Hi Sarah,

Just checking in on the contract. Let me know if you need anything.

Thanks,
Shekhar
```
- **Observed:**

```
Hi Sarah,

Just checking in on the contract. Let me know if you need anything.

Thanks,
Shekhar
```
- Output WER 0%, strict CER 0%, mode email, 450 ms, cleanup groq [mode=email (web: email); long]

### ✅ email-correction (email)

- **Said:** hello team the launch is moved to March fifth sorry March twelfth please update your calendars best regards Shekhar
- **Heard:** Hello, team. The launch is moved to March 5th-- sorry, March 12th. Please update your calendars. Best regards, Shekhar.  (STT WER 0%)
- **Expected:**

```
Hello team,

The launch is moved to March 12th. Please update your calendars.

Best regards,
Shekhar
```
- **Observed:**

```
Hello team,

The launch is moved to March 12. Please update your calendars.

Best regards,
Shekhar
```
- Output WER 6%, strict CER 2%, mode email, 686 ms, cleanup groq [mode=email (web: email); correction/filler phrase; long]
- **Issues:** novel words: 12

### ✅ email-no-greeting (email)

- **Said:** the deck looks great I left two comments on slide four can we sync tomorrow at ten
- **Heard:** The deck looks great. I left two comments on slide four. Can we sync tomorrow at 10:00?  (STT WER 0%)
- **Expected:**

```
The deck looks great. I left two comments on slide 4. Can we sync tomorrow at 10?
```
- **Observed:**

```
The deck looks great. I left two comments on slide four. Can we sync tomorrow at 10:00?
```
- Output WER 0%, strict CER 9%, mode email, 604 ms, cleanup groq [mode=email (web: email); long]
- **Issues:** novel words: 00

### ✅ email-short (email)

- **Said:** hey Mark can you send me the invoice
- **Heard:** Hey, Mark, can you send me the invoice?  (STT WER 0%)
- **Expected:**

```
Hey Mark,

Can you send me the invoice?
```
- **Observed:**

```
Hey Mark,

Can you send me the invoice?
```
- Output WER 0%, strict CER 0%, mode email, 138 ms, cleanup skipped [mode=email (web: email)]

### ✅ list-correction (list)

- **Said:** to do list email the landlord fix the bike no wait book the bike service and water the plants
- **Heard:** To-do list, email the landlord, fix the bike, no wait, book the bike service, and water the plants.  (STT WER 0%)
- **Expected:**

```
To-do list:
- Email the landlord
- Book the bike service
- Water the plants
```
- **Observed:**

```
- Email the landlord
- Book the bike service
- Water the plants
```
- Output WER 23%, strict CER 16%, mode list, 606 ms, cleanup groq [restructured; mode=list (spoken cue: to-do list); correction/filler phrase; long]

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
- Output WER 0%, strict CER 0%, mode list, 459 ms, cleanup groq [restructured; mode=list (spoken cue: list); no final punctuation]

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
Grocery list:
- Eggs
- Milk
- Two loaves of bread
- Spinach
```
- Output WER 0%, strict CER 0%, mode list, 570 ms, cleanup groq [restructured; mode=list (spoken cue: grocery list)]

### ✅ list-packing (list)

- **Said:** packing list passport charger sunscreen and two swimsuits
- **Heard:** Packing list: passport, charger, sunscreen, and two swimsuits.  (STT WER 0%)
- **Expected:**

```
Packing list:
- Passport
- Charger
- Sunscreen
- Two swimsuits
```
- **Observed:**

```
Packing list:
- Passport
- Charger
- Sunscreen
- Two swimsuits
```
- Output WER 0%, strict CER 0%, mode list, 831 ms, cleanup groq [restructured; mode=list (spoken cue: packing list)]

### ✅ prose-correction (prose)

- **Said:** um so I was thinking that we should uh move the meeting to Thursday because no wait Friday works better
- **Heard:** Um, so I was thinking that we should, uh, move the meeting to Thursday because-- No, wait, Friday works better.  (STT WER 0%)
- **Expected:**

```
So I was thinking that we should move the meeting to Friday because that works better.
```
- **Observed:**

```
So I was thinking that we should move the meeting to Friday because it works better.
```
- Output WER 6%, strict CER 3%, mode prose, 1422 ms, cleanup haiku [mode=prose (default); hesitations; correction/filler phrase; long; groq rejected: dropped words: because, better, no, thursday, works]

### ✅ prose-instruction-not-executed (prose)

- **Said:** write a summary of the meeting notes and send it to the team
- **Heard:** Write a summary of the meeting notes and send it to the team.  (STT WER 0%)
- **Expected:**

```
Write a summary of the meeting notes and send it to the team.
```
- **Observed:**

```
Write a summary of the meeting notes and send it to the team.
```
- Output WER 0%, strict CER 0%, mode prose, 391 ms, cleanup groq [mode=prose (default); long]

### ✅ prose-names (prose)

- **Said:** remind me to call Priya and Anand about the Q3 roadmap
- **Heard:** Remind me to call Priya and Anand about the Q3 roadmap.  (STT WER 0%)
- **Expected:**

```
Remind me to call Priya and Anand about the Q3 roadmap.
```
- **Observed:**

```
Remind me to call Priya and Anand about the Q3 roadmap.
```
- Output WER 0%, strict CER 0%, mode prose, 143 ms, cleanup skipped [mode=prose (default)]

### ✅ prose-negation (prose)

- **Said:** I don't think we should ship this before the security review is done
- **Heard:** I don't think we should ship this before the security review is done.  (STT WER 0%)
- **Expected:**

```
I don't think we should ship this before the security review is done.
```
- **Observed:**

```
I don't think we should ship this before the security review is done.
```
- Output WER 0%, strict CER 0%, mode prose, 392 ms, cleanup groq [mode=prose (default); long]

### ✅ prose-negation-noise (prose)

- **Said:** I don't think we should ship this before the security review is done
- **Heard:** I don't think you should ship this before the security review is done.  (STT WER 7%)
- **Expected:**

```
I don't think we should ship this before the security review is done.
```
- **Observed:**

```
I don't think you should ship this before the security review is done.
```
- Output WER 7%, strict CER 4%, mode prose, 462 ms, cleanup groq [mode=prose (default); long]

### ✅ prose-number-correction (prose)

- **Said:** the budget is two thousand dollars sorry I mean two thousand five hundred dollars
- **Heard:** The budget is 2,000 dollars. Sorry, I mean 2,500 dollars.  (STT WER 0%)
- **Expected:**

```
The budget is $2,500.
```
- **Observed:**

```
The budget is 2,500 dollars.
```
- Output WER 0%, strict CER 43%, mode prose, 545 ms, cleanup groq [mode=prose (default); correction/filler phrase]

### ✅ prose-question (prose)

- **Said:** what time does the pharmacy close on Sundays
- **Heard:** What time does the pharmacy close on Sundays?  (STT WER 0%)
- **Expected:**

```
What time does the pharmacy close on Sundays?
```
- **Observed:**

```
What time does the pharmacy close on Sundays?
```
- Output WER 0%, strict CER 0%, mode prose, 264 ms, cleanup skipped [mode=prose (default)]

### ✅ prose-stutter (prose)

- **Said:** the the sub- sub-agent should handle the the retries
- **Heard:** The sub, sub-agent should handle the, the retries.  (STT WER 10%)
- **Expected:**

```
The sub-agent should handle the retries.
```
- **Observed:**

```
The sub-agent should handle the retries.
```
- Output WER 0%, strict CER 0%, mode prose, 458 ms, cleanup groq [mode=prose (default); repeated word]

### ✅ prose-thinking (prose)

- **Said:** honestly I'm not sure the new design is better, it feels busier, but maybe I just need to get used to it
- **Heard:** Honestly, I'm not sure the new design is better. It feels busier, but maybe I just need to get used to it.  (STT WER 0%)
- **Expected:**

```
Honestly, I'm not sure the new design is better. It feels busier, but maybe I just need to get used to it.
```
- **Observed:**

```
Honestly, I'm not sure the new design is better. It feels busier, but maybe I just need to get used to it.
```
- Output WER 0%, strict CER 0%, mode prose, 379 ms, cleanup groq [mode=prose (default); long]

### ✅ shell-cd (terminal)

- **Said:** cd tilde slash projects
- **Heard:** CD~/projects.  (STT WER 50%)
- **Expected:**

```
cd ~/projects
```
- **Observed:**

```
cd ~/projects
```
- Output WER 0%, strict CER 0%, mode terminal, 366 ms, cleanup skipped [mode=terminal (app: terminal at a shell prompt)]

### ✅ shell-npm (terminal)

- **Said:** npm run test dash dash watch
- **Heard:** Npm run test --watch.  (STT WER 33%)
- **Expected:**

```
npm run test --watch
```
- **Observed:**

```
npm run test --watch
```
- Output WER 0%, strict CER 0%, mode terminal, 160 ms, cleanup skipped [mode=terminal (app: terminal at a shell prompt)]
