# InstructFlow scenario eval: replay-20261031

37 of 37 scenarios. Source: replay: say -v Samantha, replay: say -v Samantha, noise 5.0 dB SNR.  Replay = text-to-speech into live speech-to-text and the app's cleanup code (no mic, no typing into the app). Lower is better for error rates; higher for the rest.

| | Pass | STT WER | Output WER | Output CER | Strict CER | Novel words | Kept words | Layout | Mode | p50 ms | p95 ms |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **All** (37) | 73.0% | 4.5% | 10.0% | 4.8% | 9.5% | 4.4% | 93.7% | 94.6% | 100.0% | 424 | 607 |
| aiChat (3) | 100.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 100.0% | 100.0% | 100.0% | 321 | 362 |
| chat (5) | 60.0% | 8.5% | 8.5% | 3.9% | 4.7% | 8.3% | 91.7% | 100.0% | 100.0% | 256 | 473 |
| codingAgent (6) | 66.7% | 3.0% | 18.6% | 8.3% | 9.9% | 1.3% | 97.4% | 83.3% | 100.0% | 389 | 607 |
| email (5) | 80.0% | 2.6% | 4.0% | 0.9% | 2.5% | 7.5% | 92.3% | 100.0% | 100.0% | 559 | 991 |
| list (5) | 60.0% | 1.6% | 14.9% | 9.0% | 14.4% | 0.0% | 97.5% | 80.0% | 100.0% | 482 | 524 |
| prose (9) | 100.0% | 1.7% | 2.7% | 1.3% | 6.0% | 0.0% | 100.0% | 100.0% | 100.0% | 455 | 951 |
| terminal (4) | 25.0% | 45.0% | 30.8% | 11.6% | 32.0% | 18.8% | 68.8% | 100.0% | 100.0% | 376 | 514 |
| quiet room (32) | 81.2% | 4.1% | 10.6% | 4.8% | 9.9% | 3.7% | 94.5% | 93.8% | 100.0% | 410 | 607 |
| background noise (5) | 20.0% | 6.8% | 6.8% | 4.7% | 6.9% | 8.8% | 88.7% | 100.0% | 100.0% | 496 | 580 |

Negations kept: 97.3%. Numbers kept: 100.0%. Cleanup path: groq 23, skipped 14.

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
- Output WER 21%, strict CER 11%, mode chat, 473 ms, cleanup groq [mode=chat (app: chat); long]
- **Issues:** missing btw; novel words: way

### ❌ chat-lol-noise (chat)

- **Said:** lol yeah that works for me see you at 5
- **Heard:** Lmao, yeah, that works for me. See you at 5.  (STT WER 10%)
- **Expected:**

```
Lol, yeah, that works for me. See you at 5.
```
- **Observed:**

```
Lmao, yeah, that works for me. See you at 5.
```
- Output WER 10%, strict CER 7%, mode chat, 223 ms, cleanup skipped [mode=chat (app: chat)]
- **Issues:** missing lol; novel words: lmao

### ❌ code-as-a-prompt (codingAgent)

- **Said:** add dark mode to the settings page and keep the existing colors as the default as a prompt
- **Heard:** Add dark mode to the settings page and keep the existing colors as the default as a prompt.  (STT WER 0%)
- **Expected:**

```
Goal: Add dark mode to the settings page.
Constraints: Keep the existing colors as the default.
```
- **Observed:**

```
Goal: Add dark mode to the settings page and keep the existing colors as the default.
```
- Output WER 6%, strict CER 14%, mode codingAgent, 403 ms, cleanup groq [mode=codingAgent (spoken cue: prompt); long; no final punctuation]
- **Issues:** layout

### ❌ code-thinking-noise (codingAgent)

- **Said:** I'm not sure why the tests are flaky, maybe it's the timeout, or maybe the mock server isn't shutting down
- **Heard:** I'm not sure why the tests are flaky. Maybe it's the timeout, or maybe the mod server isn't shutting down.  (STT WER 4%)
- **Expected:**

```
I'm not sure why the tests are flaky. Maybe it's the timeout, or maybe the mock server isn't shutting down.
```
- **Observed:**

```
I'm not sure why the tests are flaky. Maybe it's the timeout, or maybe the mod server isn't shutting down.
```
- Output WER 4%, strict CER 2%, mode codingAgent, 580 ms, cleanup groq [mode=codingAgent (app: terminal running an agent); long]
- **Issues:** missing mock server; novel words: mod

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
- Output WER 6%, strict CER 1%, mode email, 559 ms, cleanup groq [mode=email (web: email); long]
- **Issues:** missing Shekhar; novel words: shekar

### ❌ list-correction (list)

- **Said:** to do list email the landlord fix the bike no wait book the bike service and water the plants
- **Heard:** To-do list, email the landlord, fix the bike. No, wait, book the bike service and water the plants.  (STT WER 0%)
- **Expected:**

```
To-do list:
- Email the landlord
- Book the bike service
- Water the plants
```
- **Observed:**

```
To-do list: email the landlord, fix the bike. No, wait, book the bike service and water the plants.
```
- Output WER 46%, strict CER 47%, mode list, 485 ms, cleanup groq [mode=list (spoken cue: to-do list); correction/filler phrase; long]
- **Issues:** layout; negations; has fix the bike

### ❌ list-grocery-noise (list)

- **Said:** grocery list eggs milk two loaves of bread and spinach
- **Heard:** Grocery list of milk, two loaves of bread and spinach.  (STT WER 10%)
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
- Grocery list of milk
- Two loaves of bread
- Spinach
```
- Output WER 11%, strict CER 20%, mode list, 482 ms, cleanup groq [restructured; mode=list (spoken cue: grocery list)]
- **Issues:** missing eggs

### ❌ shell-cd (terminal)

- **Said:** cd tilde slash projects
- **Heard:** C/D~/projects.  (STT WER 75%)
- **Expected:**

```
cd ~/projects
```
- **Observed:**

```
C/D~/projects
```
- Output WER 100%, strict CER 23%, mode terminal, 376 ms, cleanup skipped [mode=terminal (app: terminal at a shell prompt)]
- **Issues:** missing cd ~/projects

### ❌ shell-git (terminal)

- **Said:** git checkout dash b fix slash auth
- **Heard:** Get checkout dash B fix slash off.  (STT WER 29%)
- **Expected:**

```
git checkout -b fix/auth
```
- **Observed:**

```
git checkout -b fix/off
```
- Output WER 20%, strict CER 17%, mode terminal, 514 ms, cleanup groq [mode=terminal (app: terminal at a shell prompt)]
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
LS-Law
```
- Output WER 50%, strict CER 83%, mode terminal, 126 ms, cleanup skipped [mode=terminal (app: terminal at a shell prompt)]
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
- Output WER 0%, strict CER 0%, mode aiChat, 238 ms, cleanup skipped [mode=aiChat (app: AI chat)]

### ✅ ai-instruction (aiChat)

- **Said:** explain like I'm five how vaccines work and um keep it short
- **Heard:** Explain like I'm five how vaccines work, and, um, keep it short.  (STT WER 0%)
- **Expected:**

```
Explain like I'm five how vaccines work, and keep it short.
```
- **Observed:**

```
Explain like I'm five how vaccines work, and keep it short.
```
- Output WER 0%, strict CER 0%, mode aiChat, 321 ms, cleanup skipped [mode=aiChat (app: AI chat); hesitations]

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
- Output WER 0%, strict CER 0%, mode aiChat, 362 ms, cleanup skipped [mode=aiChat (app: AI chat)]

### ✅ chat-lol (chat)

- **Said:** lol yeah that works for me see you at 5
- **Heard:** Lol, yeah, that works for me. See you at 5:00.  (STT WER 0%)
- **Expected:**

```
Lol, yeah, that works for me. See you at 5.
```
- **Observed:**

```
Lol, yeah, that works for me. See you at 5.
```
- Output WER 0%, strict CER 0%, mode chat, 252 ms, cleanup skipped [mode=chat (app: chat)]

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
- Output WER 0%, strict CER 5%, mode chat, 256 ms, cleanup skipped [mode=chat (app: chat)]

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
- Output WER 0%, strict CER 0%, mode chat, 436 ms, cleanup groq [mode=chat (app: chat); correction/filler phrase]

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
- Output WER 50%, strict CER 8%, mode codingAgent, 291 ms, cleanup skipped [mode=codingAgent (app: terminal running an agent)]

### ✅ code-multi-ask (codingAgent)

- **Said:** the login page is broken on Safari, the redirect after sign in goes to a blank page, can you fix the redirect in auth check dot ts and add a test for it, and please don't touch the database schema, I already migrated it yesterday and it's fine
- **Heard:** The login page is broken on Safari. The redirect after sign-in goes to a blank page. Can you fix the redirect in authcheck.ts and add a test for it? And please don't touch the database schema. I already migrated it yesterday and it's fine.  (STT WER 6%)
- **Expected:**

```
Goal: Can you fix the redirect in `authCheck.ts` and add a test for it.
Context: The login page is broken on Safari. The redirect after sign in goes to a blank page. I already migrated it yesterday and it's fine.
Constraints: Please don't touch the database schema.
```
- **Observed:**

```
Goal: Fix the redirect in `authcheck.ts` and add a test for it.
Context: The login page is broken on Safari. The redirect after sign-in goes to a blank page.
Constraints: Please don't touch the database schema. I already migrated it yesterday and it's fine.
```
- Output WER 36%, strict CER 36%, mode codingAgent, 607 ms, cleanup groq [restructured; mode=codingAgent (app: terminal running an agent); long]

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
- Output WER 0%, strict CER 0%, mode codingAgent, 298 ms, cleanup skipped [mode=codingAgent (app: terminal running an agent)]

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
- Output WER 0%, strict CER 0%, mode codingAgent, 389 ms, cleanup groq [mode=codingAgent (app: terminal running an agent); long]

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
- Output WER 0%, strict CER 0%, mode email, 599 ms, cleanup groq [mode=email (web: email); long]

### ✅ email-correction (email)

- **Said:** hello team the launch is moved to March fifth sorry March twelfth please update your calendars best regards Shekhar
- **Heard:** Hello, team. The launch is moved to March 5th-- sorry, March 12th. Please update your calendars. Best regards, Shekar.  (STT WER 5%)
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
Shekar
```
- Output WER 12%, strict CER 3%, mode email, 991 ms, cleanup groq [mode=email (web: email); correction/filler phrase; long]
- **Issues:** novel words: 12, shekar

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
- Output WER 0%, strict CER 9%, mode email, 424 ms, cleanup groq [mode=email (web: email); long]
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
- Output WER 0%, strict CER 0%, mode email, 175 ms, cleanup skipped [mode=email (web: email)]

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
- Output WER 0%, strict CER 0%, mode list, 469 ms, cleanup groq [restructured; mode=list (spoken cue: list); no final punctuation]

### ✅ list-grocery (list)

- **Said:** grocery list eggs milk two loaves of bread and spinach
- **Heard:** Grocery list, eggs, milk, two loaves of bread, and spinach.  (STT WER 0%)
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
- Grocery list
- Eggs
- Milk
- Two loaves of bread
- Spinach
```
- Output WER 0%, strict CER 5%, mode list, 524 ms, cleanup groq [restructured; mode=list (spoken cue: grocery list)]

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
- Output WER 0%, strict CER 0%, mode list, 452 ms, cleanup groq [restructured; mode=list (spoken cue: packing list)]

### ✅ prose-correction (prose)

- **Said:** um so I was thinking that we should uh move the meeting to Thursday because no wait Friday works better
- **Heard:** Um, so I was thinking that we should, uh, move the meeting to Thursday because-- No, wait, Friday works better.  (STT WER 0%)
- **Expected:**

```
So I was thinking that we should move the meeting to Friday because that works better.
```
- **Observed:**

```
I was thinking that we should move the meeting to Friday because it works better.
```
- Output WER 12%, strict CER 7%, mode prose, 951 ms, cleanup groq [mode=prose (default); hesitations; correction/filler phrase; long]

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
- Output WER 0%, strict CER 0%, mode prose, 393 ms, cleanup groq [mode=prose (default); long]

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
- Output WER 0%, strict CER 0%, mode prose, 284 ms, cleanup skipped [mode=prose (default)]

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
- Output WER 0%, strict CER 0%, mode prose, 529 ms, cleanup groq [mode=prose (default); long]

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
- Output WER 7%, strict CER 4%, mode prose, 496 ms, cleanup groq [mode=prose (default); long]

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
- Output WER 0%, strict CER 43%, mode prose, 491 ms, cleanup groq [mode=prose (default); correction/filler phrase]

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
- Output WER 0%, strict CER 0%, mode prose, 189 ms, cleanup skipped [mode=prose (default)]

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
- Output WER 0%, strict CER 0%, mode prose, 455 ms, cleanup groq [mode=prose (default); repeated word]

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
- Output WER 0%, strict CER 0%, mode prose, 410 ms, cleanup groq [mode=prose (default); long]

### ✅ shell-npm (terminal)

- **Said:** npm run test dash dash watch
- **Heard:** Npm run test --watch.  (STT WER 33%)
- **Expected:**

```
npm run test --watch
```
- **Observed:**

```
Npm run test --watch
```
- Output WER 0%, strict CER 5%, mode terminal, 320 ms, cleanup skipped [mode=terminal (app: terminal at a shell prompt)]
