# Behavior dataset

Labelled dictations that say what Aloud's cleanup should do, and what it must not do, in each kind of
app. Used to measure and improve the cleanup prompts as a whole instead of fixing one bug at a time.

- `cases.jsonl`: the dataset, one JSON object per line (built from `parts/*.jsonl`).
- `split` (assigned by `behavior_eval.py build`): `train` (the prompt-construction set: failures are read
  and few-shot examples are drawn from it), `dev` (used to choose between prompt variants and settings: scores
  only), `test` (held out: scored for the baseline and once at the end, never used for tuning). Cases read
  while debugging earlier never go to `test`.
- Run and score: `bench/behavior_eval.py` (see its `--help`).

## Schema (one line per case)

```json
{"id": "corr-012", "category": "self_correction", "polarity": "positive", "difficulty": "easy",
 "app": "WhatsApp", "bundle": "net.whatsapp.WhatsApp", "title": "",
 "say": "can you grab some apples. no, pears",
 "format": "paragraph", "must": ["pears"], "must_not": ["apples"],
 "why": "bare 'no, <same kind of thing>' replaces the item"}
```

| Field | Meaning |
|---|---|
| `id` | `<prefix>-<3 digits>`, unique. Original prefixes: `code`, `list`, `corr`, `chat`, `mail`, `ai`, `term`, `heard`. Expansion files use their own prefix per app group (given in the task) |
| `category` | `prompt_vs_speech`, `list_vs_sentences`, `self_correction`, `chat`, `email`, `ai_chat`, `terminal`, `misheard`, `fidelity` (negations, numbers, hedges, names kept; fillers removed) |
| `difficulty` | `easy`: a clear signal (explicit cue, clean text, obvious intent). `hard`: a near miss (looks like the other polarity), no cue, long or noisy, mixed signals, or several behaviours at once |
| `polarity` | `positive`: the transformation should happen (lay out a prompt, make a list, apply a correction, repair a word). `negative`: a look-alike where it must NOT happen |
| `app`, `bundle`, `title` | Where the text is dictated. Use only bundle IDs from the table below |
| `say` | What speech-to-text produced (see style) |
| `format` | Expected layout: `prompt` (starts with `Goal:`), `paragraph` (sentences: no bullets, no labels), `list` (2+ bullet or numbered lines), `email` (greeting / body / sign-off as separate paragraphs, only when spoken), `single_line` (a shell command: one line, no final period), `any` (layout not judged) |
| `must` | Phrases that must appear in the output (case-insensitive, whole words; a trailing plural s still matches) |
| `must_not` | Phrases that must not appear |
| `why` | One line: the behaviour this case tests |

## Style of `say`

Lengths are computed by the build (short ≤12 words, medium 13–40, long >40); write a mix of all three.
Realistic speech-to-text output from ElevenLabs Scribe: usually punctuated and capitalized, sometimes not
(mix both, about half each). Include fillers ("um", "uh", "like", "you know") in about a third of cases,
false starts and repeated words in some. Numbers as Scribe writes them: times often "7:00", other numbers
sometimes digits, sometimes words. Vary length (4 to 80 words), topic (work, home, travel, shopping, code,
family, health, money) and tone. No real people's private data; first names are fine.

## Writing `must` / `must_not` so they score fairly

- `must`: 1 to 4 content phrases that any good output keeps, in a form the output will use. Avoid numbers in
  `must` unless `say` already has them as digits (cleanup writes spoken numbers as digits: "seven" may
  become "7"). Avoid exact punctuation or capitalization.
- `must_not`: the replaced words in a correction (give both spellings if it's a number: `["7", "seven"]`),
  fillers that must go (`"um"`, `"uh"`), an answer the model must not write, words that must not be added.
- A negative case's `must` usually holds the words a wrong transformation would delete ("No", "actually",
  both items of an addition).
- Never require a word the speaker didn't say.

## App bundle IDs

| App | bundle | title |
|---|---|---|
| Claude Code CLI in Terminal | `com.apple.Terminal` | `myrepo — ✳ claude — 120×40` (vary the repo) |
| Claude Code CLI in Ghostty | `com.mitchellh.ghostty` | `✳ claude — myrepo` |
| Codex app | `com.openai.codex` | `` |
| Cursor | `com.todesktop.230313mzl4w4u92` | `auth.ts — myrepo` |
| VS Code | `com.microsoft.VSCode` | `server.py — myrepo` |
| Terminal at a plain shell | `com.apple.Terminal` | `~/myrepo — -zsh — 80×24` |
| WhatsApp | `net.whatsapp.WhatsApp` | `` |
| Slack | `com.tinyspeck.slackmacgap` | `` |
| Messages | `com.apple.MobileSMS` | `` |
| Mail | `com.apple.mail` | `` |
| Gmail in Chrome | `com.google.Chrome` | `Inbox (3) - me@example.com - Gmail` |
| Notes | `com.apple.Notes` | `` |
| Reminders | `com.apple.reminders` | `` |
| Claude desktop | `com.anthropic.claudefordesktop` | `` |
| ChatGPT | `com.openai.chat` | `` |

## Do not reuse

The cleanup prompt's own few-shot examples (a case that copies one measures memory, not judgement):
tuesday/wednesday meeting; table for four/five; invoice to Mark/Julia; blue/red folder; launch on the
fifth/sixth; dentist Tuesday/Thursday; latte/flat white; "is the build ready? no"; "ship it today";
"liked the first design"; eggs and milk and also bread; write me the summary of yesterday's sync; poem
about the sea; move the launch / docs are ready; process vs thread; validates the email field / signup
form; payments service / unused imports / billing module; auth check dot ts / refresh handler; user table
migration / old columns; new build / settings page flickers; get hub / jason; control see.
