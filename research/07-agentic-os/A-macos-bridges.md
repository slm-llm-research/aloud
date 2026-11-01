# A. Bridging agentd to native macOS ("MacBridge")

*Research date: 2026-10-31. Scope: how Aloud's Node/TypeScript agent daemon (`agentd`) can act on the Mac's own apps and data. This section does not repeat what `research/` already covers (hotkeys, insertion, audio, distribution, STT/LLM choice).*

---

## A.0 TL;DR

1. **Build a small Swift helper, `macbridge`, of your own.** Ship it inside `Aloud.app`, signed with the same Developer ID and Team ID. Expose it to agentd as a **local MCP server over stdio**, with typed tools, each declaring its Effect. Don't mount the third-party Mac MCP servers in production. They're good for borrowing ideas (and MIT code), but each carries its own TCC identity, its own broad tools, and an unaudited permission surface.
2. **TCC follows the "responsible process".** If Aloud.app spawns agentd (a bundled Node binary) and agentd spawns `macbridge`, every Calendar, Reminders, Contacts, Automation and Accessibility prompt is attributed to **Aloud**. That only works if Aloud's `Info.plist` carries every usage string. If agentd is started from Terminal during development, Terminal gets the blame and the grants instead. Detect that case and warn.
3. **Prefer the most structured route.** Native framework (EventKit, Contacts, Spotlight) beats a scriptable dictionary (AppleScript/JXA), which beats Shortcuts / App Intents, which beats URL schemes, which beat Accessibility, which beats screenshot + OCR, which beats computer use. Each step down is slower, more brittle and harder to verify, so it gets a stricter approval level.
4. **The Effect model needs three additions.** `read_private` covers mail, messages, screen contents and the clipboard. `ui_input` covers synthetic clicks and keystrokes into other apps. `trash_local` is a reversible move to the Trash, distinct from the blocked `delete_local`. A carve-out from `system_settings` is also needed for *reversible* toggles (Focus, volume, dark mode).
5. **Shortcuts is the official on-ramp to third-party App Intents.** agentd can't call another app's App Intents directly. It can run any shortcut the user (or Aloud) has built around them, via `shortcuts run`. Apple's 26.1 betas contained groundwork for MCP inside App Intents ([9to5Mac](https://9to5mac.com/2025/09/22/macos-tahoe-26-1-beta-1-mcp-integration/)). Watch it. Don't depend on it.

---

## A.1 Mechanism-by-mechanism analysis

Each mechanism below is described by what it can do, how agentd calls it, the TCC permission it needs, how reliable and fast it is, and the agentd Effect plus approval it should get. Latency figures are typical orders of magnitude and should be measured in `bench/` on the owner's machine.

### A.1.1 AppleScript / JXA via `osascript` (Apple Events)

**What it can do.** It drives any app that ships a scripting dictionary (`.sdef`). Open one in Script Editor (File > Open Dictionary) or with `sdef /Applications/Mail.app`.

| App | Useful verbs (from its dictionary) | Notes |
|---|---|---|
| Finder | list, move, duplicate, reveal, `selection`, tags via `label index`, `delete` (moves to Trash) | Use the `selection` of the front window for "this file". |
| Mail | search mailboxes, read message content and attachments, `make new outgoing message`, `send`, save attachments | Mail.app only. For Gmail use the Gmail API/MCP. Reading is `read_private`, `send` is `send_message`. |
| Calendar / Reminders | events and reminders CRUD | Slow and flaky on large calendars. Use EventKit instead (A.1.3). |
| Notes | list, search, create, append (HTML body) | No public framework exists for Notes, so AppleScript is the best route. |
| Music | play, pause, next, search library, current track, volume | Reliable. |
| Safari / Chrome | URL and title of tabs, `do JavaScript` (needs "Allow JavaScript from Apple Events" turned on) | This is how "summarize this page" gets the real DOM text. |
| Messages | `send "…" to participant …` | Sending only. History needs Full Disk Access to `chat.db`, which isn't recommended. |
| System Events | UI scripting (menus, keystrokes), processes, login items, appearance (`dark mode`) | UI scripting needs **Accessibility** as well as Automation. |

**How to call it.**
- From Node: `execFile('osascript', ['-l','JavaScript','-e', script])`. Never interpolate model text into scripts. Pass arguments through `on run argv` / `function run(argv)`.
- From Swift: `NSAppleScript` (compile once, cache), or `NSUserAppleScriptTask` for sandboxed apps. Typed alternatives are ScriptingBridge or `SBApplication`.
- Recommendation: ship a **fixed library of parameterized scripts** inside macbridge (`mail.search`, `notes.append`, `safari.front_tab_text`), each exposed as a typed tool. Keep a generic `applescript.run` tool behind `execute_process` with approval and log the full script text.

**TCC.** **Automation (Apple Events)**, granted per target app ("Aloud wants to control Mail"). It needs `NSAppleEventsUsageDescription` in the Info.plist and the `com.apple.security.automation.apple-events` entitlement under the hardened runtime. Use `AEDeterminePermissionToAutomateTarget` to check status without triggering a prompt, and pre-flight before planning. A CLI with no bundle identity fails with `-1743`/`-1750` or blames Terminal. Steinberger's fix is to embed an `Info.plist` into the binary's `__TEXT,__info_plist` section and sign it consistently ([steipete.me](https://steipete.me/posts/2025/applescript-cli-macos-complete-guide)). Reset during testing with `tccutil reset AppleEvents <bundle-id>`.

**Reliability and latency.** Spawning `osascript` cold costs roughly 100–300 ms. A compiled `NSAppleScript` in a long-lived helper costs roughly 10–50 ms plus the target app's own time. Mail search on big mailboxes takes seconds. The target app is launched if it isn't running, so declare `launch_app` as well.

**Effect and approval.** Reads are `read_local`, or `read_private` for Mail and Messages; both are auto with a session grant. Creating notes or files is `write_local` with approval. Mail and Messages `send` is `send_message`: approval always, never by voice. Finder `delete` should be wrapped as `trash_local` with approval. Generic script execution is `execute_process` with approval.

### A.1.2 Apple Shortcuts CLI and App Intents

**What it can do.**
- `shortcuts run <name|id> [--input-path <p>|-] [--output-path <p>|-] [--output-type <UTI>]`
- `shortcuts list [--folders] [--folder-name …] [--show-identifiers]`
- `shortcuts view` and `shortcuts sign`

([man page](https://keith.github.io/xcode-man-pages/shortcuts.1.html), [Apple guide](https://support.apple.com/guide/shortcuts-mac/apd455c82f02/mac)). Stdin and stdout piping makes shortcuts composable as tools.

**Can agentd invoke third-party App Intents?** Not directly. There is no public API for one app to call another app's `AppIntent`. What works:
1. Any intent an app exposes appears as a **Shortcuts action**. Wrap it in a shortcut, then run it with `shortcuts run`. This is the sanctioned bridge to apps like Things, Fantastical, Bear, Drafts, Ivory and Obsidian (via plugins).
2. In macOS 26, App Intents also surface as **Spotlight actions** (Cmd-Space, then 3), with parameter summaries. Intents can run from **Mac automations** (folder changes, drives, Bluetooth, time of day). Shortcuts' **Use Model** action receives entity properties as JSON ([WWDC25-260](https://developer.apple.com/videos/play/wwdc2025/260/), [MacRumors](https://www.macrumors.com/how-to/do-more-with-spotlight-in-macos-tahoe/)). None of this is callable from outside, but it means more apps now ship rich intents worth wrapping.
3. Aloud can **ship its own App Intents** ("Ask Aloud", "Run voice task"), so Siri, Spotlight and Shortcuts users can trigger agentd. That's a cheap, high-visibility feature.
4. On the horizon: 26.1 betas contained code for **MCP support inside App Intents** ([9to5Mac](https://9to5mac.com/2025/09/22/macos-tahoe-26-1-beta-1-mcp-integration/), [Computerworld](https://www.computerworld.com/article/4061614/apple-to-deploy-mcp-support-for-powerful-ai-experiences.html)). If Apple ships it, macbridge could enumerate system-exposed intents as MCP tools. Design the tool registry so intents can be mounted dynamically.

**How to call it.** From Node or Swift, run `execFile('shortcuts', ['run', id, '--input-path','-','--output-path','-'])`. The AppleScript alternative is `tell application "Shortcuts Events" to run shortcut "X" with input …`, which runs in the background without opening the Shortcuts UI. Use `--show-identifiers` and refer to shortcuts by UUID so renames don't break tools.

**TCC.** The CLI runs under the user. Each shortcut's actions carry their own privacy prompts, attributed to Shortcuts rather than Aloud. That's convenient (fewer prompts to Aloud), but it's also an **opaque side-effect surface**.

**Reliability and latency.** Roughly 0.5–2 s of overhead per run. It sometimes fails silently when a shortcut needs UI (Ask for Input, Show Result), so build shortcuts headless.

**Effect and approval.** An arbitrary shortcut can do anything, so default to `execute_process` with approval. Let the user **tag allowlisted shortcuts with declared effects** in Aloud settings (for example "Set Focus: Work" as `system_settings:reversible`). A tagged shortcut is then treated per its tag. Prefix or folder-based allowlisting works well: only shortcuts in a folder named `Aloud` are visible to the model.

### A.1.3 EventKit, Contacts and Photos (Swift helper)

**What it can do.**
- **EventKit**: events and reminders CRUD, recurrence, alarms, availability queries, and calendar or list selection. It's fast, in-process, and works for iCloud, Google and Exchange accounts already configured in Calendar. Prefer it to AppleScript for "what's on my calendar after 3".
- **Contacts** (`CNContactStore`): resolve "Priya" to an email address or phone number. This entity resolution is critical before any send.
- **PhotoKit** (`PHPhotoLibrary`, `PHAsset` fetch by date, location or media type, plus albums): "find the photo of the whiteboard from Tuesday" (combine with Vision OCR).

**How to call it.** These frameworks are Swift-only, so they need macbridge. agentd calls them as MCP tools.

**TCC and plist.**
- Since macOS 14, full or write-only access is split. Write-only events access can't read anything, and there is **no read-only mode**.
- Keys: `NSCalendarsFullAccessUsageDescription` (or `…WriteOnly…`) and `NSRemindersFullAccessUsageDescription`.
- APIs: `requestFullAccessToEvents`, `requestWriteOnlyAccessToEvents` and `requestFullAccessToReminders` ([Apple: Accessing the event store](https://developer.apple.com/documentation/eventkit/accessing-the-event-store)).
- Contacts needs `NSContactsUsageDescription`. Photos needs `NSPhotoLibraryUsageDescription` (`PHAccessLevel.readWrite` or `.addOnly`).
- Sandboxed apps also need the personal-information entitlements. Aloud is likely non-sandboxed (Developer ID), but the entitlements are harmless.

**Reliability and latency.** Excellent. Roughly 5–50 ms per query on a warm store. Keep one `EKEventStore` alive for the helper's lifetime.

**Effect and approval.**

| Operation | Effect | Approval |
|---|---|---|
| Calendar, Reminder or Contact read | `read_private` | auto with session grant |
| Create event or reminder | `write_local` | approval, with the card showing title, time and calendar |
| Invite attendees (sends email) | `send_message` | approval |
| Delete event | `delete_local` | blocked, or approval-only "cancel" if needed later |

### A.1.4 Spotlight (`mdfind` / `mdls` / `NSMetadataQuery`) and FSEvents

**What it can do.** Instant, index-backed search over names, content and rich metadata. That includes `kMDItemWhereFroms` (download URL, and for saved Mail attachments the sender or message), `kMDItemContentTypeTree`, `kMDItemAuthors`, `kMDItemLastUsedDate`, `kMDItemFSCreationDate`, `kMDItemUserTags`, and `kMDItemTextContent` for indexed text ([Apple metadata attributes](https://developer.apple.com/library/content/documentation/CoreServices/Reference/MetadataAttributesRef/Reference/CommonAttrs.html)). Example: "the PDF Priya sent last week" becomes:

```
mdfind -onlyin ~ 'kMDItemContentTypeTree == "com.adobe.pdf" && kMDItemFSCreationDate >= $time.today(-7) && (kMDItemWhereFroms == "*priya*"cd || kMDItemAuthors == "*priya*"cd)'
```

Fall back to Mail.app attachment search, or to the Gmail MCP, when Spotlight misses.

**FSEvents** (`FSEventStreamCreate` with `kFSEventStreamCreateFlagFileEvents`, scheduled on a dispatch queue) watches whole trees cheaply, with roughly 2–4 ms detection ([alexwlchan](https://alexwlchan.net/2026/watch-files-on-macos/)). That makes standing rules possible ("whenever a PDF lands in Downloads, file it"), which is the "agentic OS" behaviour no dictation app has.

**How to call it.** `mdfind` and `mdls` can be run directly from Node (`execFile`). Better is `NSMetadataQuery` in macbridge, which returns typed results, supports live-updating queries and allows scoping. The FSEvents watcher lives in macbridge and pushes MCP notifications to agentd.

**TCC.** Spotlight results are filtered by what the *calling process* may read. `~/Desktop`, `~/Documents` and `~/Downloads` trigger the "Files and Folders" prompts. Removable or network volumes have separate prompts. **Full Disk Access is not required** for the user's own folders; avoid requesting it.

**Reliability and latency.** `mdfind` takes roughly 30–300 ms. Indexing can lag a freshly downloaded file by seconds. Some folders (`~/Library`, excluded volumes) aren't indexed, so add a `find` fallback within agentd's allowed roots.

**Effect and approval.** Search and metadata reads are `read_local`, auto, confined to allowed roots. Creating a watch rule is `write_local` with approval at rule-creation time. Each rule then declares what it's allowed to do. For example a rule allowed `move_within(~/Downloads → ~/Documents/Sorted)` runs without per-file approval but is audit-logged, with a daily digest.

### A.1.5 Accessibility API (`AXUIElement`)

**What it can do.**
- Read any app's UI tree: `AXUIElementCreateApplication(pid)`, `AXUIElementCopyAttributeValue` for role, title, value, `AXSelectedText`, `AXFocusedUIElement` and children.
- Act on it: `AXUIElementPerformAction` (`kAXPressAction`, `kAXRaiseAction`) and `AXUIElementSetAttributeValue` (for example `kAXPositionAttribute` and `kAXSizeAttribute` on windows, which is how "move this window to the left half" works).
- Observe it: `AXObserver` notifications such as focus changed or window created.
- Synthesize input: `CGEvent` keyboard and mouse events.
- It's the universal fallback for apps without scripting, and the foundation for **Command mode** (read `AXSelectedText`, rewrite, replace) and **AX field-role detection** from the plan.

**How to call it.** Only from Swift, C or Objective-C, so it lives in macbridge. Return **compact, pruned trees** (role, label, value and an element id, truncated by depth and visibility) rather than raw dumps. Peekaboo's "UI map with element IDs" design is a good template ([Peekaboo](https://github.com/openclaw/Peekaboo)).

**TCC.** **Accessibility** (`AXIsProcessTrustedWithOptions` with the prompt option), granted manually in System Settings > Privacy & Security > Accessibility. There is no per-app scoping: once granted, Aloud can drive *everything*. Aloud already needs this for insertion and hotkeys, so no new prompt is needed. Posting synthetic events may also need **Input Monitoring / PostEvent** on recent macOS, which is the "additional permission" Peekaboo mentions.

**Reliability and latency.**
- Native AppKit apps: good. Tree reads take roughly 20–200 ms.
- Electron and Chromium apps (Slack, VS Code, Chrome): large or poor trees take 0.5–2 s, so enable `AXManualAccessibility` / `AXEnhancedUserInterface` on the target.
- Catalyst and SwiftUI apps: mixed.
- UI changes across app versions break selectors, so always re-resolve elements just before acting.

**Effect and approval.** Reading the tree or selection is `read_private`, auto within a task. Window move or resize is a new `ui_input:window` Effect, auto, because it's reversible and harmless. Clicks or typing into other apps are `ui_input` with **approval** and a preview naming the target element ("Press 'Send' in Slack"). Any click that semantically sends, pays or deletes inherits that effect (`send_message`, `spend_money` or `delete_local`), and that semantic classification is done by a guard model in agentd.

### A.1.6 ScreenCaptureKit and Vision OCR (screen context)

**What it can do.**
- **ScreenCaptureKit** (`SCShareableContent`, `SCScreenshotManager.captureImage`, macOS 14+) grabs a single window, a display or a region. It can exclude Aloud's own HUD.
- **Vision**: `VNRecognizeTextRequest` (accurate mode, language correction) and, on **macOS 26**, `RecognizeDocumentsRequest`, which returns paragraphs, **tables** and lists rather than flat lines ([Apple](https://developer.apple.com/documentation/vision/recognizedocumentsrequest)).
- Together they deliver "summarize what's on my screen", "pull the table on screen into a CSV", or "what's the error in this dialog" without sending a screenshot to the cloud. On-device OCR text can go to Claude, and the image only when needed.

**TCC.** **Screen Recording**. Since Sequoia the user re-confirms it periodically ("Allow for one month"). There is no public way around this; the undocumented "persistent content capture" entitlement isn't obtainable ([9to5Mac](https://9to5mac.com/2024/08/14/macos-sequoia-screen-recording-prompt-monthly/), [TidBITS](https://tidbits.com/2024/08/19/apple-reduces-excessive-sequoia-permission-requests-shifts-to-monthly)). The UX needs to explain this monthly prompt.

**Reliability and latency.** Capture takes roughly 30–80 ms. OCR on a Retina window takes roughly 150–600 ms on Apple Silicon. That's very reliable for text but has no semantics; combine it with the AX tree when available.

**Effect and approval.** `read_private`. Screen capture is auto **only when the user's utterance explicitly references the screen** ("this", "on my screen"). Otherwise it needs approval. The capture is always shown as a thumbnail in the AgentPanel, and is never persisted beyond the task unless the user asks.

### A.1.7 Computer use (Anthropic tool) as last resort

**What it can do.** The model sees screenshots and emits mouse and keyboard actions. The current client toolset is `computer_toolset_20260801`, which needs no beta header and has 17 actions including `zoom`. Claude 5.5-generation models accept only the toolset on the Claude API ([Claude docs](https://platform.claude.com/docs/en/agents-and-tools/tool-use/computer-use-tool)). agentd runs on `claude-opus-5-5`, so implement the toolset. macbridge implements screenshot (via ScreenCaptureKit), click and type (`CGEvent`), and zoom (a crop at full resolution).

**Limits.**
- Anthropic's docs say latency "may be too slow for real-time human-AI interaction". Expect several seconds per step.
- Coordinates can be misplaced and success can be claimed falsely, so require a verification screenshot after each step.
- Prompt injection from on-screen content is a real risk.
- The docs recommend a VM and human confirmation for consequential actions.

**Effect and approval.**
- The whole session gets `ui_input` plus an inherited worst-case effect.
- It requires an explicit "take over" approval, with a visible red border and the kill switch armed.
- Each consequential action needs re-approval, and voice approval is never allowed.
- Use it only for apps with no AX, script or intent route, and log the reason in the audit.
- A cheaper middle path is **AX-grounded computer use**: give the model the pruned AX map plus element ids, and let it act by id rather than by pixels.

### A.1.8 NSWorkspace, Launch Services, `open`, URL schemes and deep links

**What it can do.**
- **NSWorkspace**: `openApplication(at:configuration:)`, open URLs or files with a specific app, `frontmostApplication`, `runningApplications`, `activateFileViewerSelecting`, and `recycle(_:)` (move to Trash, which is reversible). It also posts notifications on app launch and activate, useful for context.
- **`open`**: `open -a`, `open -b <bundleId>` and `open -g` (background).
- **URL schemes and x-callback-url** give zero-permission, robust writes into third-party apps:
  - Things: `things:///add?title=…&when=today`, plus an `auth-token` for updates.
  - Obsidian: `obsidian://new?vault=…&file=…&content=…` and `obsidian://open` ([Obsidian URI](https://www.dsebastien.net/obsidian-uri/)).
  - Bear: `bear://x-callback-url/create`.
  - Raycast: `raycast://extensions/<author>/<ext>/<command>?arguments=…` ([MacStories](https://www.macstories.net/stories/raycast-adds-deeplinking-of-commands/), [Raycast changelog](https://www.raycast.com/changelog/1-47-0)).
  - Also Fantastical, Drafts, Craft, Linear, Zoom (`zoommtg://`), Slack (`slack://channel?team=&id=`), and `x-apple.systempreferences:` for opening Settings panes.
- x-callback replies (`x-success`) need Aloud to register its own URL scheme (`aloud://cb/<taskId>`) to receive results.

**TCC.** None for opening. The target app may prompt on its own side.

**Reliability and latency.** Very high, roughly 50–300 ms. The weakness is that it's fire-and-forget unless x-callback is supported.

**Effect and approval.** `open_url` or `launch_app` is auto when the scheme is read-only or navigational. Schemes that create content (`things:///add`, `obsidian://new`) are `write_local`: auto for Things and Obsidian if the user opts in per scheme, otherwise approval. Keep a **scheme registry** in agentd mapping scheme plus action to an Effect, and treat unknown schemes as `execute_process`.

### A.1.9 Keychain

**What it can do.** `SecItemAdd` and `SecItemCopyMatching` store Aloud's *own* secrets (API keys for ElevenLabs, Groq and Anthropic, plus OAuth tokens for the Gmail MCP or a Robinhood-like API) under its access group. It can **not** silently read other apps' items: every cross-app read triggers a user prompt, and that's by design.

**Recommendation.** agentd should never get a generic "read keychain" tool. macbridge exposes `secrets.get(name)` only for Aloud-owned items, used internally to inject credentials into MCP servers. The value never goes to the model context.

**Effect and approval.** Internal only, not model-visible.

### A.1.10 Notifications (`UNUserNotificationCenter`)

**What it can do.** Post local notifications with actions (Approve / Deny / Open). That allows **out-of-band approval** for long-running tasks ("Your Downloads cleanup plan is ready: Review"), timed reminders, and results of background watch rules. It can't read other apps' notifications; there's no public API, and the notification DB requires Full Disk Access and is an unsupported route.

**TCC.** The Notifications authorization (`requestAuthorization`), attributed to Aloud.app. That's another reason for the helper to live in the app bundle.

**Effect and approval.** Posting to yourself is `notify`, auto (a no-risk effect). Approval actions in a notification count as **click approval** but must show the full step text.

### A.1.11 Focus modes

**What it can do.**
- **Setting** a Focus has no public API. The supported path is the Shortcuts **Set Focus** action wrapped in user shortcuts ("IF Focus Work", "IF Focus Off"), invoked via `shortcuts run`.
- **Reading**: `INFocusStatusCenter` only says whether the user is focused, and only for apps with the Communication Notifications capability. Hacks that read `~/Library/DoNotDisturb/DB/*.json` need Full Disk Access, so don't use them.
- Focus Filters (App Intents `SetFocusFilterIntent`) let Aloud itself *change behaviour* per Focus. For example, in "Work" Focus the default mail tool is work Outlook; in Personal it's Gmail.

**Effect and approval.** Set Focus is `system_settings:reversible`, auto or by voice. It's an explicit carve-out from the blocked `system_settings`, because it's trivially undoable.

### A.1.12 System settings (`defaults`, `pmset`, etc.)

**What it can do.**
- `defaults write com.apple.dock autohide -bool true; killall Dock`
- Appearance through System Events (`tell appearance preferences to set dark mode to true`)
- `osascript -e "set volume output volume 30"`, `brightness`, `networksetup` (needs admin), `pmset` (admin)
- Opening a Settings pane with `open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"`, which is great for onboarding.

**Effect and approval.** Keep `system_settings` **blocked** by default. Allow a **named allowlist of reversible toggles**, each recording its prior value for undo:

| Toggle | Effect | Approval |
|---|---|---|
| dark mode | `system_settings:reversible` | auto |
| volume, mute, brightness | `system_settings:reversible` | auto |
| Dock autohide | `system_settings:reversible` | approval |
| Do Not Disturb (via Shortcut) | `system_settings:reversible` | auto |
| Anything needing `sudo` | blocked | never |

### A.1.13 Window management (AX / yabai-like)

**What it can do.** Move, resize, raise or minimize windows through AX (`kAXPositionAttribute`, `kAXSizeAttribute`, `kAXMinimizedAttribute`), using screen geometry from `NSScreen.visibleFrame`. Tiling layouts ("left half", "thirds", "move Slack to my second display") are pure AX. **Spaces** switching and moving windows between Spaces need private APIs; yabai's scripting addition requires partially disabling SIP ([yabai wiki](https://github.com/koekeishiya/yabai/wiki)). Don't go there. AeroSpace avoids SIP by emulating workspaces. If the user already runs yabai, AeroSpace or Rectangle, call their CLIs (`yabai -m`, `aerospace`) or URL schemes (`rectangle://execute-action?name=left-half`) as optional adapters.

**Effect and approval.** `ui_input:window`, auto. It's reversible, so snapshot the frames and offer an "undo layout" command.

### A.1.14 Clipboard and clipboard history

**What it can do.** `NSPasteboard.general` read and write. Write-then-paste is already how InsertKit works. **Clipboard history** must be built by Aloud itself by polling `changeCount`. macOS 26's Spotlight clipboard history has no API ([MacRumors](https://www.macrumors.com/how-to/do-more-with-spotlight-in-macos-tahoe/)).

**Privacy change.** Apple is adding iOS-style pasteboard privacy to the Mac. Programmatic reads without user interaction raise an alert. New `detect` methods let an app inspect types without reading, and `accessBehavior` controls the policy ([MacRumors](https://www.macrumors.com/2025/05/12/apple-mac-apps-clipboard-change/), [Michael Tsai](https://mjtsai.com/blog/2025/05/12/)).

**Recommendations.**
- Use `detect*` first, and read only during a user-initiated task.
- If Aloud offers clipboard history, make it opt-in, honour `org.nspasteboard.ConcealedType` / `TransientType` (which password managers set), and store it encrypted locally.

**Effect and approval.** Clipboard read is `read_private`, auto within a voice task that references "what I copied". Clipboard write is `write_local`, auto because it's reversible and InsertKit already restores the clipboard.

### A.1.15 Audio and media control

**What it can do.**
- Volume through `osascript` or CoreAudio (`AudioObjectSetPropertyData` on the default output device).
- Output device switching through CoreAudio.
- App-specific playback through AppleScript (Music, Spotify).
- System-wide "now playing" plus play/pause for any app normally uses the private **MediaRemote** framework. Since **macOS 15.4** it no longer works when loaded by third-party apps. The community workaround, `mediaremote-adapter` (BSD-3), runs it via `/usr/bin/perl`, which is entitled ([GitHub](https://github.com/ungive/mediaremote-adapter)). It's fragile; prefer posting media-key `CGEvent`s (`NX_KEYTYPE_PLAY`) for play/pause/next, which needs Accessibility (already granted).

**Effect and approval.** `ui_input:media`, auto.

---

## A.2 Existing open-source macOS MCP servers

Figures are from the repository pages as fetched on 2026-10-31.

| Project | Stars | License | Language | Covers | Status / notes |
|---|---|---|---|---|---|
| [supermemoryai/apple-mcp](https://github.com/supermemoryai/apple-mcp/wiki) | ~3.1k | MIT | TS/Bun, JXA | Messages, Notes, Contacts, Mail, Reminders, Calendar, Maps | **Archived Jan 1 2026**, read-only. A useful catalogue of JXA snippets. Don't mount it. |
| [mattt/iMCP](https://github.com/mattt/iMCP) | ~1.9k | MIT | Swift | Calendar, Contacts, Location, Mail, Maps, Messages, Music, Notes, Phone, Reminders, **Shortcuts**, Voice Memos, Voicemail, Weather | Best-designed native one: a menu-bar app owns TCC, and an `imcp-server` stdio CLI talks to it via Bonjour. macOS 15.3+. It's the closest prior art to MacBridge; study its EventKit and Contacts code. |
| [openclaw/Peekaboo](https://github.com/openclaw/Peekaboo) (formerly steipete) | ~5.4k | MIT | Swift + Node MCP wrapper | Screenshots (app, window, screen), AX tree "UI map" with element IDs, click, type, scroll, drag, menus, Dock, dialogs, and its own agent | Very active (v4.9.x, about 3.9k commits). Best reference for the AX and ScreenCaptureKit layer. Needs Screen Recording plus Accessibility. |
| [steipete/macos-automator-mcp](https://github.com/steipete/macos-automator-mcp) | ~880 | MIT | TS | `execute_script` (AppleScript/JXA inline, file or knowledge-base ID) and `get_scripting_tips` (hundreds of curated scripts) | A generic "run any script" tool is too broad for agentd's policy. **Mine its knowledge base** for the fixed script library. |
| [mediar-ai/mcp-server-macos-use](https://mcp.so/servers/mcp-server-macos-use) | n/a | unclear (NOASSERTION) | Swift (MacosUseSDK) | Open app, click, type, key, and refresh AX traversal, by PID | License is unclear, so don't vendor it. |
| [adamrdrew/macos-accessibility-mcp](https://lobehub.com/ko/mcp/adamrdrew-macos-accessibility-mcp) | small | MIT | Swift | get_ui_tree, find_element, get_focused_element, list_windows, perform_action, set_value, observe_changes | A clean minimal AX tool vocabulary worth copying. |
| [Jeomon/macos-mcp](https://www.getdrio.com/mcp/io-github-jeomon-macos-mcp/md) | small | n/a | Python (`uvx`) | AX desktop automation | Python runtime; not a fit to bundle. |

**Recommendation: build MacBridge and don't mount these servers.** The reasons:

1. **TCC identity.** Each third-party server either runs as its own app (iMCP, Peekaboo.app), which means a second set of permission prompts and a second trust decision for the user, or inherits Aloud's grants with code you didn't write. Either is bad for a product whose pitch is policy-governed agency.
2. **Effects granularity.** agentd's model needs each tool to declare *one* Effect. `execute_script` or an "apple-mcp mail" tool that both reads and sends can't be classified safely.
3. **Licensing.** The top projects are MIT, so Aloud (Apache-2.0) can vendor or port code with attribution. Port iMCP's EventKit and Contacts patterns, Peekaboo's AX snapshot and element-id approach, and macos-automator-mcp's script knowledge base.
4. **Portfolio value.** "A typed, effect-declared, TCC-correct Mac bridge with evals" is a distinctive artifact. "I mounted apple-mcp" is not.

**Keep MCP mounting for remote services** (Gmail, Google Calendar, GitHub, brokerage read-only APIs), where agentd's generic MCP client plus per-tool Effect annotations in a config file is the right abstraction. For dev experimentation, allow mounting Peekaboo or iMCP behind a `dev.unsafeMcp` flag, with all their tools classified as `execute_process` + approval.

---

## A.3 MacBridge architecture

```
Aloud.app  (Developer ID, hardened runtime, Team T)
├── Contents/MacOS/Aloud          Swift UI, HUD, AgentPanel, HotkeyKit…
├── Contents/MacOS/macbridge             Swift CLI: MCP server (stdio)  ← same Team ID, embedded Info.plist
├── Contents/Resources/agentd/node       bundled Node 22 + agentd JS
└── Contents/Info.plist                  ALL usage strings (responsible process = this app)

Aloud ──spawn──▶ agentd (Node) ──spawn stdio──▶ macbridge
     ▲  JSON-RPC unix socket   │  MCP client                │ EventKit / CNContactStore / PhotoKit
     │  approvals, HUD         │  policy engine (Effects)    │ NSMetadataQuery / FSEvents
     └──── approval cards ◀────┘  audit JSONL                │ AXUIElement / CGEvent
                                                             │ ScreenCaptureKit / Vision
                                                             │ NSAppleScript (fixed script lib)
                                                             │ NSWorkspace / URL schemes / shortcuts
```

### A.3.1 Identity and TCC

- **Responsible process.** TCC attributes a child's access to its responsible ancestor ([Michael Tsai summary](https://mjtsai.com/blog/2025/07/07/the-curious-case-of-the-responsible-process/)). With the app → agentd → macbridge chain, every prompt says "Aloud". Put `NSAppleEventsUsageDescription`, `NSCalendarsFullAccessUsageDescription`, `NSRemindersFullAccessUsageDescription`, `NSContactsUsageDescription`, `NSPhotoLibraryUsageDescription` and the Screen Recording / Accessibility onboarding copy in the **app's** Info.plist. Give macbridge its own embedded Info.plist too (bundle id `ai.aloud.macbridge`) for standalone dev runs.
- **Entitlements** (hardened runtime): `com.apple.security.automation.apple-events`. Node needs `com.apple.security.cs.allow-jit` and possibly `allow-unsigned-executable-memory`, but **don't** give those to macbridge. Keeping the two binaries separate keeps the JIT entitlement off the binary that holds the personal-data access.
- **Pre-flight tool.** `permissions.status` returns `{automation:{Mail:granted,Notes:notDetermined}, accessibility:true, screen:false, calendars:"fullAccess", …}` using `AEDeterminePermissionToAutomateTarget`, `AXIsProcessTrusted`, `CGPreflightScreenCaptureAccess` and `EKEventStore.authorizationStatus`. The planner reads this before picking a route, so it never plans a step that will hit a prompt mid-task. A `permissions.request(kind)` tool is approval-gated and pops the prompt or deep-links to Settings.
- **Dev guard.** If `getppid()`'s responsible process isn't Aloud (for example agentd launched from Terminal), macbridge logs a loud warning, because grants would attach to Terminal.

### A.3.2 Tool contract

macbridge is written in Swift 6 with the official MCP Swift SDK or a minimal JSON-RPC stdio loop. Each tool carries metadata that agentd's policy engine consumes:

```jsonc
{
  "name": "calendar.events",
  "description": "List events in a time range",
  "inputSchema": { "type":"object", "properties": { "start":{"type":"string","format":"date-time"}, "end":{"type":"string","format":"date-time"}, "calendars":{"type":"array","items":{"type":"string"}} }, "required":["start","end"] },
  "annotations": { "readOnlyHint": true },
  "_meta": { "aloud/effect": "read_private", "aloud/tcc": ["calendars"], "aloud/reversible": true, "aloud/launches": [] }
}
```

agentd validates `_meta.aloud/effect` against an allowlist **compiled into agentd**, not trusted from the server. Unknown or missing values default to `execute_process`. That keeps the policy authoritative even if macbridge is swapped.

### A.3.3 Proposed tool catalogue (v1)

| Group | Tools | Effect |
|---|---|---|
| permissions | `permissions.status`, `permissions.request` | read_local / (approval) |
| context | `context.frontmost` (app, bundle, window, AX role of focused field, `AXSelectedText`), `context.selection_text`, `context.browser_tab` (URL, title, text via AS) | read_private |
| files | `spotlight.search` (typed predicate builder: kind, dateRange, from, text, tags, onlyIn), `files.metadata`, `files.move`, `files.copy`, `files.tag`, `files.trash` (NSWorkspace.recycle), `files.reveal` | read_local / write_local / trash_local / launch_app |
| watch | `watch.create_rule`, `watch.list`, `watch.disable` (FSEvents + rule DSL) | write_local |
| calendar | `calendar.events`, `calendar.free_busy`, `calendar.create_event`, `calendar.update_event` | read_private / write_local (+send_message if invitees) |
| reminders | `reminders.list`, `reminders.create`, `reminders.complete` | read_private / write_local |
| contacts | `contacts.resolve` (name → candidates with emails and phones) | read_private |
| photos | `photos.find` (date, location, media type, OCR text), `photos.export` | read_private / write_local |
| mail (Mail.app) | `mail.search`, `mail.read`, `mail.save_attachments`, `mail.draft` (open compose window, not send), `mail.send` | read_private / write_local / send_message |
| messages | `messages.send` | send_message (never voice-approved) |
| notes | `notes.search`, `notes.read`, `notes.create`, `notes.append` | read_private / write_local |
| shortcuts | `shortcuts.list` (Aloud folder only), `shortcuts.run` | read_local / per-tag or execute_process |
| apps and urls | `apps.open`, `apps.quit` (approval: unsaved work), `url.open` (scheme registry) | launch_app / open_url / write_local |
| windows | `windows.list`, `windows.arrange` (preset layouts), `windows.move_to_display`, `windows.undo_layout` | read_local / ui_input:window |
| screen | `screen.capture` (window, display, region; excludes HUD), `screen.ocr` (Vision; `RecognizeDocumentsRequest` on 26) | read_private |
| ui (AX) | `ui.snapshot` (pruned tree + element ids), `ui.press(id)`, `ui.set_value(id, text)`, `ui.menu(path)` | read_private / ui_input |
| computer | `computer_toolset_20260801` member implementations | ui_input + takeover approval |
| media and system | `media.playpause/next/prev`, `audio.volume`, `audio.output_device`, `system.toggle(name)` (allowlist), `focus.set(name)` (via tagged shortcut) | ui_input:media / system_settings:reversible |
| notify | `notify.post` (with action buttons tied to task id) | notify |
| clipboard | `clipboard.read` (detect first), `clipboard.write`, `clipboard.history.search` (opt-in) | read_private / write_local |
| applescript | `applescript.run` (raw script; full text in approval card) | execute_process |

### A.3.4 Policy changes in agentd

| New or changed effect | Meaning | Default approval |
|---|---|---|
| `read_private` | personal data or screen contents (mail, messages, calendar, contacts, photos, screen, selection, clipboard) | Auto after a **per-session category grant** ("Allow Aloud to read your calendar for this session?"). Results are tagged **tainted** (prompt-injection source). |
| `ui_input` | synthetic input or AX actions into other apps | Click approval per step, showing target app and element. `ui_input:window` and `ui_input:media` are auto. |
| `trash_local` | NSWorkspace.recycle into the Trash (reversible) | Click approval with a file list. Bulk (more than 20 files) requires typing or saying a confirmation count. |
| `system_settings:reversible` | allowlisted toggles with stored undo | Auto (voice OK). Everything else stays blocked. |
| `notify` | post a notification to the user | Auto |
| Taint rule | After any tainted read in a task, `send_message` / `network_write` steps must show the **exact payload** and the source of any included private data. Instructions found inside tainted content are never executed as plan steps. | Enforced |

Also add **dry-run plans** (from the plan backlog) for bulk file ops. macbridge returns a `plan` (list of moves) from `files.organize_plan`. The AgentPanel renders it as a diff, and one approval executes the whole batch atomically, with an undo log (`~/Library/Application Support/Aloud/undo/<task>.json`).

### A.3.5 Lifecycle and performance

- macbridge is long-lived (spawned once per agentd start), which keeps `EKEventStore`, compiled AppleScripts and AX observers warm.
- MCP `notifications/*` push FSEvents rule hits and AX focus changes to agentd.
- A crash leads to restart with backoff. A per-tool timeout (default 10 s; AX snapshot 3 s; computer step 30 s) feeds agentd's kill switch.
- Bench it: add `bench/macbridge/` scenarios such as permissions pre-flight, calendar query latency, Spotlight precision for "the PDF X sent", AX snapshot size and time for Slack/VS Code/Finder, and OCR accuracy on fixed screenshots. That turns the bridge into an **evaluated** component, matching the owner's evals-driven-development story.

---

## A.4 Voice task catalogue (36 tasks)

Difficulty: **S** means a single tool call; **M** means multi-step or entity resolution; **L** means fragile, UI-driven or needing rules.

| # | Utterance | Bridge(s) | Effect(s) | Approval | Diff. |
|---|---|---|---|---|---|
| 1 | "What's on my calendar after 3?" | EventKit `calendar.events` | read_private | auto (session grant) | S |
| 2 | "Am I free Thursday afternoon for an hour with Priya?" | EventKit free_busy + Contacts (+ Google Calendar MCP for work calendar) | read_private | auto | M |
| 3 | "Block 2 to 4 tomorrow for deep work" | EventKit create_event | write_local | click | S |
| 4 | "Remind me to call Mom when I get home" | EventKit reminder with location alarm | write_local | click | M |
| 5 | "What reminders are overdue?" | EventKit reminders.list | read_private | auto | S |
| 6 | "Find the PDF Priya sent last week" | Spotlight (`kMDItemWhereFroms`, date, type) → Mail.app attachment search fallback → Gmail MCP | read_local / read_private | auto | M |
| 7 | "Organize my Downloads by type" | Spotlight/listing → `files.organize_plan` → batch `files.move` | write_local | one approval on diff plan | M |
| 8 | "From now on, file every invoice PDF in Downloads into Finance/Invoices" | FSEvents watch rule + Vision OCR or text extraction classifier | write_local (rule) | approval at creation; digest after | L |
| 9 | "Delete the DMGs in Downloads older than a month" | Spotlight + NSWorkspace.recycle | trash_local | click with list | S |
| 10 | "Tag these files as tax 2026" | Finder selection (AS) + `files.tag` | write_local | click | S |
| 11 | "Open the deck I was working on yesterday" | Spotlight `kMDItemLastUsedDate` + NSWorkspace open | read_local, launch_app | auto | S |
| 12 | "Move this window to the left half" | AX windows.arrange | ui_input:window | auto | S |
| 13 | "Put Slack on my second monitor and make VS Code full screen" | AX + NSScreen | ui_input:window | auto | M |
| 14 | "Set up my coding layout" | AX layout preset + open apps | launch_app, ui_input:window | auto | M |
| 15 | "Summarize what's on my screen" | ScreenCaptureKit + Vision OCR (+ AX text) → Claude | read_private | auto (explicit "screen") | S |
| 16 | "Turn the table on screen into a spreadsheet" | ScreenCaptureKit + `RecognizeDocumentsRequest` (macOS 26) → write CSV, open Numbers | read_private, write_local | click for write | M |
| 17 | "What does this error dialog mean and how do I fix it?" | AX snapshot of front window (fallback OCR) | read_private | auto | S |
| 18 | "Summarize this page" (in Safari or Chrome) | AppleScript `do JavaScript` / tab text | read_private | auto | S |
| 19 | "Save this page to Obsidian under Reading" | Browser tab (AS) + `obsidian://new` | read_private, write_local | auto if scheme opted in | M |
| 20 | "Add 'renew passport' to Things for Friday" | Things URL scheme or Things shortcut | write_local | auto (opt-in) / click | S |
| 21 | "Append this to my 1:1 notes with Priya" | `context.selection_text` + Notes AS append | read_private, write_local | click | M |
| 22 | "Draft a reply to the last email from Sam saying I'll review tomorrow" | Mail.app AS search + draft (compose window opened, not sent), or Gmail MCP draft | read_private, write_local | click | M |
| 23 | "Send it" (after 22) | Mail `send` / Gmail send | send_message | click only, never voice | S |
| 24 | "Text my wife I'm leaving in 10 minutes" | Contacts resolve → Messages AS send | read_private, send_message | click, exact text shown | M |
| 25 | "Turn on Work focus until 6" | Tagged Shortcut "IF Focus Work" | system_settings:reversible | auto | S |
| 26 | "Dark mode on" / "Volume to 30" | System Events / CoreAudio | system_settings:reversible | auto | S |
| 27 | "Pause the music" / "Skip this song" | Media key CGEvent / Music AS | ui_input:media | auto | S |
| 28 | "Switch audio to my AirPods" | CoreAudio output device | system_settings:reversible | auto | S |
| 29 | "What did I copy a few minutes ago? Paste the link, not the text" | Opt-in clipboard history + InsertKit | read_private, write_local | auto | M |
| 30 | "Run my morning shortcut" | `shortcuts run` (tagged) | per tag | per tag | S |
| 31 | "Find photos of the whiteboard from Tuesday and OCR them into a note" | PhotoKit date fetch + Vision OCR + Notes create | read_private, write_local | click for note | M |
| 32 | "Quit everything except Xcode and Slack" | NSWorkspace runningApplications + terminate (unsaved check) | launch_app (quit) | click | S |
| 33 | "Rename the selected screenshots to 'checkout-flow-1, 2, 3…'" | Finder selection + `files.move` | write_local | click with diff | S |
| 34 | "In this Jira form, fill the summary with what I just said" | AX focused field `set_value` (Command mode) | ui_input | click | M |
| 35 | "Click 'Approve' on this pull request" (web) | Chrome/AX `ui.press` by element id; fallback computer use | ui_input (+ semantic: approve = network_write) | click + preview | L |
| 36 | "Export my Robinhood positions page to a CSV" | Computer use / AX over browser (no official API) → OCR or DOM → CSV | read_private, write_local | takeover approval; read-only, never trade (spend_money blocked) | L |
| 37 | "Join my next meeting" | EventKit next event → extract Zoom/Meet URL → `open` | read_private, open_url | auto | S |
| 38 | "Notify me when the Claude Code task in aloud finishes" | agentd task + `notify.post` | notify | auto | S |
| 39 | "Who's Priya's phone number?" | Contacts resolve | read_private | auto | S |
| 40 | "Make a reminder for every unanswered email from my manager this week" | Mail AS/Gmail MCP search + EventKit batch create | read_private, write_local | one approval on plan | M |

---

## A.5 Build order (suggested)

1. **macbridge skeleton.** Stdio MCP, the `permissions.*` tools, embedded plist, signing inside the app bundle, the responsible-process check, and the Effect metadata plus agentd allowlist.
2. **High-value structured reads.** EventKit, Contacts, Spotlight, `context.frontmost`/selection, and browser tab text. These cover tasks 1, 2, 5, 6, 11, 17, 18, 37 and 39.
3. **Writes with approval.** Calendar and reminders create, file move/tag/trash with dry-run plans plus undo, Notes append, and URL-scheme registry (Things, Obsidian, Raycast).
4. **Shortcuts bridge.** The Aloud folder, effect tags, and Focus via shortcuts.
5. **Screen context and AX.** ScreenCaptureKit + Vision, pruned AX snapshot, window arrange, and Command mode.
6. **FSEvents rules.** This is the standout "agentic OS" feature.
7. **Computer use** last, behind takeover approval, with AX-grounding.
8. The **bench/macbridge** eval suite throughout. Publish latency and accuracy per tool.

---

## Sources

- Apple, *Develop for Shortcuts and Spotlight with App Intents* (WWDC25-260): https://developer.apple.com/videos/play/wwdc2025/260/
- Apple, *Accessing the event store* (EventKit full / write-only access): https://developer.apple.com/documentation/eventkit/accessing-the-event-store
- Apple, *RecognizeDocumentsRequest* (Vision, macOS 26): https://developer.apple.com/documentation/vision/recognizedocumentsrequest
- Apple, *Spotlight Metadata Attributes*: https://developer.apple.com/library/content/documentation/CoreServices/Reference/MetadataAttributesRef/Reference/CommonAttrs.html
- Apple Support, *Run shortcuts from the command line*: https://support.apple.com/guide/shortcuts-mac/apd455c82f02/mac
- `shortcuts(1)` man page: https://keith.github.io/xcode-man-pages/shortcuts.1.html
- Anthropic, *Computer use tool*: https://platform.claude.com/docs/en/agents-and-tools/tool-use/computer-use-tool
- 9to5Mac, *macOS Tahoe 26.1 beta 1 MCP integration*: https://9to5mac.com/2025/09/22/macos-tahoe-26-1-beta-1-mcp-integration/
- Computerworld, *Apple to deploy MCP support*: https://www.computerworld.com/article/4061614/apple-to-deploy-mcp-support-for-powerful-ai-experiences.html
- 9to5Mac, *Sequoia screen recording prompt monthly*: https://9to5mac.com/2024/08/14/macos-sequoia-screen-recording-prompt-monthly/
- TidBITS, *Apple Reduces Excessive Sequoia Permission Requests*: https://tidbits.com/2024/08/19/apple-reduces-excessive-sequoia-permission-requests-shifts-to-monthly
- MacRumors, *Apple to Block Mac Apps From Secretly Accessing Your Clipboard*: https://www.macrumors.com/2025/05/12/apple-mac-apps-clipboard-change/
- Michael Tsai, pasteboard privacy notes: https://mjtsai.com/blog/2025/05/12/
- Michael Tsai, *The Curious Case of the Responsible Process*: https://mjtsai.com/blog/2025/07/07/the-curious-case-of-the-responsible-process/
- Peter Steinberger, *AppleScript CLI on macOS: stop fighting TCC*: https://steipete.me/posts/2025/applescript-cli-macos-complete-guide
- MacRumors, *Do More With Spotlight in macOS Tahoe*: https://www.macrumors.com/how-to/do-more-with-spotlight-in-macos-tahoe/
- Alex Chan, *Watching files on macOS (FSEvents)*: https://alexwlchan.net/2026/watch-files-on-macos/
- yabai wiki (SIP requirements): https://github.com/koekeishiya/yabai/wiki
- ungive/mediaremote-adapter (MediaRemote after 15.4): https://github.com/ungive/mediaremote-adapter
- Obsidian URI overview: https://www.dsebastien.net/obsidian-uri/
- MacStories, *Raycast adds deeplinking of commands*: https://www.macstories.net/stories/raycast-adds-deeplinking-of-commands/ ; Raycast changelog 1.47: https://www.raycast.com/changelog/1-47-0
- supermemoryai/apple-mcp: https://github.com/supermemoryai/apple-mcp/wiki
- mattt/iMCP: https://github.com/mattt/iMCP
- openclaw/Peekaboo: https://github.com/openclaw/Peekaboo
- steipete/macos-automator-mcp: https://github.com/steipete/macos-automator-mcp
- mediar-ai/mcp-server-macos-use: https://mcp.so/servers/mcp-server-macos-use
- adamrdrew/macos-accessibility-mcp: https://lobehub.com/ko/mcp/adamrdrew-macos-accessibility-mcp
- Jeomon/macos-mcp: https://www.getdrio.com/mcp/io-github-jeomon-macos-mcp/md
