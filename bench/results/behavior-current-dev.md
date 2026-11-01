# Behavior eval: current (dev)

| | app (was) | groq (was) | haiku (was) |
|---|---|---|---|
| all | 92% (179/195) (was 78%) | 88% (172/195) (was 76%) | 92% (179/195) (was 83%) |
| ai_chat | 100% (12/12) (was 100%) | 100% (12/12) (was 100%) | 100% (12/12) (was 100%) |
| &nbsp;&nbsp;positive | 100% (7/7) (was 100%) | 100% (7/7) (was 100%) | 100% (7/7) (was 100%) |
| &nbsp;&nbsp;negative | 100% (5/5) (was 100%) | 100% (5/5) (was 100%) | 100% (5/5) (was 100%) |
| chat | 93% (13/14) (was 71%) | 93% (13/14) (was 71%) | 100% (14/14) (was 86%) |
| &nbsp;&nbsp;positive | 88% (7/8) (was 75%) | 88% (7/8) (was 75%) | 100% (8/8) (was 100%) |
| &nbsp;&nbsp;negative | 100% (6/6) (was 67%) | 100% (6/6) (was 67%) | 100% (6/6) (was 67%) |
| email | 93% (14/15) (was 80%) | 93% (14/15) (was 80%) | 100% (15/15) (was 100%) |
| &nbsp;&nbsp;positive | 100% (9/9) (was 89%) | 100% (9/9) (was 89%) | 100% (9/9) (was 100%) |
| &nbsp;&nbsp;negative | 83% (5/6) (was 67%) | 83% (5/6) (was 67%) | 100% (6/6) (was 100%) |
| fidelity | 81% (13/16) (was 81%) | 81% (13/16) (was 88%) | 88% (14/16) (was 88%) |
| &nbsp;&nbsp;positive | 80% (8/10) (was 80%) | 80% (8/10) (was 90%) | 80% (8/10) (was 80%) |
| &nbsp;&nbsp;negative | 83% (5/6) (was 83%) | 83% (5/6) (was 83%) | 100% (6/6) (was 100%) |
| list_vs_sentences | 92% (37/40) (was 72%) | 85% (34/40) (was 70%) | 92% (37/40) (was 72%) |
| &nbsp;&nbsp;positive | 89% (17/19) (was 68%) | 79% (15/19) (was 63%) | 89% (17/19) (was 68%) |
| &nbsp;&nbsp;negative | 95% (20/21) (was 76%) | 90% (19/21) (was 76%) | 95% (20/21) (was 76%) |
| misheard | 100% (12/12) (was 100%) | 100% (12/12) (was 100%) | 100% (12/12) (was 100%) |
| &nbsp;&nbsp;positive | 100% (7/7) (was 100%) | 100% (7/7) (was 100%) | 100% (7/7) (was 100%) |
| &nbsp;&nbsp;negative | 100% (5/5) (was 100%) | 100% (5/5) (was 100%) | 100% (5/5) (was 100%) |
| prompt_vs_speech | 94% (29/31) (was 97%) | 97% (30/31) (was 84%) | 87% (27/31) (was 100%) |
| &nbsp;&nbsp;positive | 87% (13/15) (was 93%) | 100% (15/15) (was 67%) | 93% (14/15) (was 100%) |
| &nbsp;&nbsp;negative | 100% (16/16) (was 100%) | 94% (15/16) (was 100%) | 81% (13/16) (was 100%) |
| self_correction | 88% (36/41) (was 54%) | 80% (33/41) (was 54%) | 85% (35/41) (was 56%) |
| &nbsp;&nbsp;positive | 79% (19/24) (was 21%) | 67% (16/24) (was 21%) | 75% (18/24) (was 25%) |
| &nbsp;&nbsp;negative | 100% (17/17) (was 100%) | 100% (17/17) (was 100%) | 100% (17/17) (was 100%) |
| terminal | 93% (13/14) (was 86%) | 79% (11/14) (was 86%) | 93% (13/14) (was 93%) |
| &nbsp;&nbsp;positive | 89% (8/9) (was 78%) | 67% (6/9) (was 78%) | 89% (8/9) (was 89%) |
| &nbsp;&nbsp;negative | 100% (5/5) (was 100%) | 100% (5/5) (was 100%) | 100% (5/5) (was 100%) |
| app: ai_apps | 95% (19/20) (was 80%) | 95% (19/20) (was 80%) | 95% (19/20) (was 80%) |
| app: chat_apps | 94% (47/50) (was 76%) | 90% (45/50) (was 74%) | 96% (48/50) (was 82%) |
| app: claude_code | 96% (22/23) (was 91%) | 91% (21/23) (was 91%) | 83% (19/23) (was 91%) |
| app: codex | 75% (6/8) (was 88%) | 88% (7/8) (was 75%) | 88% (7/8) (was 88%) |
| app: editor | 89% (16/18) (was 83%) | 89% (16/18) (was 72%) | 83% (15/18) (was 89%) |
| app: email_apps | 89% (25/28) (was 82%) | 86% (24/28) (was 82%) | 96% (27/28) (was 93%) |
| app: notes | 100% (21/21) (was 71%) | 95% (20/21) (was 71%) | 100% (21/21) (was 81%) |
| app: terminal | 88% (14/16) (was 81%) | 69% (11/16) (was 81%) | 88% (14/16) (was 88%) |
| app: todo | 82% (9/11) (was 36%) | 82% (9/11) (was 36%) | 82% (9/11) (was 27%) |
| difficulty: easy | 97% (102/105) (was 86%) | 94% (99/105) (was 85%) | 97% (102/105) (was 88%) |
| difficulty: hard | 86% (77/90) (was 69%) | 81% (73/90) (was 66%) | 86% (77/90) (was 77%) |
| difficulty+polarity: easy negative | 100% (44/44) (was 93%) | 100% (44/44) (was 93%) | 98% (43/44) (was 95%) |
| difficulty+polarity: easy positive | 95% (58/61) (was 80%) | 90% (55/61) (was 79%) | 97% (59/61) (was 82%) |
| difficulty+polarity: hard negative | 93% (40/43) (was 84%) | 88% (38/43) (was 84%) | 93% (40/43) (was 88%) |
| difficulty+polarity: hard positive | 79% (37/47) (was 55%) | 74% (35/47) (was 49%) | 79% (37/47) (was 66%) |
| length: long | 85% (33/39) (was 82%) | 85% (33/39) (was 79%) | 79% (31/39) (was 87%) |
| length: medium | 93% (82/88) (was 76%) | 90% (79/88) (was 73%) | 95% (84/88) (was 78%) |
| length: short | 94% (64/68) (was 78%) | 88% (60/68) (was 78%) | 94% (64/68) (was 85%) |
| polarity: negative | 97% (84/87) (was 89%) | 94% (82/87) (was 89%) | 95% (83/87) (was 92%) |
| polarity: positive | 88% (95/108) (was 69%) | 83% (90/108) (was 66%) | 89% (96/108) (was 75%) |

Latency p50 / p95 (ms): app 529 / 1458, groq 521 / 948, haiku 1546 / 2065

## Failures: app (16)

- **ac-042** (positive, Claude desktop): layout≠list  
  said: `I'm making a meal plan for the week and my rules are: first, no red meat on weekdays, second, at least two fish dinners, third, nothing that takes more than 40 minutes, and fourth, um, my daughter won't eat anything spicy. Can you build the plan around those?`  
  typed: `I'm making a meal plan for the week, and my rules are: first, no red meat on weekdays; second, at least two fish dinners; third, nothing that takes more than 40 minutes; and fourth, my daughter won't eat anything spicy. Can you build the plan around those?`  
  via groq · hesitations; long; groq layout: sentences
- **ch-012** (positive, Teams): missing 'kinda blanked'  
  said: `hey um so I kinda blanked on the vendor call this morning, sorry, uh can you just send me the gist when you get a chance? gonna follow up with them after lunch, and um if they asked about pricing just tell me what they said, don't worry about writing it up properly`  
  typed: `Hey, I blanked on the vendor call this morning. Sorry, can you just send me the gist when you get a chance? Gonna follow up with them after lunch, and if they asked about pricing just tell me what they said, don't worry about writing it up properly.`  
  via groq · hesitations; correction/filler phrase; long; no final punctuation; groq layout: sentences
- **ch-037** (positive, Discord): has 'eastern'  
  said: `um let's run the raid at uh 8:00 eastern, pacific, 8:00 pacific, people are still at work`  
  typed: `Let's run the raid at 8 Eastern, Pacific, 8:00 Pacific; people are still at work.`  
  via groq · hesitations; repeated word; long; no final punctuation; groq layout: sentences
- **code-013** (positive, Codex app): missing 'Excel'  
  said: `so basically the CSV export is cutting off names with accents, it's an encoding thing I think. fix the export so it writes UTF-8 with a BOM so Excel opens it right, add a test with a name like José, and don't change the column order.`  
  typed: `Goal: Fix the CSV export so it writes UTF-8 with a BOM. ⏎ Context: The CSV export is cutting off names with accents; it's an encoding issue. ⏎ Tasks: Add a test with a name like José. ⏎ Constraints: Don't change the column order.`  
  via groq · restructured; long; groq layout: prompt
- **corr-018** (positive, Slack): has 'staging'  
  said: `ping me when the staging, the production deploy finishes`  
  typed: `Ping me when the staging, the production deploy finishes.`  
  via groq · no final punctuation; groq layout: sentences
- **cx-005** (positive, Cursor): layout≠prompt  
  said: `the cart total should include shipping before tax is applied and right now it doesn't, ideally with a unit test for the free shipping threshold`  
  typed: `The cart total should include shipping before tax is applied, and right now it doesn't. Ideally with a unit test for the free shipping threshold.`  
  via haiku · long; no final punctuation; groq layout: prompt; groq rejected: new words: add, calculation, tasks, update; haiku layout: sentences
- **cx-053** (positive, Cursor): has 'blue'  
  said: `okay so the client looked at the mockup yesterday and they weren't happy with how heavy the whole top of the page really feels, so um make the header blue, or actually no, make it match the footer color, and drop the border`  
  typed: `Goal: Make it match the footer color, and drop the border ⏎ Context: Okay so the client looked at the mockup yesterday and they weren't happy with how heavy the whole top of the page really feels, so make the header blue, or actually no.`  
  via fallback · restructured; hesitations; correction/filler phrase; long; no final punctuation; groq layout: prompt; groq correction: make the header blue -> make it match the footer color; groq rejected: shrank 42->12 words; haiku layout: prompt; haiku correction: blue -> match the footer color; haiku rejected: reported a correction it didn't apply; fallback laid out as prompt
- **cx-057** (positive, Codex app): has 'react-day-picker'  
  said: `So for the date picker, I'd like you to switch the library to react-day-picker, um, no, sorry, to the one we already use in the booking form, which is flatpickr I think, and keep the same props so the parent components don't change.`  
  typed: `Goal: So for the date picker, I'd like you to switch the library to react-day-picker, no, sorry, to the one we already use in the booking form, which is flatpickr I think. ⏎ Constraints: Keep the same props so the parent components. Don't change.`  
  via fallback · restructured; hesitations; correction/filler phrase; long; groq layout: prompt; groq correction: react-day-picker -> flatpickr; groq rejected: shrank 42->19 words; haiku layout: prompt; haiku correction: react-day-picker -> flatpickr; haiku rejected: reported a correction it didn't apply; fallback laid out as prompt
- **cx-083** (positive, Claude Code CLI in Terminal): missing 'I guess'  
  said: `okay so, uh, the tile server, it's on version 3.4.2 and we can't go to 4 because of the license change, so, um, I guess just patch the memory leak on the 3.4 branch, and don't touch the renderer, I really don't want to re-test that`  
  typed: `Goal: Patch the memory leak on the 3.4 branch. ⏎ Context: The tile server is on version 3.4.2, and we can't upgrade to 4 because of the license change. ⏎ Constraints: Don't touch the renderer; don't re-test the renderer.`  
  via groq · restructured; hesitations; long; no final punctuation; groq layout: prompt
- **em-020** (negative, Gmail in Chrome): missing 'thanks to the new intake process'  
  said: `thanks to the new intake process we saved a week per hire`  
  typed: `Thanks to the new interview process we saved a week per hire.`  
  via groq · groq repaired: intake process -> interview process; no final punctuation; groq layout: sentences
- **em-053** (positive, Mail): missing 'council'  
  said: `um, we can't confirm before the 14th, uh, the council's slow.`  
  typed: `We can't confirm before the 14th. The council's slow.`  
  via groq · hesitations; groq layout: sentences
- **em-062** (negative, Mail): missing 'maybe'  
  said: `we might, maybe, be able to move the date, but please don't promise anything to the client yet.`  
  typed: `We might be able to move the date, but please don't promise anything to the client yet.`  
  via groq · long; groq layout: sentences
- **nt-016** (positive, Reminders): layout≠list  
  said: `Defrost the chicken. Charge the camera.`  
  typed: `Defrost the chicken. Charge the camera.`  
  via groq · groq layout: sentences
- **nt-032** (negative, Reminders): layout≠paragraph; missing 'pet store'  
  said: `Stop by the pet store for cat litter, a scratching post and the salmon treats Luna likes`  
  typed: `- Cat litter ⏎ - A scratching post ⏎ - The salmon treats Luna likes`  
  via groq · restructured; long; no final punctuation; groq layout: list
- **sh-018** (positive, Terminal (shell)): missing 'dist/app.zip'; missing 'ubuntu@10.0.0.5:~'; has 'dot'; has 'colon'; has 'tilde'; has 'at'  
  said: `scp dist slash app dot zip ubuntu at 10 dot 0 dot 0 dot 5 colon tilde`  
  typed: `scp dist slash app dot zip ubuntu at 10 dot 0 dot 0 dot 5 colon tilde`  
  via fallback · repeated word; long; no final punctuation; groq layout: prompt; groq rejected: shrank 17->3 words; haiku layout: sentences; haiku rejected: shrank 17->3 words; fallback laid out as prompt
- **sh-024** (positive, Terminal (shell)): missing 'chmod 644 config/app.yaml'; has 'settings'; has 'I mean'  
  said: `So uh, chmod 644 config slash settings dot yaml, I mean, config slash app dot yaml`  
  typed: `So chmod 644 config slash settings dot yaml, I mean, config slash app dot yaml`  
  via fallback · hesitations; correction/filler phrase; long; no final punctuation; groq layout: prompt; groq correction: config/settings.yaml -> config/app.yaml; groq rejected: shrank 16->3 words; haiku layout: sentences; haiku correction: config/settings.yaml -> config/app.yaml; haiku rejected: shrank 16->3 words; fallback laid out as prompt

## Failures: groq (23)

- **ac-042** (positive, Claude desktop): layout≠list  
  said: `I'm making a meal plan for the week and my rules are: first, no red meat on weekdays, second, at least two fish dinners, third, nothing that takes more than 40 minutes, and fourth, um, my daughter won't eat anything spicy. Can you build the plan around those?`  
  typed: `I'm making a meal plan for the week, and my rules are: first, no red meat on weekdays; second, at least two fish dinners; third, nothing that takes more than 40 minutes; and fourth, my daughter won't eat anything spicy. Can you build the plan around those?`  
  via groq · hesitations; long; groq layout: sentences
- **ch-009** (positive, WhatsApp): missing 'white one'  
  said: `I I was gonna, um, I was gonna ask if you still have my charger, the the white one with the long cable, kinda need it rn cause my phone's on 4%, I left mine at the office again and the store downstairs is closed`  
  typed: `I was gonna ask if you still have my white charger with the long cable, kinda need it rn cause my phone's on 4%, I left mine at the office again and the store downstairs is closed.`  
  via groq · hesitations; long; no final punctuation; groq layout: sentences
- **ch-037** (positive, Discord): has 'eastern'  
  said: `um let's run the raid at uh 8:00 eastern, pacific, 8:00 pacific, people are still at work`  
  typed: `Let's run the raid at 8 Eastern, 8:00 Pacific; people are still at work.`  
  via groq · hesitations; repeated word; long; no final punctuation; groq layout: sentences
- **ch-054** (positive, Discord): layout≠list  
  said: `lol ok so before the lan party saturday, um here's what people still need to bring: extension cords, a spare monitor, the switch controllers, and snacks that aren't just chips this time. ngl last time was rough`  
  typed: `Lol ok so before the lan party saturday, here's what people still need to bring: extension cords, a spare monitor, the switch controllers, and snacks that aren't just chips this time. Ngl last time was rough`  
  via fallback · hesitations; long; no final punctuation; groq layout: list; groq rejected: dropped the ending: last time rough; fallback laid out as list
- **corr-003** (positive, Messages): missing 'traffic'  
  said: `I'll be there around eight, I mean nine, traffic is awful`  
  typed: `I'll be there around 9.`  
  via groq · correction/filler phrase; no final punctuation; groq layout: sentences; groq correction: eight -> nine
- **corr-015** (positive, Claude Code CLI in Terminal): has 'checkout'  
  said: `Look at the checkout page. No, the cart page. The remove button doesn't do anything on mobile.`  
  typed: `Goal: Look at the checkout page. ⏎ Context: No, the cart page. The remove button doesn't do anything on mobile.`  
  via fallback · restructured; long; groq layout: prompt; groq rejected: dropped words: anything, checkout, no; fallback laid out as prompt
- **corr-018** (positive, Slack): has 'staging'  
  said: `ping me when the staging, the production deploy finishes`  
  typed: `Ping me when the staging, the production deploy finishes.`  
  via groq · no final punctuation; groq layout: sentences
- **cx-049** (negative, VS Code): layout≠paragraph  
  said: `um can you just restart the dev server, I think it's still serving the old templates`  
  typed: `Goal: Can you just restart the dev server, I think it's still serving the old templates`  
  via fallback · restructured; hesitations; long; no final punctuation; groq layout: prompt; groq rejected: dropped words: old, serving, still, templates, think; fallback laid out as prompt
- **cx-053** (positive, Cursor): has 'blue'  
  said: `okay so the client looked at the mockup yesterday and they weren't happy with how heavy the whole top of the page really feels, so um make the header blue, or actually no, make it match the footer color, and drop the border`  
  typed: `Goal: Make it match the footer color, and drop the border ⏎ Context: Okay so the client looked at the mockup yesterday and they weren't happy with how heavy the whole top of the page really feels, so make the header blue, or actually no.`  
  via fallback · restructured; hesitations; correction/filler phrase; long; no final punctuation; groq layout: prompt; groq correction: make the header blue -> make it match the footer color; groq rejected: shrank 42->12 words; fallback laid out as prompt
- **cx-057** (positive, Codex app): has 'react-day-picker'  
  said: `So for the date picker, I'd like you to switch the library to react-day-picker, um, no, sorry, to the one we already use in the booking form, which is flatpickr I think, and keep the same props so the parent components don't change.`  
  typed: `Goal: So for the date picker, I'd like you to switch the library to react-day-picker, no, sorry, to the one we already use in the booking form, which is flatpickr I think. ⏎ Constraints: Keep the same props so the parent components. Don't change.`  
  via fallback · restructured; hesitations; correction/filler phrase; long; groq layout: prompt; groq correction: react-day-picker -> flatpickr; groq rejected: shrank 42->19 words; fallback laid out as prompt
- **cx-083** (positive, Claude Code CLI in Terminal): missing 'I guess'  
  said: `okay so, uh, the tile server, it's on version 3.4.2 and we can't go to 4 because of the license change, so, um, I guess just patch the memory leak on the 3.4 branch, and don't touch the renderer, I really don't want to re-test that`  
  typed: `Goal: Patch the memory leak on the 3.4 branch. ⏎ Context: The tile server is on version 3.4.2 and we can't upgrade to 4 because of the license change. ⏎ Constraints: Don't touch the renderer. I really don't want to re-test that.`  
  via groq · restructured; hesitations; long; no final punctuation; groq layout: prompt
- **em-020** (negative, Gmail in Chrome): missing 'thanks to the new intake process'  
  said: `thanks to the new intake process we saved a week per hire`  
  typed: `Thanks to the new interview process we saved a week per hire.`  
  via groq · groq repaired: intake process -> interview process; no final punctuation; groq layout: sentences
- **em-043** (positive, Mail): layout≠list  
  said: `Hi Ollie, before the camping trip please check three things: the tent poles are all there, the stove has gas, and the first aid kit is restocked. Also double check the torch batteries while you're at it. We leave at 7:00 on Saturday. Thanks, Fern`  
  typed: `Hi Ollie, ⏎  ⏎ Before the camping trip please check three things: the tent poles are all there, the stove has gas, and the first aid kit is restocked. Also double check the torch batteries while you're at it. We leave at 7:00 on Saturday. ⏎  ⏎ Thanks, ⏎ Fern`  
  via fallback · long; no final punctuation; groq layout: list; groq rejected: dropped words: before, fern, hi, ollie, thanks; fallback laid out as list
- **em-053** (positive, Mail): missing 'council'  
  said: `um, we can't confirm before the 14th, uh, the council's slow.`  
  typed: `We can't confirm before the 14th; the server's slow.`  
  via groq · groq repaired: council's -> server's; hesitations; groq layout: sentences
- **em-062** (negative, Mail): missing 'maybe'  
  said: `we might, maybe, be able to move the date, but please don't promise anything to the client yet.`  
  typed: `We might be able to move the date, but please don't promise anything to the client yet.`  
  via groq · long; groq layout: sentences
- **nt-016** (positive, Reminders): layout≠list  
  said: `Defrost the chicken. Charge the camera.`  
  typed: `Defrost the chicken. Charge the camera.`  
  via groq · groq layout: sentences
- **nt-025** (negative, Notes): layout≠paragraph  
  said: `I need to make a packing list for the wedding this weekend but I keep putting it off, maybe tonight after dinner.`  
  typed: `- I need to make a packing list for the wedding this weekend but I keep putting it off ⏎ - Maybe tonight after dinner`  
  via fallback · long; groq layout: sentences; groq rejected: dropped words: keep, off, putting; fallback laid out as sentences
- **nt-032** (negative, Reminders): layout≠paragraph; missing 'pet store'  
  said: `Stop by the pet store for cat litter, a scratching post and the salmon treats Luna likes`  
  typed: `- Cat litter ⏎ - A scratching post ⏎ - The salmon treats Luna likes`  
  via groq · restructured; long; no final punctuation; groq layout: list
- **sh-006** (positive, iTerm2 (shell)): missing 'rm -rf build'; has 'dash'  
  said: `rm dash rf build`  
  typed: `rm dash rf build`  
  via fallback · no final punctuation; groq layout: prompt; groq correction: dash -> -; groq rejected: reported a correction it didn't apply; fallback laid out as prompt
- **sh-012** (positive, iTerm2 (shell)): missing 'docker exec -it web sh'  
  said: `docker exec dash it web bash, actually make that sh`  
  typed: `docker exec dash it web sh`  
  via groq · correction/filler phrase; no final punctuation; groq layout: prompt; groq correction: bash -> sh
- **sh-018** (positive, Terminal (shell)): missing 'dist/app.zip'; missing 'ubuntu@10.0.0.5:~'; has 'dot'; has 'colon'; has 'tilde'; has 'at'  
  said: `scp dist slash app dot zip ubuntu at 10 dot 0 dot 0 dot 5 colon tilde`  
  typed: `scp dist slash app dot zip ubuntu at 10 dot 0 dot 0 dot 5 colon tilde`  
  via fallback · repeated word; long; no final punctuation; groq layout: prompt; groq rejected: shrank 17->3 words; fallback laid out as prompt
- **sh-023** (positive, Terminal (shell)): missing 'main...feature/search'; missing '--stat'; has 'dot'; has 'slash'; has 'dash'  
  said: `git diff main dot dot dot feature slash search dash dash stat`  
  typed: `git diff main dot dot dot feature slash search dash dash stat`  
  via fallback · repeated word; no final punctuation; groq layout: prompt; groq rejected: shrank 12->3 words; fallback laid out as prompt
- **sh-024** (positive, Terminal (shell)): missing 'chmod 644 config/app.yaml'; has 'settings'; has 'I mean'  
  said: `So uh, chmod 644 config slash settings dot yaml, I mean, config slash app dot yaml`  
  typed: `So chmod 644 config slash settings dot yaml, I mean, config slash app dot yaml`  
  via fallback · hesitations; correction/filler phrase; long; no final punctuation; groq layout: prompt; groq correction: config/settings.yaml -> config/app.yaml; groq rejected: shrank 16->3 words; fallback laid out as prompt

## Failures: haiku (16)

- **ac-042** (positive, Claude desktop): layout≠list  
  said: `I'm making a meal plan for the week and my rules are: first, no red meat on weekdays, second, at least two fish dinners, third, nothing that takes more than 40 minutes, and fourth, um, my daughter won't eat anything spicy. Can you build the plan around those?`  
  typed: `I'm making a meal plan for the week and my rules are: first, no red meat on weekdays; second, at least two fish dinners; third, nothing that takes more than 40 minutes; and fourth, my daughter won't eat anything spicy. Can you build the plan around those?`  
  via haiku · hesitations; long; haiku layout: prompt
- **ch-031** (positive, Messages): has 'Elm'  
  said: `the vet's on Elm Street, on Oak Street, by the bakery`  
  typed: `The vet's on Elm Street, on Oak Street, by the bakery`  
  via fallback · no final punctuation; haiku layout: sentences; haiku correction: Elm Street -> Oak Street; haiku rejected: reported a correction it didn't apply; fallback laid out as sentences
- **code-033** (negative, Claude Code CLI in Terminal): layout≠paragraph  
  said: `Okay, so the benchmark numbers came back. The new parser is about twice as fast on small files, but on the big ones it's actually slower, probably because of all the allocations.`  
  typed: `Goal: The benchmark numbers came back. ⏎ Context: The new parser is about twice as fast on small files, but on the big ones it's actually slower, probably because of all the allocations.`  
  via haiku · restructured; correction/filler phrase; long; haiku layout: prompt
- **code-055** (negative, Claude Code CLI in Ghostty): layout≠paragraph  
  said: `okay so I looked at the chart with real data and the y axis labels overlap when the numbers get big and the legend wraps onto three lines on mobile you could maybe abbreviate the numbers but honestly the bigger problem is the colors are hard to tell apart`  
  typed: `Goal: Okay so I looked at the chart with real data and the y axis labels overlap when the numbers get big and the legend wraps onto three lines on mobile you could maybe abbreviate the numbers but honestly the bigger problem is the colors are hard to tell apart`  
  via fallback · restructured; long; no final punctuation; haiku layout: prompt; haiku rejected: new words: fix, problems, readability; fallback laid out as prompt
- **corr-018** (positive, Slack): has 'staging'  
  said: `ping me when the staging, the production deploy finishes`  
  typed: `Ping me when the staging, the production deploy finishes.`  
  via haiku · no final punctuation; haiku layout: sentences
- **cx-025** (positive, Cursor): layout≠prompt; has 'you know'  
  said: `so the search box fires a request on every keystroke and the API is rate limiting us at like 10 per second so yeah debounce it by 300 milliseconds cancel the previous request with an abort controller and you know keep the loading spinner behavior the same and I'll check it in the network tab after`  
  typed: `So the search box fires a request on every keystroke and the API is rate limiting us at like 10 per second so yeah debounce it by 300 milliseconds cancel the previous request with an abort controller and you know keep the loading spinner behavior the same and I'll check it in the network tab after`  
  via fallback · correction/filler phrase; long; no final punctuation; haiku layout: prompt; haiku rejected: answered, not edited; fallback laid out as prompt
- **cx-040** (negative, Claude Code CLI in Ghostty): layout≠paragraph  
  said: `Okay so I ran the migration on a copy of prod. It took eleven minutes, two tables locked for about thirty seconds each, and the row counts match. I didn't see any errors in the logs, but I haven't tested the rollback yet.`  
  typed: `Goal: Report on the migration run and its results. ⏎ Context: I ran the migration on a copy of prod. It took 11 minutes, with two tables locked for about 30 seconds each. The row counts match. I didn't see any errors in the logs. ⏎ Constraints: I haven't tested the rollback yet.`  
  via haiku · restructured; long; haiku layout: prompt
- **cx-053** (positive, Cursor): has 'blue'  
  said: `okay so the client looked at the mockup yesterday and they weren't happy with how heavy the whole top of the page really feels, so um make the header blue, or actually no, make it match the footer color, and drop the border`  
  typed: `Goal: Make it match the footer color, and drop the border ⏎ Context: Okay so the client looked at the mockup yesterday and they weren't happy with how heavy the whole top of the page really feels, so make the header blue, or actually no.`  
  via fallback · restructured; hesitations; correction/filler phrase; long; no final punctuation; haiku layout: prompt; haiku correction: make the header blue, or actually no, make it match the footer color -> make it match the footer color; haiku rejected: reported a correction it didn't apply; fallback laid out as prompt
- **cx-054** (positive, VS Code): has 'staging registry'  
  said: `Okay so in the deploy script, add a step that tags the image with the git SHA, then pushes to the staging registry, wait, not staging, push it to the prod registry, but only after the smoke tests pass, and leave the rollback part as it is.`  
  typed: `Goal: Add a step that tags the image with the git SHA, then pushes to the staging registry, wait, not staging. ⏎ Tasks: ⏎ - Push it to the prod registry. ⏎ Context: Okay so in the deploy script. ⏎ Constraints: Only after the smoke tests pass, and leave the rollback part as it is.`  
  via fallback · restructured; long; haiku layout: prompt; haiku correction: staging registry -> prod registry; haiku rejected: new words: corrected, first, said, speaker; fallback laid out as prompt
- **cx-057** (positive, Codex app): has 'react-day-picker'  
  said: `So for the date picker, I'd like you to switch the library to react-day-picker, um, no, sorry, to the one we already use in the booking form, which is flatpickr I think, and keep the same props so the parent components don't change.`  
  typed: `Goal: So for the date picker, I'd like you to switch the library to react-day-picker, no, sorry, to the one we already use in the booking form, which is flatpickr I think. ⏎ Constraints: Keep the same props so the parent components. Don't change.`  
  via fallback · restructured; hesitations; correction/filler phrase; long; haiku layout: prompt; haiku correction: react-day-picker -> flatpickr; haiku rejected: reported a correction it didn't apply; fallback laid out as prompt
- **cx-083** (positive, Claude Code CLI in Terminal): missing 'I guess'  
  said: `okay so, uh, the tile server, it's on version 3.4.2 and we can't go to 4 because of the license change, so, um, I guess just patch the memory leak on the 3.4 branch, and don't touch the renderer, I really don't want to re-test that`  
  typed: `Goal: Patch the memory leak on the 3.4 branch of the tile server. ⏎ Context: The tile server is on version 3.4.2. We can't go to 4 because of the license change. ⏎ Constraints: Don't touch the renderer. I really don't want to re-test that.`  
  via haiku · restructured; hesitations; long; no final punctuation; haiku layout: prompt
- **em-053** (positive, Mail): missing 'council'  
  said: `um, we can't confirm before the 14th, uh, the council's slow.`  
  typed: `We can't confirm before the 14th; the council's slow.`  
  via haiku · hesitations; haiku layout: sentences
- **nt-016** (positive, Reminders): layout≠list  
  said: `Defrost the chicken. Charge the camera.`  
  typed: `Defrost the chicken. Charge the camera.`  
  via haiku · haiku layout: sentences
- **nt-033** (negative, Reminders): layout≠paragraph  
  said: `remind me to ask the landlord about fixing the dishwasher the bathroom fan and the porch light when he comes by on monday`  
  typed: `Remind me to ask the landlord about: ⏎ - Fixing the dishwasher ⏎ - The bathroom fan ⏎ - The porch light ⏎  ⏎ When he comes by on Monday.`  
  via haiku · restructured; long; no final punctuation; haiku layout: list
- **sh-018** (positive, Terminal (shell)): missing 'dist/app.zip'; missing 'ubuntu@10.0.0.5:~'; has 'dot'; has 'colon'; has 'tilde'; has 'at'  
  said: `scp dist slash app dot zip ubuntu at 10 dot 0 dot 0 dot 5 colon tilde`  
  typed: `scp dist slash app dot zip ubuntu at 10 dot 0 dot 0 dot 5 colon tilde`  
  via fallback · repeated word; long; no final punctuation; haiku layout: sentences; haiku rejected: shrank 17->3 words; fallback laid out as sentences
- **sh-024** (positive, Terminal (shell)): missing 'chmod 644 config/app.yaml'; has 'settings'; has 'I mean'  
  said: `So uh, chmod 644 config slash settings dot yaml, I mean, config slash app dot yaml`  
  typed: `So chmod 644 config slash settings dot yaml, I mean, config slash app dot yaml`  
  via fallback · hesitations; correction/filler phrase; long; no final punctuation; haiku layout: sentences; haiku correction: config/settings.yaml -> config/app.yaml; haiku rejected: shrank 16->3 words; fallback laid out as sentences
