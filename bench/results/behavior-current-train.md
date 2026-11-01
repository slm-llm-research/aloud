# Behavior eval: current (train)

| | app | groq | haiku |
|---|---|---|---|
| all | 94% (250/267) | 91% (242/267) | 96% (256/267) |
| ai_chat | 100% (19/19) | 100% (19/19) | 100% (19/19) |
| &nbsp;&nbsp;positive | 100% (12/12) | 100% (12/12) | 100% (12/12) |
| &nbsp;&nbsp;negative | 100% (7/7) | 100% (7/7) | 100% (7/7) |
| chat | 83% (15/18) | 89% (16/18) | 94% (17/18) |
| &nbsp;&nbsp;positive | 80% (8/10) | 80% (8/10) | 90% (9/10) |
| &nbsp;&nbsp;negative | 88% (7/8) | 100% (8/8) | 100% (8/8) |
| email | 95% (19/20) | 95% (19/20) | 95% (19/20) |
| &nbsp;&nbsp;positive | 92% (11/12) | 92% (11/12) | 92% (11/12) |
| &nbsp;&nbsp;negative | 100% (8/8) | 100% (8/8) | 100% (8/8) |
| fidelity | 91% (20/22) | 91% (20/22) | 95% (21/22) |
| &nbsp;&nbsp;positive | 86% (12/14) | 86% (12/14) | 93% (13/14) |
| &nbsp;&nbsp;negative | 100% (8/8) | 100% (8/8) | 100% (8/8) |
| list_vs_sentences | 91% (48/53) | 83% (44/53) | 98% (52/53) |
| &nbsp;&nbsp;positive | 85% (22/26) | 69% (18/26) | 100% (26/26) |
| &nbsp;&nbsp;negative | 96% (26/27) | 96% (26/27) | 96% (26/27) |
| misheard | 94% (17/18) | 94% (17/18) | 94% (17/18) |
| &nbsp;&nbsp;positive | 89% (8/9) | 89% (8/9) | 100% (9/9) |
| &nbsp;&nbsp;negative | 100% (9/9) | 100% (9/9) | 89% (8/9) |
| prompt_vs_speech | 98% (40/41) | 98% (40/41) | 100% (41/41) |
| &nbsp;&nbsp;positive | 100% (20/20) | 100% (20/20) | 100% (20/20) |
| &nbsp;&nbsp;negative | 95% (20/21) | 95% (20/21) | 100% (21/21) |
| self_correction | 93% (51/55) | 85% (47/55) | 89% (49/55) |
| &nbsp;&nbsp;positive | 91% (29/32) | 81% (26/32) | 81% (26/32) |
| &nbsp;&nbsp;negative | 96% (22/23) | 91% (21/23) | 100% (23/23) |
| terminal | 100% (21/21) | 95% (20/21) | 100% (21/21) |
| &nbsp;&nbsp;positive | 100% (12/12) | 92% (11/12) | 100% (12/12) |
| &nbsp;&nbsp;negative | 100% (9/9) | 100% (9/9) | 100% (9/9) |
| app: ai_apps | 100% (33/33) | 97% (32/33) | 94% (31/33) |
| app: chat_apps | 94% (60/64) | 92% (59/64) | 97% (62/64) |
| app: claude_code | 97% (32/33) | 94% (31/33) | 97% (32/33) |
| app: codex | 100% (9/9) | 100% (9/9) | 89% (8/9) |
| app: editor | 95% (19/20) | 95% (19/20) | 100% (20/20) |
| app: email_apps | 89% (34/38) | 82% (31/38) | 95% (36/38) |
| app: notes | 91% (30/33) | 88% (29/33) | 97% (32/33) |
| app: terminal | 95% (21/22) | 91% (20/22) | 95% (21/22) |
| app: todo | 80% (12/15) | 80% (12/15) | 93% (14/15) |
| difficulty: easy | 97% (138/143) | 95% (136/143) | 98% (140/143) |
| difficulty: hard | 90% (112/124) | 85% (106/124) | 94% (116/124) |
| difficulty+polarity: easy negative | 100% (60/60) | 100% (60/60) | 100% (60/60) |
| difficulty+polarity: easy positive | 94% (78/83) | 92% (76/83) | 96% (80/83) |
| difficulty+polarity: hard negative | 93% (56/60) | 93% (56/60) | 97% (58/60) |
| difficulty+polarity: hard positive | 88% (56/64) | 78% (50/64) | 91% (58/64) |
| length: long | 85% (52/61) | 75% (46/61) | 93% (57/61) |
| length: medium | 95% (116/122) | 94% (115/122) | 96% (117/122) |
| length: short | 98% (82/84) | 96% (81/84) | 98% (82/84) |
| polarity: negative | 97% (116/120) | 97% (116/120) | 98% (118/120) |
| polarity: positive | 91% (134/147) | 86% (126/147) | 94% (138/147) |

Latency p50 / p95 (ms): app 505 / 1256, groq 528 / 992, haiku 1579 / 2192

## Failures: app (17)

- **ch-011** (positive, Discord): missing 'joever'; has 'so over'  
  said: `bruh uh the patch nerfed my main into the ground, it's so joever`  
  typed: `Bruh, the patch nerfed my main into the ground, it's so over.`  
  via groq · groq repaired: joever -> over; hesitations; no final punctuation; groq layout: sentences
- **ch-025** (negative, WhatsApp): missing 'tmrw'; has 'tomorrow'  
  said: `Okay so update: landed, got my bag, and the hotel shuttle is nowhere to be found lol. Gonna grab a cab instead and hopefully be there by 11:30. If you're still up later lmk and I'll call, otherwise talk tmrw. Tell the kids I said night and that I miss them.`  
  typed: `Okay, so I landed, got my bag, and the hotel shuttle is nowhere to be found lol. Gonna grab a cab instead and hopefully be there by 11:30. If you're still up later, lmk and I'll call; otherwise, talk tomorrow. Tell the kids I said night and that I miss them.`  
  via groq · long; groq layout: sentences
- **ch-067** (positive, Messages): missing 'internet'  
  said: `uh rent's $1,450 this month, um I'll venmo you my half by the 3rd, and the internet's still split three ways like we said. Lmk if that math looks off to you, I did it in my head on the train.`  
  typed: `Rent's $1,450 this month, I'll venmo you my half by the 3rd, and the internet's still split three ways like we said. Lmk if that math looks off to you, I did it in my head on the train.`  
  via groq · hesitations; long; groq layout: sentences
- **chat-004** (positive, WhatsApp): missing 'yeah nah'  
  said: `yeah nah I'm not feeling the beach tomorrow, uh it's meant to rain all day tbh`  
  typed: `I'm not feeling the beach tomorrow; it's meant to rain all day, tbh.`  
  via groq · hesitations; long; no final punctuation; groq layout: sentences
- **code-049** (negative, Cursor): layout≠paragraph  
  said: `this function wraps the user question as a prompt for the classifier, and I think the bug is that it drops the conversation history`  
  typed: `Goal: This function wraps the user question as a prompt for the classifier, and I think the bug is that it drops the conversation history.`  
  via groq · long; no final punctuation; groq layout: prompt
- **corr-014** (positive, Notes): layout≠paragraph; missing 'baking'  
  said: `gift for mom. a scarf. no, a cookbook. she's been getting really into baking`  
  typed: `Gift for mom: ⏎ - Cookbook`  
  via groq · long; no final punctuation; groq layout: list; groq correction: scarf -> cookbook
- **cx-070** (positive, Claude Code CLI in Terminal): missing 'async'; missing 'don't'; has 'a sink'  
  said: `okay so I was profiling the checkout flow this morning and I noticed that the handler is blocking the event loop because it's not a sink, so make fetch inventory a sink and await the database call, and don't change the return type`  
  typed: `Goal: Make `fetchInventory` a sink and await the database call. ⏎ Context: While profiling the checkout flow, I noticed that the handler is blocking the event loop because it's not a sink. ⏎ Constraints: Do not change the return type.`  
  via groq · restructured; long; no final punctuation; groq layout: prompt
- **em-018** (positive, Mail): missing 'I'm frank'  
  said: `Dear Frank, I'm frank, I didn't expect the renovation to run this long. The builder mentioned the tiles are back-ordered, but nobody told us until yesterday. Could we meet on site Monday to agree a new finish date? Yours sincerely, Imogen`  
  typed: `Dear Frank, ⏎  ⏎ I'm Imogen. I didn't expect the renovation to run this long. The builder mentioned the tiles are back-ordered, but nobody told us until yesterday. Could we meet on site Monday to agree on a new finish date? Yours sincerely, Imogen`  
  via groq · groq repaired: I'm frank -> I'm Imogen; long; no final punctuation; groq layout: sentences
- **em-034** (positive, Mail): has 'the cathedral at'  
  said: `Hey Marta, the walking tour starts at the cathedral at 9:00. Bring water and good shoes. Actually, scratch the cathedral, we're meeting at the fountain in the main square, the cathedral steps are closed for filming. See you on Sunday, Luis`  
  typed: `Hey Marta, ⏎  ⏎ The walking tour starts at the cathedral at 9:00. Bring water and good shoes. Actually, scratch the cathedral, we're meeting at the fountain in the main square, the cathedral steps are closed for filming. See you on Sunday, Luis`  
  via fallback · correction/filler phrase; long; no final punctuation; groq layout: sentences; groq correction: cathedral -> fountain in the main square; groq rejected: reported a correction it didn't apply; haiku layout: sentences; haiku correction: the cathedral -> the fountain in the main square; haiku rejected: reported a correction it didn't apply; fallback laid out as sentences
- **em-042** (negative, Outlook): missing 'no one objected'  
  said: `We considered moving the offsite to Lisbon, no one objected at first, but then the flight costs came in higher than budgeted, so for now we're sticking with Porto. Sorry, I know some of you were excited about Lisbon. The agenda and hotel details will follow next week.`  
  typed: `We considered moving the offsite to Lisbon, but then the flight costs came in higher than budgeted, so for now we're sticking with Porto. Sorry, I know some of you were excited about Lisbon. The agenda and hotel details will follow next week.`  
  via groq · correction/filler phrase; long; groq layout: sentences
- **em-046** (positive, Outlook): layout≠list  
  said: `Hi Rafael, um, ahead of the audit next month, could you check the following for your team. Uh, first, that everyone has completed the data protection training. Second, that shared drives don't have any customer files outside the restricted folder. And third, that laptops have the latest security update installed. Let me know by the 15th if anything's outstanding. Best, Joanne`  
  typed: `Hi Rafael, ⏎  ⏎ Ahead of the audit next month, could you check the following for your team: first, that everyone has completed the data protection training; second, that shared drives don't have any customer files outside the restricted folder; and third, that laptops have the latest security update installed. Let me know by the 15th if anything's outstanding. ⏎  ⏎ Best, ⏎ Joanne`  
  via groq · hesitations; long; no final punctuation; groq layout: sentences
- **list-005** (positive, Notes): layout≠list  
  said: `To reset the router, first unplug it from the wall, then wait 30 seconds, then plug it back in, and finally hold the reset button until the light blinks.`  
  typed: `To reset the router, first unplug it from the wall, then wait 30 seconds, then plug it back in, and finally hold the reset button until the light blinks.`  
  via groq · long; groq layout: sentences
- **list-017** (positive, Reminders): layout≠list  
  said: `Um, call the vet about Bella's shots, pick up the dry cleaning, and email the landlord about the heater.`  
  typed: `Call the vet about Bella's shots, pick up the dry cleaning, and email the landlord about the heater.`  
  via groq · hesitations; long; groq layout: sentences
- **nt-021** (positive, Things): layout≠list  
  said: `so for the website relaunch I need to like write the about page get new headshots fix the broken contact form and set up redirects for all the old blog posts so we don't lose the search traffic we already have from them`  
  typed: `So for the website relaunch I need to write the about page, get new headshots, fix the broken contact form, and set up redirects for all the old blog posts so we don't lose the search traffic we already have from them.`  
  via groq · long; no final punctuation; groq layout: sentences
- **nt-026** (negative, Reminders): missing 'Friday'  
  said: `Ask Gabriel to put me on the guest list for Friday's show`  
  typed: `Ask Gabriel to put me on the guest list for Friday's show.`  
  via groq · no final punctuation; groq layout: sentences
- **nt-064** (positive, Notes): missing 'probably'  
  said: `I think maybe we could probably afford the bigger apartment if we, uh, if we don't buy a second car this year, and if my raise actually comes through in June, but I don't want to stretch the budget so thin that we can't save anything for the trip`  
  typed: `I think maybe we could afford the bigger apartment if we don't buy a second car this year, and if my raise actually comes through in June, but I don't want to stretch the budget so thin that we can't save anything for the trip.`  
  via groq · hesitations; correction/filler phrase; long; no final punctuation; groq layout: sentences
- **sh-013** (positive, Terminal (shell)): missing 'cd /var/tmp'; has 'log'; has 'sorry'  
  said: `Um, cd slash var slash log, sorry, slash var slash tmp.`  
  typed: `cd slash var slash log, sorry, slash var slash tmp`  
  via fallback · hesitations; correction/filler phrase; groq layout: prompt; groq correction: /var/log -> /var/tmp; groq rejected: shrank 11->2 words; haiku layout: sentences; haiku correction: slash var slash log -> slash var slash tmp; haiku rejected: shrank 11->2 words; fallback laid out as prompt

## Failures: groq (25)

- **ch-010** (positive, Slack): missing 'super cursed'  
  said: `um ok so ngl the backfill job is being super cursed today, uh it keeps timing out on the biggest tenant, so I'm gonna split it into batches of 500 and rerun tonight, um no action needed from you all rn, just fyi`  
  typed: `Ok, ngl the backfill job is being cursed today, it keeps timing out on the biggest tenant, so I'm gonna split it into batches of 500 and rerun tonight, no action needed from you all rn, just fyi.`  
  via groq · hesitations; long; no final punctuation; groq layout: sentences
- **ch-011** (positive, Discord): missing 'joever'; has 'so over'  
  said: `bruh uh the patch nerfed my main into the ground, it's so joever`  
  typed: `Bruh, the patch nerfed my main into the ground, it's so over.`  
  via groq · groq repaired: joever -> over; hesitations; no final punctuation; groq layout: sentences
- **ch-030** (positive, WhatsApp): has 'matinee'; has 'scratch that'  
  said: `Can you get two tickets for the matinee, scratch that, the evening show, Sara wants to come after work and she can't leave before 5. Get them on my card and I'll sort out the money with her later, she always pays me back.`  
  typed: `Can you get two tickets for the matinee, scratch that, the evening show, Sara wants to come after work and she can't leave before 5. Get them on my card and I'll sort out the money with her later, she always pays me back.`  
  via fallback · correction/filler phrase; long; groq layout: sentences; groq correction: two tickets for the matinee -> two tickets for the evening show; groq rejected: reported a correction it didn't apply; fallback laid out as sentences
- **ch-046** (negative, WhatsApp): missing 'Sorry'  
  said: `Sorry for the late reply, work's been insane. Yes to Saturday! I'll bring the speaker. Oh and also my cousin Ana might tag along if that's ok, she's in town for the week. Oh and I can drive if you need, I've got the big car this weekend.`  
  typed: `Yes to Saturday! I'll bring the speaker. My cousin Ana might tag along if that's ok, she's in town for the week. I can drive if you need; I've got the big car this weekend.`  
  via groq · correction/filler phrase; long; groq layout: sentences
- **ch-067** (positive, Messages): missing 'internet'  
  said: `uh rent's $1,450 this month, um I'll venmo you my half by the 3rd, and the internet's still split three ways like we said. Lmk if that math looks off to you, I did it in my head on the train.`  
  typed: `Rent's $1,450 this month, I'll venmo you my half by the 3rd, and the internet's still split three ways like we said. Lmk if that math looks off to you, I did it in my head on the train.`  
  via groq · hesitations; long; groq layout: sentences
- **code-049** (negative, Cursor): layout≠paragraph  
  said: `this function wraps the user question as a prompt for the classifier, and I think the bug is that it drops the conversation history`  
  typed: `Goal: This function wraps the user question as a prompt for the classifier, and I think the bug is that it drops the conversation history.`  
  via groq · long; no final punctuation; groq layout: prompt
- **corr-014** (positive, Notes): layout≠paragraph; missing 'baking'  
  said: `gift for mom. a scarf. no, a cookbook. she's been getting really into baking`  
  typed: `Gift for mom: ⏎ - A cookbook`  
  via groq · long; no final punctuation; groq layout: list; groq correction: scarf -> cookbook
- **corr-028** (positive, Claude Code CLI in Terminal): has 'checkout'  
  said: `um so in the checkout service, uh, scratch that, in the inventory service, the stock count goes negative when two orders come in at once, can you add a lock`  
  typed: `Goal: So in the checkout service, scratch that, in the inventory service, the stock count goes negative when two orders come in at once, can you add a lock`  
  via fallback · restructured; hesitations; correction/filler phrase; long; no final punctuation; groq layout: prompt; groq correction: checkout service -> inventory service; groq rejected: dropped words: come, goes, once, orders, two; fallback laid out as prompt
- **corr-032** (positive, Claude desktop): has 'fifty'  
  said: `I'm planning a vegetarian dinner for six people, one of them is gluten free and another doesn't like mushrooms. Can you suggest a main dish, a side, and a dessert that I can mostly make ahead, and keep the budget under fifty dollars, actually under forty.`  
  typed: `I'm planning a vegetarian dinner for six people, one of them is gluten free and another doesn't like mushrooms. Can you suggest a main dish, a side, and a dessert that I can mostly make ahead, and keep the budget under fifty dollars, actually under forty.`  
  via fallback · correction/filler phrase; long; groq layout: sentences; groq correction: under fifty dollars -> under forty dollars; groq rejected: reported a correction it didn't apply; fallback laid out as sentences
- **cx-070** (positive, Claude Code CLI in Terminal): missing 'async'; missing 'don't'; has 'a sink'  
  said: `okay so I was profiling the checkout flow this morning and I noticed that the handler is blocking the event loop because it's not a sink, so make fetch inventory a sink and await the database call, and don't change the return type`  
  typed: `Goal: Make `fetchInventory` a sink and await the database call. ⏎ Context: While profiling the checkout flow, I noticed that the handler is blocking the event loop because it's not a sink. ⏎ Constraints: Do not change the return type.`  
  via groq · restructured; groq repair refused: a sink -> async (ambiguous); groq repair refused: make fetch inventory a sink -> make fetch inventory async (size); long; no final punctuation; groq layout: prompt
- **em-018** (positive, Mail): missing 'I'm frank'  
  said: `Dear Frank, I'm frank, I didn't expect the renovation to run this long. The builder mentioned the tiles are back-ordered, but nobody told us until yesterday. Could we meet on site Monday to agree a new finish date? Yours sincerely, Imogen`  
  typed: `Dear Frank, ⏎  ⏎ I'm Imogen. I didn't expect the renovation to run this long. The builder mentioned the tiles are back-ordered, but nobody told us until yesterday. Could we meet on site Monday to agree on a new finish date? Yours sincerely, Imogen`  
  via groq · groq repaired: I'm frank -> I'm Imogen; long; no final punctuation; groq layout: sentences
- **em-034** (positive, Mail): has 'the cathedral at'  
  said: `Hey Marta, the walking tour starts at the cathedral at 9:00. Bring water and good shoes. Actually, scratch the cathedral, we're meeting at the fountain in the main square, the cathedral steps are closed for filming. See you on Sunday, Luis`  
  typed: `Hey Marta, ⏎  ⏎ The walking tour starts at the cathedral at 9:00. Bring water and good shoes. Actually, scratch the cathedral, we're meeting at the fountain in the main square, the cathedral steps are closed for filming. See you on Sunday, Luis`  
  via fallback · correction/filler phrase; long; no final punctuation; groq layout: sentences; groq correction: cathedral -> fountain in the main square; groq rejected: reported a correction it didn't apply; fallback laid out as sentences
- **em-042** (negative, Outlook): missing 'no one objected'  
  said: `We considered moving the offsite to Lisbon, no one objected at first, but then the flight costs came in higher than budgeted, so for now we're sticking with Porto. Sorry, I know some of you were excited about Lisbon. The agenda and hotel details will follow next week.`  
  typed: `We considered moving the offsite to Lisbon, but then the flight costs came in higher than budgeted, so for now we're sticking with Porto. Sorry, I know some of you were excited about Lisbon. The agenda and hotel details will follow next week.`  
  via groq · correction/filler phrase; long; groq layout: sentences
- **em-044** (positive, Outlook): layout≠list  
  said: `hello team, for the quarter end close please do the following. one, reconcile the bank accounts. two, review open purchase orders. three, submit expense reports by Thursday. four, update the accruals spreadsheet in the shared drive. please reach out if anything's blocked. regards, Mina`  
  typed: `Hello team, ⏎  ⏎ For the quarter end close please do the following. One, reconcile the bank accounts. Two, review open purchase orders. Three, submit expense reports by Thursday. Four, update the accruals spreadsheet in the shared drive. Please reach out if anything's blocked. ⏎  ⏎ Regards, ⏎ Mina`  
  via fallback · long; no final punctuation; groq layout: list; groq rejected: dropped words: anything, blocked, following, four, hello; fallback laid out as list
- **em-045** (positive, Gmail in Chrome): layout≠list  
  said: `hey Dom um so for the house sitting this week can you water the tomatoes every evening feed the cat twice a day put the bins out on Tuesday night and keep the back door locked please thanks so much Ivy`  
  typed: `Hey Dom, ⏎  ⏎ So for the house sitting this week can you water the tomatoes every evening feed the cat twice a day put the bins out on Tuesday night and keep the back door locked please thanks so much Ivy`  
  via fallback · hesitations; long; no final punctuation; groq layout: list; groq rejected: dropped words: dom, hey, ivy, much, thanks; fallback laid out as list
- **em-046** (positive, Outlook): layout≠list  
  said: `Hi Rafael, um, ahead of the audit next month, could you check the following for your team. Uh, first, that everyone has completed the data protection training. Second, that shared drives don't have any customer files outside the restricted folder. And third, that laptops have the latest security update installed. Let me know by the 15th if anything's outstanding. Best, Joanne`  
  typed: `Hi Rafael, ⏎  ⏎ Ahead of the audit next month, could you check the following for your team: first, that everyone has completed the data protection training; second, that shared drives don't have any customer files outside the restricted folder; and third, that laptops have the latest security update installed. Let me know by the 15th if anything's outstanding. ⏎  ⏎ Best, ⏎ Joanne`  
  via groq · hesitations; long; no final punctuation; groq layout: sentences
- **list-005** (positive, Notes): layout≠list  
  said: `To reset the router, first unplug it from the wall, then wait 30 seconds, then plug it back in, and finally hold the reset button until the light blinks.`  
  typed: `To reset the router, first unplug it from the wall, then wait 30 seconds, then plug it back in, and finally hold the reset button until the light blinks.`  
  via groq · long; groq layout: sentences
- **list-017** (positive, Reminders): layout≠list  
  said: `Um, call the vet about Bella's shots, pick up the dry cleaning, and email the landlord about the heater.`  
  typed: `Call the vet about Bella's shots, pick up the dry cleaning, and email the landlord about the heater.`  
  via groq · hesitations; long; groq layout: sentences
- **list-025** (positive, Mail): layout≠list  
  said: `Hi team, here are the things to bring to the offsite. Your laptop and charger, a photo ID for the building, comfortable shoes for the hike, and a water bottle. Thanks, Priya.`  
  typed: `Hi team, ⏎  ⏎ Here are the things to bring to the offsite. Your laptop and charger, a photo ID for the building, comfortable shoes for the hike, and a water bottle. ⏎  ⏎ Thanks, ⏎ Priya`  
  via fallback · long; groq layout: list; groq rejected: dropped words: hi, offsite, priya, team, thanks; fallback laid out as list
- **nt-006** (positive, Notes): layout≠list  
  said: `How to bleed the radiator. Turn off the heating and let it cool down. Put a cloth under the valve. Turn the key a quarter turn until it starts hissing. Close it again as soon as water comes out. Then go downstairs and check the boiler pressure, it should be somewhere between one and one and a half bar.`  
  typed: `How to bleed the radiator: turn off the heating and let it cool down. Put a cloth under the valve. Turn the key a quarter turn until it starts hissing. Close it again as soon as water comes out. Then go downstairs and check the boiler pressure; it should be between 1 and 1.5 bar.`  
  via groq · groq repair refused: one and one and a half bar -> one and a half bar (size); long; groq layout: sentences
- **nt-021** (positive, Things): layout≠list  
  said: `so for the website relaunch I need to like write the about page get new headshots fix the broken contact form and set up redirects for all the old blog posts so we don't lose the search traffic we already have from them`  
  typed: `So for the website relaunch I need to write the about page, get new headshots, fix the broken contact form, and set up redirects for all the old blog posts so we don't lose the search traffic we already have from them.`  
  via groq · long; no final punctuation; groq layout: sentences
- **nt-026** (negative, Reminders): missing 'Friday'  
  said: `Ask Gabriel to put me on the guest list for Friday's show`  
  typed: `Ask Gabriel to put me on the guest list for Friday's show.`  
  via groq · no final punctuation; groq layout: sentences
- **nt-064** (positive, Notes): missing 'probably'  
  said: `I think maybe we could probably afford the bigger apartment if we, uh, if we don't buy a second car this year, and if my raise actually comes through in June, but I don't want to stretch the budget so thin that we can't save anything for the trip`  
  typed: `I think maybe we could afford the bigger apartment if we don't buy a second car this year and if my raise actually comes through in June, but I don't want to stretch the budget so thin that we can't save anything for the trip.`  
  via groq · hesitations; correction/filler phrase; long; no final punctuation; groq layout: sentences
- **sh-013** (positive, Terminal (shell)): missing 'cd /var/tmp'; has 'log'; has 'sorry'  
  said: `Um, cd slash var slash log, sorry, slash var slash tmp.`  
  typed: `cd slash var slash log, sorry, slash var slash tmp`  
  via fallback · hesitations; correction/filler phrase; groq layout: prompt; groq correction: /var/log -> /var/tmp; groq rejected: shrank 11->2 words; fallback laid out as prompt
- **term-005** (positive, Terminal (shell)): missing 'grep -rn fixme lib'  
  said: `grep dash rn fixme lib`  
  typed: `grep -r -n fixme lib`  
  via groq · no final punctuation; groq layout: prompt

## Failures: haiku (11)

- **ac-036** (positive, ChatGPT in Chrome): has 'dumbbells'  
  said: `Give me a 20 minute workout I can do at home with dumbbells, actually without any equipment, just bodyweight.`  
  typed: `Give me a 20 minute workout I can do at home with dumbbells, actually without any equipment, just bodyweight.`  
  via fallback · correction/filler phrase; long; haiku layout: prompt; haiku correction: with dumbbells, actually without any equipment -> with bodyweight only, no equipment; haiku rejected: negation changed 0->1; fallback laid out as prompt
- **ch-067** (positive, Messages): missing 'internet'  
  said: `uh rent's $1,450 this month, um I'll venmo you my half by the 3rd, and the internet's still split three ways like we said. Lmk if that math looks off to you, I did it in my head on the train.`  
  typed: `Rent's $1,450 this month, I'll Venmo you my half by the 3rd, and the internet's still split three ways like we said. Lmk if that math looks off to you, I did it in my head on the train.`  
  via haiku · hesitations; long; haiku layout: sentences
- **chat-005** (positive, Slack): missing 'tho'  
  said: `um can you like take a quick look at my PR when you get a sec, no rush tho`  
  typed: `Can you take a quick look at my PR when you get a sec, no rush though?`  
  via haiku · hesitations; long; no final punctuation; haiku layout: sentences
- **corr-007** (positive, Codex app): has 'user'; has 'scratch that'  
  said: `Add a retry to the fetch user function, scratch that, add it to the fetch orders function, with three attempts max.`  
  typed: `Add a retry to the fetch user function, scratch that, add it to the fetch orders function, with three attempts max.`  
  via fallback · correction/filler phrase; long; haiku layout: sentences; haiku correction: the fetch user function, scratch that, add it to the fetch orders function -> the fetch orders function; haiku rejected: reported a correction it didn't apply; fallback laid out as sentences
- **corr-028** (positive, Claude Code CLI in Terminal): has 'checkout'  
  said: `um so in the checkout service, uh, scratch that, in the inventory service, the stock count goes negative when two orders come in at once, can you add a lock`  
  typed: `Goal: So in the checkout service, scratch that, in the inventory service, the stock count goes negative when two orders come in at once, can you add a lock`  
  via fallback · restructured; hesitations; correction/filler phrase; long; no final punctuation; haiku layout: prompt; haiku correction: checkout service -> inventory service; haiku rejected: new words: doesn, go, same, time; fallback laid out as prompt
- **corr-032** (positive, Claude desktop): has 'fifty'  
  said: `I'm planning a vegetarian dinner for six people, one of them is gluten free and another doesn't like mushrooms. Can you suggest a main dish, a side, and a dessert that I can mostly make ahead, and keep the budget under fifty dollars, actually under forty.`  
  typed: `I'm planning a vegetarian dinner for six people, one of them is gluten free and another doesn't like mushrooms. Can you suggest a main dish, a side, and a dessert that I can mostly make ahead, and keep the budget under fifty dollars, actually under forty.`  
  via fallback · correction/filler phrase; long; haiku layout: prompt; haiku correction: $50 -> $40; haiku rejected: reported a correction it didn't apply; fallback laid out as prompt
- **em-018** (positive, Mail): missing 'I'm frank'  
  said: `Dear Frank, I'm frank, I didn't expect the renovation to run this long. The builder mentioned the tiles are back-ordered, but nobody told us until yesterday. Could we meet on site Monday to agree a new finish date? Yours sincerely, Imogen`  
  typed: `Dear Frank, ⏎  ⏎ I didn't expect the renovation to run this long. The builder mentioned the tiles are back-ordered, but nobody told us until yesterday. Could we meet on site Monday to agree a new finish date? ⏎  ⏎ Yours sincerely, ⏎ Imogen`  
  via haiku · haiku repair refused: I'm frank -> I'm Frank (size); long; no final punctuation; haiku layout: sentences
- **em-034** (positive, Mail): has 'the cathedral at'  
  said: `Hey Marta, the walking tour starts at the cathedral at 9:00. Bring water and good shoes. Actually, scratch the cathedral, we're meeting at the fountain in the main square, the cathedral steps are closed for filming. See you on Sunday, Luis`  
  typed: `Hey Marta, ⏎  ⏎ The walking tour starts at the cathedral at 9:00. Bring water and good shoes. Actually, scratch the cathedral, we're meeting at the fountain in the main square, the cathedral steps are closed for filming. See you on Sunday, Luis`  
  via fallback · correction/filler phrase; long; no final punctuation; haiku layout: sentences; haiku correction: the cathedral -> the fountain in the main square; haiku rejected: reported a correction it didn't apply; fallback laid out as sentences
- **nt-026** (negative, Reminders): missing 'Friday'  
  said: `Ask Gabriel to put me on the guest list for Friday's show`  
  typed: `Ask Gabriel to put me on the guest list for Friday's show.`  
  via haiku · no final punctuation; haiku layout: sentences
- **nt-074** (negative, Notes): missing 'knight scene'; has 'night scene'  
  said: `Rehearsal notes, the knight scene drags, Eli needs to come in earlier on the sword fight`  
  typed: `Rehearsal notes: the night scene drags. Eli needs to come in earlier on the sword fight.`  
  via haiku · haiku repaired: the knight scene -> the night scene; long; no final punctuation; haiku layout: sentences
- **sh-013** (positive, Terminal (shell)): missing 'cd /var/tmp'; has 'log'; has 'sorry'  
  said: `Um, cd slash var slash log, sorry, slash var slash tmp.`  
  typed: `cd slash var slash log, sorry, slash var slash tmp`  
  via fallback · hesitations; correction/filler phrase; haiku layout: sentences; haiku correction: slash var slash log -> slash var slash tmp; haiku rejected: shrank 11->2 words; fallback laid out as sentences
