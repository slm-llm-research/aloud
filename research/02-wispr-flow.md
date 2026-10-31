# Wispr Flow: Competitive Feature Catalog

Research date: 2026-10-30. Written for an open-source macOS alternative.

**Confidence marks**
- **[H]**: official docs or Wispr's own pages
- **[M]**: reputable third party, or official but inconsistent across pages
- **[L]**: a single or interested source (often a competitor's blog), not verified

Official docs live at `docs.wisprflow.ai` (also mirrored at `wispr-knowledge-base.help.usepylon.com`). The changelog moved from `roadmap.wisprflow.ai/changelog` to https://wisprflow.ai/whats-new.

---

## 0. TL;DR for builders

- **Core loop:** you hold a global hotkey (Fn on Mac), speak, and release. Audio goes to the cloud for speech recognition (ASR). An LLM cleanup pass (a fine-tuned Llama on Baseten) follows, and the text is pasted into the focused field. The latency target is under 700 ms p99 after you stop speaking. [H]
- **Main differentiators:**
  - Cleanup: filler removal, "backtrack" self-correction, lists, punctuation.
  - Per-app-category Styles.
  - Context awareness: surrounding text and screen context, used for names.
  - Personal dictionary that learns automatically, plus snippets.
  - Command Mode: a voice LLM edit of selected text, or questions answered by voice.
  - Developer features: Variable Recognition and @-file tagging in Cursor and Windsurf.
- **Weaknesses an open-source tool can attack:**
  - Cloud only, with no real offline mode, and multi-day outages in mid-2026.
  - Privacy controversies: window screenshots for context, a keyboard event tap, and a challenged SOC 2 audit.
  - An Electron footprint of about 750–1000 MB RAM.
  - A subscription priced at $12–15/mo.
  - Free tier capped at 2,000 words/week.

---

## 1. Public GitHub presence

- https://github.com/Wispr-Flow holds one public repo, `.github`, which is just the org profile README: "Download Wispr Flow to turn spoken ideas into polished text…". It has 0 stars and no code. The org description reads: "AI voice dictation tool for faster writing, notes, messages, and documents." [H]
- **Takeaway:** nothing is open source. There is no SDK and no public API apart from the Notetaker MCP server (see §10).

---

## 2. Hotkeys and activation

### Defaults [H]

Sources: https://docs.wisprflow.ai/articles/6391241694-use-flow-hands-free, https://docs.wisprflow.ai/articles/4816967992-how-to-use-command-mode, https://docs.wisprflow.ai/articles/2612050838-supported-unsupported-keyboard-hotkey-shortcuts

| Action | Mac | Mac without an Apple Fn key | Windows |
|---|---|---|---|
| Push-to-talk (hold) | **Fn** | **Ctrl+Opt** | **Ctrl+Win** (or Caps Lock if chosen in onboarding) |
| Hands-free (latched) | **Fn+Space** | Ctrl+Opt+Space | **Ctrl+Win+Space** |
| Command Mode | **Fn+Ctrl** | Cmd+Ctrl+Opt | **Ctrl+Win+Alt** |
| Paste last transcript | **Ctrl+Cmd+V** | n/a | **Alt+Shift+Z** |
| Cancel | **Esc** (remappable since Mar 2026) | | Esc |

- **Fn availability:** external and non-Apple keyboards don't expose Fn to the app, so Flow switches to Ctrl+Opt automatically. [H]
- **Older Command Mode default:** the older Notion beta page listed Command Mode as Fn+Cmd. That is outdated. [M]

### Hold-to-talk vs. hands-free [H]

- **Push-to-talk:** hold the key to record, release to transcribe and paste.
- **Starting hands-free:** any of these works:
  - press the hands-free shortcut;
  - **double-tap the push-to-talk key within ~500 ms**;
  - click the Flow Bar.
- **Double-tap still works with no binding:** if the hands-free binding is removed, double-tapping push-to-talk still starts hands-free dictation.
- **Stopping hands-free:** press the hands-free shortcut again, or click the stop (■) icon in the Flow Bar. Clicking the Flow Bar body does *not* stop recording.
- **Cancelling:** press Esc or click X. An **Undo** option then appears, which retries the last transcript.
- **Double-press cancels:** pressing the hands-free shortcut twice (or clicking the Flow Bar twice) within 0.5 s cancels instead of pasting.
- **Command Mode lock:** pressing the Command Mode shortcut twice within 500 ms locks it in hands-free mode. Esc or Backspace cancels.
- **Session length:** desktop sessions run up to **20 minutes**, with a warning at 19 minutes. The cap was raised in Mar 2026. Mobile is limited to 5 minutes.
- **Early release:** releasing the key before Flow starts listening cancels the session.
- **System shortcuts:** using a non-Flow system shortcut within the first ~1 s cancels the session (needed so that Fn+key system shortcuts still work).
- **Busy state:** a key press is ignored while the previous transcript is still processing.
- **Audio cues:** a "ping" sounds when listening starts.

### Configurability [H]

Source: https://docs.wisprflow.ai/articles/2612050838-supported-unsupported-keyboard-hotkey-shortcuts

- **Where to set them:** Settings → General → Shortcuts, or the menu-bar icon → Shortcuts.
- **Bindings per action:** up to **4 bindings** per action; Cancel gets 1.
- **Per device:** bindings are stored per device and do not sync.
- **Combination rules:**
  - at most 3 keys, and a modifier (or a mouse button) is required;
  - left and right versions of the same modifier can't be mixed;
  - letters and numbers can't be used on their own.
  - Caps Lock alone is allowed only for push-to-talk and hands-free.
  - Esc alone is allowed only for Cancel.
- **Reserved combos are blocked:** Cmd+C/V/X/Z/A/Q/W, Cmd+Tab, Ctrl+A/E/K, and so on.
- **Fn behavior:** when Fn is bound on its own, Flow suppresses its system action (emoji picker / dictation).
- **Overlap warning:** if a hands-free binding is a subset of the push-to-talk binding, Flow shows a 5-second warning.
- **Saving:** a key combo saves on key-up; a mouse binding saves on press.
- **Mouse buttons ("Mouse Flow", Mar 2026):**
  - Supported hardware: Logitech MX, or any mouse with more than 3 buttons. Windows supports middle-click and Mouse4/5; Mac supports Mouse 4–10.
  - Trackpads and the Magic Mouse are excluded.
  - Bound buttons are swallowed, so other apps don't receive them.
  - They work like keys: hold for push-to-talk, double-tap for hands-free.
- **Known conflicts:**
  - Secure Keyboard Entry (e.g. 1Password) blocks the hotkeys.
  - Granola's voice typing steals Fn.
  - OEM keyboard utilities interfere on Windows.
  - A stuck hold recovers automatically within 10–15 s.
- **Voice "press enter" (Experimental, paid):** ending a dictation with "press enter" pastes the text and then sends Return; the phrase itself is stripped. [M] Source: https://talk.macpowerusers.com/t/wisprflow-tip-press-enter-to-trigger-return/45142
- **Implementation hint:** an independent forensic write-up describes the Mac app as **Electron plus a Swift helper**. The helper installs a system-wide CGEventTap, which is how Fn is captured and suppressed, and forwards events to Electron over a queue. The same write-up blames a bug in this tap for "eating" spacebar presses. [L] Source: wensenwu.com, "How Wispr Flow Ate My Spacebar" (Apr 2026), summarized via https://www.getvoibe.com/resources/is-wispr-flow-safe.md

### UI

- **Flow Bar:** a small floating pill, shown by default and draggable to screen edges (Jul 2026). It acts as a start/stop control, and a language picker was added in Mar 2026. [H] Source: https://wisprflow.ai/whats-new
- **Menu bar:** the menu-bar/tray icon offers Open, Help, and Support.
- **Dock icon:** optional on Mac.
- **Microphone handling:** Flow auto-selects the best available mic and switches to an external one when the laptop lid is closed. Virtual audio devices became selectable in Aug 2026. [H]

---

## 3. Dictation cleanup ("Refine")

Source: https://wisprflow.ai/features [H]

- **Filler removal:** strips "um" and "uh" and pauses.
- **Backtrack / self-correction:** "2… actually 3" becomes "3".
- **Numbered lists:** spoken enumerations are formatted as lists.
- **Auto punctuation:** inferred from pauses and tone. Spoken punctuation ("comma") also works.
- **Auto Cleanup levels (Apr 2026):** None / Light / Medium / High. A bug made Cleanup overly aggressive; it was rolled back and fixed by Jul 2026. [H] Source: https://wisprflow.ai/whats-new
- **One model for everyone (Jun 2026):** all users were moved to a single current formatting model, with A/B testing for new models. [H]
- **Transforms (beta, May 2026):** AI rewrites of selected text through preset and custom prompts, e.g. "Polish" and "Prompt Engineer". "Transform Shortcuts and Custom Prompts" are configurable. [H, details thin] Source: https://wisprflow.ai/whats-new

### Styles (tone per app category)

Source: https://docs.wisprflow.ai/articles/2368263928-how-to-setup-flow-styles [H]

- **Categories:** Personal messages, Work messages, Emails, Other apps.
- **Available styles:** Formal and Casual everywhere. **Very Casual** is for personal messages only. **Excited** is for work, email, and other apps.
- **Defaults:** Personal → Casual; Work, Email, Other → Formal.
- **What a style controls:** punctuation, capitalization (casual drops caps and trailing periods), and tone. Styles affect new dictations only.
- **Where Styles work:** English and desktop only, per the features page; iPhone was added later.
- **iOS 26.4 change:** third-party keyboards can no longer detect the host app, so Flow added a "Quick Style Switcher" on iOS. Source: https://docs.wisprflow.ai/articles/6269634092-adapting-to-ios-26-4 [H]
- **Launch:** Oct 2025. Source: https://alternativeto.net/news/2025/10/wispr-flow-introduces-personalized-text-formatting-by-app-type [M]

### Languages

Source: https://docs.wisprflow.ai/articles/3191899797-use-flow-with-multiple-languages [H]

- **Count:** marketing says "100+ languages". Wikipedia says 104. Auto-detect covers **99** (Whisper's language set, which hints at Whisper-family ASR [L, inference]).
- **Auto-detect:** on by default on desktop; manual selection is disabled while it is on. Android has no auto-detect. On iOS, removing every language turns auto-detect on.
- **Recommendation:** the docs suggest picking 2–3 languages for better accuracy, and admit that non-English accuracy is still improving.
- **Code-switching:** mixing languages mid-utterance is a stated research focus. Source: https://wisprflow.ai/research/technical-challenges [H]
- **Routing fixes:** language routing for UK English and Swiss German was fixed in Jun 2026, and Canadian English was added to the dictionary in Jul 2026. [H]

### Whisper mode (quiet speech)

- **Status:** "Whispering mode" launched in beta on Aug 5, 2024. The features page now says Flow "works when you speak quietly". There is no separate toggle in the current docs. [M] Sources: https://roadmap.wisprflow.ai/changelog/ocean-use-flow-everywhere-with-whispering-mode-in-beta, https://wisprflow.ai/features
- **Accuracy:** reviewers say it degrades in noise. [L]
- **Subvocalization:** the CTO lists sub-audible speech as an open research problem, a legacy of the original wearable. [H]

---

## 4. App-aware context

- **Name spelling from context:** Flow "uses surrounding text to spell uncommon names correctly." [H] Source: https://wisprflow.ai/features
- **Toggle:** the Security Overview says the Privacy/context setting "controls whether Flow uses context from your screen to improve transcription accuracy". [M] Source: https://docs.wisprflow.ai/articles/3147443438-security-overview (via search; the page returned 404 on direct fetch)
- **Screenshot controversy:**
  - What was reported: Context Awareness *captured screenshots of the active window and uploaded them*. A user found this by sniffing network traffic and posted about it on Reddit (r/macapps / r/privacy). Accounts date it to 2025 and to Feb 2026, and say the poster was reportedly banned.
  - Response: the CTO apologized, and the feature was "reworked".
  - Current state: later descriptions say it reads a limited snippet of text near the cursor through Accessibility APIs.
  - Confidence: [L–M], because the sources are mostly competitors. Sources: https://www.getvoibe.com/resources/is-wispr-flow-safe.md, https://www.laxis.com/pt/blog/wispr-flow/, https://reddit.sentinel-team.org/posts/1u0fpaq/snapshots/2026-06-09T22%3A23%3A55.474306Z
- **How context feeds the models:** the CTO's post says the ASR is conditioned on "speaker qualities, surrounding context, and individual history". Context includes "dictation history and current app context", fed to *both* the ASR and the LLM within the latency budget. [H] Source: https://wisprflow.ai/research/technical-challenges
- **Android:** an AccessibilityService detects text fields and inserts text, and the app claims it collects nothing when not dictating. [M] Source: https://www.apkmirror.com/apk/wispr-ai-inc/wispr-flow-ai-voice-to-text/
- **Android 1.4.1 (Mar 2026):** added "context-aware dictation" and pauses in banking apps. [H]

### Developer and "vibe coding" features

- **Variable Recognition**, under Settings → **Vibe coding**. [H] Source: https://docs.wisprflow.ai/articles/8554805225-variable-recognition
  - Off by default.
  - Reads code context from Cursor, Windsurf, and VS Code, and sends variable, function, and class names to the transcription service as vocabulary hints.
  - Formats recognized identifiers in backticks.
  - In Cursor and Windsurf it requires the editor's **"Screen Reader Optimized" accessibility mode**, i.e. it reads the editor buffer through accessibility APIs. VS Code gets only the screen-reader-mode context.
  - Handles camelCase, snake_case, and acronyms, with exact spacing. Changelog Aug 28, 2025: https://roadmap.wisprflow.ai/changelog/variable-recognition-for-developers-with-file-tagging-already-built-in
- **File Tagging:** [H] Source: https://docs.wisprflow.ai/articles/9805771321-file-tagging
  - On by default.
  - Saying a filename inside the Cursor or Windsurf AI chat inserts an `@file` tag.
  - Not supported in VS Code + Copilot, and not in the integrated terminals.
  - Mac and Windows only.
- **Developer jargon:** recognizes product names such as Supabase, Cloudflare, and Vercel, plus CLI commands. [H] Source: https://wisprflow.ai/features
- **Coding use cases:** prompting in Cursor, terminal commands in Warp, Jira and Linear tickets, commit messages and PR reviews. [H] Source: https://wisprflow.ai/use-cases/github
- **Terminal dictation:** fixes shipped in May 2026. [H]

---

## 5. Command Mode

Source: https://docs.wisprflow.ai/articles/4816967992-how-to-use-command-mode (updated Jun 2026) [H]

- **Availability:** Experimental, off by default; enable it under Settings → Experimental. It requires a paid plan or trial, and some commands are Pro-only.
- **Flow:**
  1. Optionally highlight text.
  2. Hold the Command shortcut (Fn+Ctrl / Ctrl+Win+Alt).
  3. Speak the instruction naturally, with no wake word.
  4. Release.
- **What gets sent:** the instruction plus the **whole content of the current text box and the selection**.
- **Results:**
  - Highlighted text is **replaced** with the result.
  - With no selection, the generated text or answer is inserted at the cursor.
  - With no editable field focused, the result appears in a notification.
- **Output formatting:** the result is pasted *without* normal dictation formatting.
- **Use cases:** edit or rewrite selected text, draft a reply, answer a question by voice, web search, and "app-building" commands that open the result in a browser.
- **Web search:** opens **Perplexity** with the query, plus the selected text appended.
- **Spoken triggers:** English only. Hotkey activation works in any language.
- **Models:** not named. Third-party reports list OpenAI, Anthropic, Cerebras, and Fireworks as subprocessors, routed per feature. [L] Sources: https://spokenly.app/blog/wispr-flow-review, https://www.getvoibe.com/resources/wisprtype-vs-wispr-flow/
- **Limits:**
  - 20-minute cap.
  - "Servers busy" means nothing is pasted.
  - On iOS, editing in place is broken and fails silently.
- **Unconfirmed:** a popup fallback for Google Docs is reported by reviews. [L]

---

## 6. Personalization: dictionary, snippets, history, notes

- **Dictionary:** [H] Source: https://docs.wisprflow.ai/articles/4052411709-teach-flow-your-words-with-the-dictionary
  - **Manual entries** of words or terms, plus **replacement rules** (misheard → correct).
  - **Auto-learning:** when you correct a dictated word in place, the correction goes through proper-noun detection, and only names and uncommon proper nouns are added. Auto-learned entries carry a ✨ icon.
  - Mar 2026 added starring and usage ranking.
  - Entries are limited to 60 characters [L].
  - A word can't be both a dictionary entry and a snippet trigger.
  - **Edit capture happens on-device**, and an LLM is trained to follow captured edits. [H] Source: https://wisprflow.ai/research/technical-challenges
- **Snippets:** speaking a trigger phrase expands it into longer text (scheduling links, intros, FAQs). Rich text formatting was added in Jul 2026. [H] Sources: https://wisprflow.ai/features, https://wisprflow.ai/whats-new
- **Team sharing:** shared dictionary and snippets on Pro/teams; org- and department-wide sharing came in Sep 2026. [H]
- **Sync:** the dictionary and snippets sync across devices *regardless* of privacy settings. [M]
- **History (Home tab):**
  - Searchable, grouped by date, with copy, flag, and retry actions.
  - Audio playback covers the last 14 days (Aug 2026).
  - "Retry" re-transcribes stored audio.
  - Local transcript storage options came in Apr 2026.
  - [H] Source: https://docs.wisprflow.ai/articles/5096240724-navigating-the-wispr-flow-app-desktop-ios-and-android
- **Local storage footprint:** the forensic report found a 694 MB local SQLite database holding 3,404 dictations and about 198 MB of audio. [L]
- **Insights tab (Apr 2026):** usage stats and a "communication profile". There is a team leaderboard and a daily teammate digest. Marketing claims a ~220 wpm speaking rate vs. 45 wpm typing ("4x faster"). [H]
- **Notes → Scratchpad (beta, May 2026):** a floating notepad that replaced "Flow Notes". It syncs to iOS. iOS Quick Dictation to Notes uses the Action Button. Notes support @-mentions (Oct 2026). [H] Source: https://wisprflow.ai/whats-new
- **Data export:** exports are kept for 30 days. [H]

---

## 7. Meetings: Notetaker (and MCP)

- **Launch:** Notetaker launched on Mac on **Aug 5, 2026** and on Windows on Sep 15, 2026. [H] Sources: https://wisprflow.ai/whats-new, https://releases.sh/release/rel_qCAmo4gWENZvEDcoAG0JT
- **Capture:** bot-free; it records system audio with any meeting platform.
- **Transcription:** uses your dictionary and calendar attendee names for speakers, and re-processes recordings after the meeting. Transcription covers 21 languages.
- **Speaker detection:** works for the Teams gallery view and Google Meet (Oct 2026).
- **Integrations:** Outlook and Google calendars; imports from Otter and (reportedly) Granola.
- **Retention:** meeting audio is deleted 7 days after upload, while transcripts and summaries are kept. Notetaker was not in scope of the SOC 2 audit. [H] Source: https://docs.wisprflow.ai/articles/3467817258-security-and-compliance-faq
- **MCP server:** exposes meetings, calendar, participants, folders, and Scratchpad notes to Claude (custom connector), ChatGPT (Developer mode, web), and Gemini. It requires Notetaker and Cloud Sync. [H] Source: https://docs.wisprflow.ai/articles/4759919286-how-to-connect-wispr-flow-to-claude-chatgpt-and-other-ai-tools-mcp
  - The MCP tool surface, observed in this environment's Wispr Flow connector: `search_meetings`, `get_meeting`, `get_upcoming_meeting`, `list_folders`, `search_scratchpad_notes`, `get_scratchpad_note`, `search_calendar_events`, `resolve_share_link`, `get_meeting_participants_enriched`, and similar. **There is no dictation API.**
  - Relevance to an open-source dictation app: low. This is a separate notes and meetings product.

---

## 8. Platforms and architecture

- **Platforms:**
  - macOS and Windows desktop (Windows announced in 2025).
  - **iOS:** shipped Jun 2025 as a custom keyboard. Using it means globe-switching back after app changes, and on iOS 26.4+ tapping the mic may bounce to the app and back.
  - **Android:** shipped Feb 2026 as a floating **Flow Bubble** over the keyboard, using an AccessibilityService. It is hidden in password, numeric, and banking fields.
  - No Linux, no web.
  - [H] Sources: https://en.wikipedia.org/wiki/Wispr_Flow, https://docs.wisprflow.ai/articles/7453988911-set-up-the-flow-keyboard-on-iphone, https://docs.wisprflow.ai/articles/6391241694-use-flow-hands-free
- **Desktop stack:** **Electron**, plus a native Swift helper on Mac for the event tap and input. [M] Electron is repeatedly cited by users and reviews; the Swift helper comes from the forensic write-up [L].
- **Text insertion:** a paste into the focused field (the "Paste last transcript" design implies the clipboard is used). Clipboard restore behavior is undocumented. [L]
- **Cloud pipeline:**
  - Steps: audio upload → ASR → personalized LLM formatting (fine-tuned **Llama** on **Baseten** dedicated deployments, on AWS, using the TensorRT-LLM engine builder and Baseten Chains for multi-step inference) → paste.
  - **End-to-end under 700 ms p99 after you stop speaking.** Llama must generate 100+ tokens in under 250 ms.
  - Internal budgets: ASR under 200 ms, LLM under 200 ms, network under 200 ms worldwide.
  - Volume: about 1B words/month as of Sep 2025.
  - [H] Sources: https://www.baseten.co/resources/customers/wispr-flow/, https://wisprflow.ai/research/technical-challenges
- **ASR provider history:** earlier ASR reportedly used OpenAI, which is listed as a subprocessor. [L] Source: https://spokenly.app/blog/wispr-flow-review
- **"Canto" (in-house ASR):**
  - Previewed Aug 2026 with the Series B and rolled out to all users on **Sep 17, 2026**.
  - About 2B parameters, tuned for noise, wind, and accents.
  - Company-reported WER: 9.1% on a challenge set, 7.6% on noisy audio, 21.4% on short dictation. These are self-benchmarked and the methodology isn't public.
  - [H for existence, M for numbers] Sources: https://wisprflow.ai/whats-new, https://www.reworked.co/ai-platforms/wispr-hits-2b-valuation-launches-canto-voice-model/, https://benchlm.ai/voice-benchmarks/wispr-canto-launch-evaluation
- **Personalization architecture:** "most personalization data must stay on device". A local RL policy aligns output to the user's style. [H] Source: https://wisprflow.ai/research/technical-challenges
- **Latency and uptime claims:**
  - 30% lower latency since January, and 99.9% uptime, both claimed in Jul 2026. [H]
  - A competitor measured an average of **1,805 ms** for Wispr Pro. [L] Source: https://enviouswispr.pages.dev/compare/wisprflow/
- **Offline: effectively none.**
  - The desktop app keeps the audio when the network fails and transcribes it once you're back online.
  - The docs mention an unspecified "alternative transcription method" as a fallback.
  - Android greys out its controls when offline, and the iOS keyboard fails.
  - [H] Sources: https://docs.wisprflow.ai/articles/3834764683-why-vpns-or-security-tools-can-block-wispr-flow, https://docs.wisprflow.ai/articles/6391241694-use-flow-hands-free
  - Android Police also notes that an internet connection is required. [M]
- **Company:**
  - Founded 2021 by Tanay Kothari (CEO) and Sahaj Garg (CTO). It began as a silent-speech wearable and pivoted to Flow in 2024.
  - Funding: total $81M by Nov 2025, then a **$280M Series B at a $2B valuation in Aug 2026** (Menlo Ventures).
  - [H/M] Source: https://en.wikipedia.org/wiki/Wispr_Flow

---

## 9. Privacy and security

- **Settings → Data & Privacy holds separate toggles (split Jun 2026):** [H] Sources: https://docs.wisprflow.ai/articles/3467817258-security-and-compliance-faq, https://wisprflow.ai/whats-new
  - **Privacy Mode** ("Improve the model for everyone" inverted) decides whether your data is used for training and evaluation. **Training is on by default** for Free and Pro, and off on Growth and Enterprise (forced off since Oct 2026).
  - **Dictation Cloud Storage / Cloud Sync** decides whether transcripts, audio, and history are stored on Wispr's servers.
  - True zero data retention requires Privacy Mode on *and* Cloud Sync off. Enterprise can enforce ZDR org-wide.
- **Processing:**
  - Cloud only, in the US (AWS us-east-1 by default). Not end-to-end encrypted, because audio must be processed in the clear.
  - Encrypted in transit and at rest with Wispr-managed keys; customer-managed keys are not supported.
  - Third-party AI subprocessors are contractually barred from training on the data.
  - [H]
- **Certifications:**
  - Claimed: SOC 2 Type II and ISO 27001:2022.
  - The earlier audit came through **Delve** (ACCORP), a compliance vendor accused of templated reports (Mar 2026). After that, A-LIGN issued a clean SOC 2 Type I (Apr 2026), and the Type II re-audit was ongoing as of Aug 2026.
  - HIPAA BAA is available on Growth and above; Android is excluded.
  - The docs pages contradict each other on certification status.
  - [M] Sources: https://docs.wisprflow.ai/articles/6939510703-compliance-certifications-standards, https://www.getvoibe.com/resources/is-wispr-flow-safe.md
- **Incidents and allegations:**
  - The window-screenshot controversy (2025 / Feb 2026), covered in §4.
  - An independent forensic report on the Mac app (v1.4.752, Apr 2026) alleged:
    - a global keyboard event tap that swallowed 145 spacebar presses in 10 minutes;
    - hourly uploads that continued with sharing off;
    - 1,688 app and URL events logged in 30 hours;
    - Hardened Runtime disabled.
  - Wikipedia notes that Wispr has confirmed the app can read keystrokes.
  - Per-user analytics were discussed on a founder podcast, and aggregate country-level word stats were published on LinkedIn (Aug 2026).
  - [L–M] Sources: https://www.getvoibe.com/resources/is-wispr-flow-safe.md, https://en.wikipedia.org/wiki/Wispr_Flow

---

## 10. Pricing

Source: https://wisprflow.ai/pricing (fetched Oct 2026) [H]

| Tier | Price | Key limits and features |
|---|---|---|
| **Free** | $0 | **2,000 words/week on desktop**; "limited weekly use" on mobile. 100+ languages, dictionary and snippets, limited Notetaker. No Command Mode (Command Mode needs paid or trial). |
| **Pro** | **$15/user/mo monthly, $12 annual** | Unlimited dictation, Command Mode and Experimental features, shared dictionary and snippets, team workspace, usage analytics, priority support, longer Notetaker history |
| **Growth** | ~$18–26 annual / $23–33 monthly per user (the page is ambiguous) | SAML SSO, HIPAA BAA, admin training controls, multiple domains, unlimited Notetaker |
| **Enterprise** | Custom | SCIM, audit logs, MDM deployment, domain capture, training locked off, SLAs |

- **Trial:** a 14-day Pro trial for new members is mentioned (Aug 2026). [H]
- **Students and non-profits:** students and educators get 50% off Pro; non-profits get a discount. There is no lifetime plan. [H]
- **Usage cap:** free users are blocked once they hit the weekly word cap. [H]

---

## 11. Known limitations and complaints

| Issue | Detail | Confidence and source |
|---|---|---|
| Cloud-only / no offline | Dictation fails offline; there were multi-day outages in late May–Jun 2026 | [H] https://wisprflow.ai/whats-new (Jun 4/10 entries) |
| Privacy | Screenshot context, keystroke tap, training on by default, the Delve audit | [M/L] see §9 |
| Resource use | Electron; ~750–1000 MB RAM and ~8% CPU idle; laggy on 8 GB Macs; Windows freezes the target app (VS Code, Notepad++) | [L–M] https://tldv.io/blog/wisprflow/, https://spokenly.app/blog/wispr-flow-review, How-To Geek via Wikipedia |
| Latency variance | Under 700 ms p99 claimed vs. ~1.8 s measured by a competitor; "servers busy" drops | [L] |
| Over-aggressive cleanup | The Auto Cleanup regression (Apr–Jul 2026) rewrote user text | [H] changelog |
| Hotkey conflicts | Fn unavailable on external keyboards; Secure Keyboard Entry; Granola; spacebar-eating bug | [H/L] |
| Mobile friction | iOS keyboard switching; iOS 26.4 app bounce and loss of per-app style; 5-min caps | [H] |
| Command Mode gaps | Paid only, experimental, broken on iOS | [H] |
| Non-English | Accuracy still improving; Styles English-only | [H] |
| Subscription fatigue | "$15/mo STT wrapper"; free tier only 2k words/week | [L] Reddit snapshots, e.g. https://reddit.sentinel-team.org/posts/1sjg6he/snapshots/2026-04-13T18%3A18%3A39.555675Z |
| Trust | Trustpilot 2.7/5 (billing, reliability) | [M] https://es.trustpilot.com/review/wisprflow.ai |
| Hands-free cancel | Users report no keyboard cancel in hands-free mode on some builds (Esc now documented) | [L] |

**Open-source alternatives commonly suggested on r/macapps:** VoiceInk, FreeFlow, OpenWhispr, plus Superwhisper, Spokenly, and MacWhisper. [L] Sources: https://tryvoiceink.com/best-wispr-flow-alternatives, https://feedback.openwhispr.com/compare/wisprflow

---

## 12. Feature checklist for an open-source clone (derived)

- [ ] Fn hold-to-talk using a CGEventTap that suppresses Fn's system action, with a Ctrl+Opt fallback
- [ ] Double-tap within 500 ms latches hands-free; press again to stop; Esc cancels with Undo/retry
- [ ] A double-press within 0.5 s while recording cancels instead of pasting
- [ ] Ignore the first ~1 s if another system shortcut fires
- [ ] Mouse buttons 4–10 as triggers
- [ ] Floating pill (Flow Bar) with a waveform, stop and cancel buttons, and a language picker
- [ ] Paste-last-transcript hotkey; keep audio on failure for retry; history with audio playback
- [ ] LLM cleanup: fillers, backtrack, lists, punctuation, cleanup levels None/Light/Medium/High
- [ ] Styles by app category (bundle-ID mapping) and "press enter" voice command
- [ ] Context: AX-read text near the cursor and the app name feeding ASR prompt and LLM; identifier extraction from editors; @file tagging for Cursor
- [ ] Dictionary with auto-learn by diffing the user's post-paste edits (AX read-back) and proper-noun filter; replacement rules; snippets
- [ ] Command Mode: selection plus field text plus instruction → LLM → replace selection
- [ ] **Differentiators:** local/offline ASR (whisper.cpp / Parakeet), bring-your-own LLM, no screenshots, native Swift (low RAM), no word caps
