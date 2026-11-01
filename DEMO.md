# Demo script

A 3-minute run-through of what Aloud does, built only from features that work today. Each beat says what
to say, what the audience sees, and what to set up beforehand.

## Before you start

- **Allowed folders** (menu bar ▸ Agent Settings…): your projects folder and `~/Desktop`. Add
  `~/Downloads` too for beat 5.
- **Desktop access:** the first time the agent looks at the Desktop, macOS asks whether Aloud may access
  your Desktop folder. Do one dry run beforehand so the prompt doesn't appear on camera.
- **A messy Desktop:** a few screenshots, a PDF or two, a zip, a .dmg, some loose notes. Real clutter
  reads better than a staged one.
- **Hide distractions:** turn on Do Not Disturb and close other notification sources.
- **Run each beat once off camera:** the agent's choices are consistent but not identical between runs.

## The run

**1. Dictation that keeps your words (20 s).** In Slack or Notes, hold Right Shift and talk naturally,
with an "um" and a self-correction: "Let's meet Tuesday, no, Wednesday at three." The pill at the bottom
shows a live waveform moving with your voice. Release: clean text, with the correction applied and the
filler gone, but your own wording kept.

**2. Same voice, different app (20 s).** Switch to Claude Code in the terminal and ramble a long
request ending in "… as a prompt". It arrives laid out as Goal / Context / Constraints. The point:
Aloud knows where you're typing.

**3. Talk to your computer: tidy the Desktop (45 s).** Hold Right Shift, add Right ⌘ (the waveform
turns orange), and say "organize my desktop". The island drops from the notch, shows the plan, lists
the Desktop, then turns into one approval card: "Organize 14 items in Desktop", with every move grouped
by destination folder and the new folders marked. Click Approve and the Desktop rearranges itself. Then
say "undo that": one more card and everything goes back.

**4. Hand code to an agent by voice (45 s).** Right Shift + Right ⌘: "In aloud, run the tests in
agentd." The island shows the exact command and a medium-risk badge. Approve, and the summary comes
back ("42 passed"). Open Task Center (⌘T from the menu) to show the full timeline: plan, steps,
timings, tokens.

**5. Guardrails (20 s).** Say "delete everything on my desktop". It refuses: deleting is never allowed
from a spoken task, approved or not. This is the trust story: every change is previewed, risky ones
are labelled, nothing destructive is possible, and everything is in an audit log.

## More agentic ideas to showcase

Each of these works with today's tools. The tools involved are in brackets.

| Say | What happens | Why it lands |
|---|---|---|
| "Clean up my Downloads: installers, archives and anything older than three months into an Archive folder" | Lists with dates, one grouped approval, undoable [list_dir details, organize_files] | Everyone has a messy Downloads folder |
| "Write a standup note on my desktop with what I changed today in aloud" | Reads git log, writes `~/Desktop/standup.md` with a diff preview [run_shell git, write_file] | Voice → real artifact in seconds |
| "What's the status of the aloud repo?" | Branch, uncommitted changes, last commits, read aloud in the island [run_shell git] | Zero-click awareness |
| "In aloud, make the Task Center window remember its last filter" | Delegated to Claude Code with edits only; the result shows in Task Center [claude_code_task] | Voice as the interface to coding agents |
| "Find the PDF about the YC application and open it" | Spotlight search inside allowed folders, then opens it [search_files, open_app] | Finding things by meaning, not by path |
| "Open the Aloud results page" | Opens the published eval page [open_url] | Shows the measured-accuracy story |
| "Group my screenshots on the desktop by month" | Uses modification dates to make `Screenshots/2026-10`, … [list_dir details, organize_files] | Visible, satisfying change |

Ideas that would need new work (good roadmap slides, not live demos yet):

- **Calendar and mail by voice** ("move my 3 pm to tomorrow"): needs calendar/mail connectors, with
  sending kept click-only.
- **Voice approvals** ("yes, do it") so the whole loop is hands-free; the policy already marks which
  steps must stay click-only.
- **Arranging icons** (sort the Desktop by kind or date in Finder): needs Finder automation, which
  asks for one more macOS permission.
- **Live Claude Code progress and diffs** in the island while it edits.
