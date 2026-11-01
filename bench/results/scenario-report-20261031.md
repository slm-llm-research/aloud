# Aloud scenario eval: 20261031

27 of 37 scenarios. Source: capture. Lower is better for error rates; higher for the rest.

| | Pass | STT WER | Output WER | Output CER | Strict CER | Novel words | Kept words | Layout | Mode | p50 ms | p95 ms |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **All** (27) | 85.2% | 2.7% | 11.8% | 5.5% | 12.4% | 2.5% | 92.4% | 100.0% | 100.0% | 413 | 789 |
| aiChat (3) | 100.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 100.0% | 100.0% | 100.0% | 152 | 173 |
| chat (4) | 75.0% | 8.1% | 8.1% | 4.3% | 6.3% | 8.3% | 95.0% | 100.0% | 100.0% | 393 | 614 |
| codingAgent (4) | 75.0% | 5.7% | 31.3% | 13.9% | 16.0% | 4.2% | 92.9% | 100.0% | 100.0% | 340 | 717 |
| email (4) | 100.0% | 0.0% | 1.7% | 0.5% | 2.7% | 4.4% | 95.5% | 100.0% | 100.0% | 476 | 620 |
| list (4) | 75.0% | 3.9% | 18.4% | 12.1% | 13.5% | 0.0% | 85.7% | 100.0% | 100.0% | 637 | 854 |
| prose (8) | 87.5% | 0.0% | 3.1% | 3.2% | 22.8% | 0.0% | 89.9% | 100.0% | 100.0% | 484 | 789 |

Negations kept: 100.0%. Numbers kept: 100.0%. Cleanup path: groq 17, skipped 10.

**Not scored (5):** dictated into a different app than the scenario asks, so they test that app's mode instead: code-thinking (in com.anthropic.claudefordesktop "Claude", routed aiChat); shell-git (in com.apple.Terminal "research — ✳ Claude Code — node ◂ claude — 130×51", routed codingAgent); shell-ls (in com.apple.Terminal "research — ✳ Claude Code — node ◂ claude — 130×51", routed codingAgent); shell-cd (in com.apple.Terminal "research — ✳ Claude Code — node ◂ claude — 130×51", routed codingAgent); shell-npm (in com.apple.Terminal "research — ✳ Claude Code — node ◂ claude — 130×51", routed codingAgent). Redo them with `run --only code-thinking,shell-git,shell-ls,shell-cd,shell-npm --redo`.

## Scenarios

### ❌ chat-omg (chat)

- **Said:** omg did you see the game last night
- **Heard:** Oh my God, did you see the game last night?  (STT WER 38%)
- **Expected:**

```
OMG, did you see the game last night?
```
- **Observed:**

```
Oh my God, did you see the game last night?
```
- Output WER 38%, strict CER 19%, mode chat, 212 ms, cleanup skipped [mode=chat (app: chat)]
- **Issues:** missing omg; novel words: oh, god

### ❌ code-identifiers (codingAgent)

- **Said:** rename fetch user to load user in the profile service
- **Heard:** Can you fetch user to load user in the profile server?  (STT WER 30%)
- **Expected:**

```
Rename `fetchUser` to `loadUser` in the profile service.
```
- **Observed:**

```
Can you fetch user to load user in the profile server?
```
- Output WER 88%, strict CER 27%, mode codingAgent, 155 ms, cleanup skipped [mode=codingAgent (app: terminal running an agent)]
- **Issues:** missing profile service; novel words: server

### ❌ list-correction (list)

- **Said:** to do list email the landlord fix the bike no wait book the bike service and water the plants
- **Heard:** To-do list email the landlord, fix the bike, no wait, book the bike service and water the plants.  (STT WER 0%)
- **Expected:**

```
To-do list:
- Email the landlord
- Book the bike service
- Water the plants
```
- **Observed:**

```
- To-do list email the landlord
- Fix the bike
- Book the bike service
- Water the plants
```
- Output WER 23%, strict CER 28%, mode list, 854 ms, cleanup groq [restructured; mode=list (spoken cue: to-do list); correction/filler phrase; long]
- **Issues:** has fix the bike

### ❌ prose-stutter (prose)

- **Said:** the the sub- sub-agent should handle the the retries
- **Heard:** The, the sub-sub-agent should handle the, the retries.  (STT WER 0%)
- **Expected:**

```
The sub-agent should handle the retries.
```
- **Observed:**

```
The sub-sub-agent should handle the retries.
```
- Output WER 14%, strict CER 10%, mode prose, 484 ms, cleanup groq [mode=prose (default); repeated word]
- **Issues:** has sub-sub

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
- Output WER 0%, strict CER 0%, mode aiChat, 173 ms, cleanup skipped [mode=aiChat (app: AI chat)]

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
- Output WER 0%, strict CER 0%, mode aiChat, 152 ms, cleanup skipped [mode=aiChat (app: AI chat); hesitations]

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
- Output WER 0%, strict CER 0%, mode aiChat, 152 ms, cleanup skipped [mode=aiChat (app: AI chat)]

### ✅ chat-btw (chat)

- **Said:** btw I pushed the fix can you review it when you get a chance
- **Heard:** Btw, I pushed the fix. Can you review it when you get a chance?  (STT WER 0%)
- **Expected:**

```
Btw, I pushed the fix. Can you review it when you get a chance?
```
- **Observed:**

```
Btw, I pushed the fix. Can you review it when you get a chance?
```
- Output WER 0%, strict CER 0%, mode chat, 614 ms, cleanup groq [mode=chat (app: chat); long]

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
- Output WER 0%, strict CER 0%, mode chat, 144 ms, cleanup skipped [mode=chat (app: chat)]

### ✅ chat-sorry-not-correction (chat)

- **Said:** running ten minutes late sorry
- **Heard:** Running 10 minutes late. Sorry.  (STT WER 0%)
- **Expected:**

```
Running 10 minutes late, sorry.
```
- **Observed:**

```
Running 10 minutes late. Sorry.
```
- Output WER 0%, strict CER 6%, mode chat, 393 ms, cleanup groq [mode=chat (app: chat); correction/filler phrase]

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
- Output WER 0%, strict CER 0%, mode codingAgent, 340 ms, cleanup groq [restructured; mode=codingAgent (spoken cue: prompt); long; no final punctuation]

### ✅ code-multi-ask (codingAgent)

- **Said:** the login page is broken on Safari, the redirect after sign in goes to a blank page, can you fix the redirect in auth check dot ts and add a test for it, and please don't touch the database schema, I already migrated it yesterday and it's fine
- **Heard:** The login page is broken on Safari. The redirect after sign-in goes to a blank page. Can you fix the redirect in auth, check.ts, and a test for it? And please don't touch the database schema. I already migrated it yesterday, and it's fine.  (STT WER 4%)
- **Expected:**

```
Goal: Can you fix the redirect in `authCheck.ts` and add a test for it.
Context: The login page is broken on Safari. The redirect after sign in goes to a blank page. I already migrated it yesterday and it's fine.
Constraints: Please don't touch the database schema.
```
- **Observed:**

```
Goal: Fix the redirect in `auth`, `check.ts`, and add a test for it.
Context: The login page is broken on Safari; the redirect after sign-in goes to a blank page.
Constraints: Don't touch the database schema. I already migrated it yesterday, and it's fine.
```
- Output WER 38%, strict CER 37%, mode codingAgent, 717 ms, cleanup groq [restructured; mode=codingAgent (app: terminal running an agent); long]

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
- Output WER 0%, strict CER 0%, mode codingAgent, 189 ms, cleanup skipped [mode=codingAgent (app: terminal running an agent)]

### ✅ email-checkin (email)

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
Hi Sarah,

Just checking in on the contract. Let me know if you need anything.

Thanks,
Shekhar
```
- Output WER 0%, strict CER 0%, mode email, 413 ms, cleanup groq [mode=email (web: email); long]

### ✅ email-correction (email)

- **Said:** hello team the launch is moved to March fifth sorry March twelfth please update your calendars best regards Shekhar
- **Heard:** Hello, team. The launch is moved to March 5th, sorry, March 12th. Please update your calendars. Best regards, Shekhar.  (STT WER 0%)
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
- Output WER 6%, strict CER 2%, mode email, 620 ms, cleanup groq [mode=email (web: email); correction/filler phrase; long]
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
- Output WER 0%, strict CER 9%, mode email, 476 ms, cleanup groq [mode=email (web: email); long]
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
- Output WER 0%, strict CER 0%, mode email, 155 ms, cleanup skipped [mode=email (web: email)]

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
- Output WER 0%, strict CER 0%, mode list, 513 ms, cleanup groq [restructured; mode=list (spoken cue: list); no final punctuation]

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
- Output WER 0%, strict CER 0%, mode list, 537 ms, cleanup groq [restructured; mode=list (spoken cue: grocery list)]

### ✅ list-packing (list)

- **Said:** packing list passport charger sunscreen and two swimsuits
- **Heard:** Packing list: passports, chargers, sunscreen, and two swimsuits.  (STT WER 25%)
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
- Passports
- Chargers
- Sunscreen
- Two swimsuits
```
- Output WER 57%, strict CER 26%, mode list, 637 ms, cleanup groq [restructured; mode=list (spoken cue: packing list)]

### ✅ prose-correction (prose)

- **Said:** um so I was thinking that we should uh move the meeting to Thursday because no wait Friday works better
- **Heard:** Mm, so I was thinking that we should, uh, move the meeting to Thursday because... No, wait, Friday works better.  (STT WER 0%)
- **Expected:**

```
So I was thinking that we should move the meeting to Friday because that works better.
```
- **Observed:**

```
So I was thinking that we should move the meeting to Friday works better.
```
- Output WER 12%, strict CER 15%, mode prose, 635 ms, cleanup groq [mode=prose (default); hesitations; correction/filler phrase; long]

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
- Output WER 0%, strict CER 0%, mode prose, 439 ms, cleanup groq [mode=prose (default); long]

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
- Output WER 0%, strict CER 0%, mode prose, 112 ms, cleanup skipped [mode=prose (default)]

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
- Output WER 0%, strict CER 0%, mode prose, 390 ms, cleanup groq [mode=prose (default); long]

### ✅ prose-number-correction (prose)

- **Said:** the budget is two thousand dollars sorry I mean two thousand five hundred dollars
- **Heard:** The budget is two thousand dollars, sorry I mean two thousand five hundred dollars  (STT WER 0%)
- **Expected:**

```
The budget is $2,500.
```
- **Observed:**

```
The budget is two thousand five hundred dollars.
```
- Output WER 0%, strict CER 157%, mode prose, 789 ms, cleanup groq [mode=prose (default); correction/filler phrase; long; no final punctuation]

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
- Output WER 0%, strict CER 0%, mode prose, 138 ms, cleanup skipped [mode=prose (default)]

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
- Output WER 0%, strict CER 0%, mode prose, 519 ms, cleanup groq [mode=prose (default); long]
