# Behavior evals: baseline vs final

**Held-out test split** (198 cases never used for tuning): app 84% → **92%**, groq 82% → **92%**, haiku 87% → **94%**. `app` is what ships: Groq (gpt-oss-120b) first, Claude Haiku as fallback, with the app's timeouts.

## What is measured

Each case is a realistic speech-to-text transcript dictated into a specific app, labelled with what Aloud's cleanup must do there (`positive`: a transformation should happen, e.g. lay out a prompt, make a list, apply a self-correction, repair a misheard word) or must not do (`negative`: a look-alike that must be left alone). A case passes when the output has the expected layout, keeps every required phrase and contains no forbidden one. Spec and schema: [`behavior/SPEC.md`](../behavior/SPEC.md).

- **Dataset:** 660 cases, written per app group by separate agents from a shared spec, then audited case by case by three more agents (label fixes are recorded in each case's `audit` field; 5 ambiguous cases were dropped).
- **Splits (40/30/30, stratified by category, polarity and difficulty):** `train` is the prompt-construction set (its failures were read and few-shot examples come from it); `dev` chose between prompt variants and settings (scores only); `test` was scored for the baseline and once at the end. Cases read while debugging before this eval are never in `test`.
- **Setups:** `app` (the shipped chain), `groq` and `haiku` (each model alone, 8 s timeout).
- **Baseline:** the last pushed version before this work (commit `22bf7db`), run on the same cases with the same scorer.
- **Noise:** a repeat run of the same build moves a split's overall score by about ±1–2 points.

## Dataset

| category | positive easy | positive hard | negative easy | negative hard | total |
|---|---:|---:|---:|---:|---:|
| ai_chat | 19 | 9 | 4 | 13 | 45 |
| chat | 17 | 8 | 13 | 7 | 45 |
| email | 16 | 14 | 12 | 8 | 50 |
| fidelity | 17 | 17 | 5 | 16 | 55 |
| list_vs_sentences | 34 | 30 | 35 | 33 | 132 |
| misheard | 14 | 8 | 12 | 9 | 43 |
| prompt_vs_speech | 32 | 18 | 28 | 24 | 102 |
| self_correction | 38 | 42 | 28 | 29 | 137 |
| terminal | 18 | 12 | 12 | 9 | 51 |

**By split:** dev 195, test 198, train 267

**By length:** long 146, medium 280, short 234

**By app_group:** ai_apps 79, chat_apps 155, claude_code 78, codex 35, editor 46, email_apps 96, notes 73, terminal 55, todo 43

## Results on the held-out test split

### By category and polarity

| | app baseline | app final | groq baseline | groq final | haiku baseline | haiku final |
|---|---:|---:|---:|---:|---:|---:|
| all | 84% (167/198) | **92% (182/198)** | 82% (162/198) | **92% (183/198)** | 87% (173/198) | **94% (186/198)** |
| ai_chat | 100% (14/14) | **100% (14/14)** | 100% (14/14) | **100% (14/14)** | 100% (14/14) | **100% (14/14)** |
| &nbsp;&nbsp;positive | 100% (9/9) | **100% (9/9)** | 100% (9/9) | **100% (9/9)** | 100% (9/9) | **100% (9/9)** |
| &nbsp;&nbsp;negative | 100% (5/5) | **100% (5/5)** | 100% (5/5) | **100% (5/5)** | 100% (5/5) | **100% (5/5)** |
| chat | 85% (11/13) | **85% (11/13)** | 77% (10/13) | **85% (11/13)** | 92% (12/13) | **92% (12/13)** |
| &nbsp;&nbsp;positive | 71% (5/7) | **71% (5/7)** | 57% (4/7) | **71% (5/7)** | 100% (7/7) | **86% (6/7)** |
| &nbsp;&nbsp;negative | 100% (6/6) | **100% (6/6)** | 100% (6/6) | **100% (6/6)** | 83% (5/6) | **100% (6/6)** |
| email | 100% (15/15) | **93% (14/15)** | 93% (14/15) | **93% (14/15)** | 100% (15/15) | **100% (15/15)** |
| &nbsp;&nbsp;positive | 100% (9/9) | **89% (8/9)** | 89% (8/9) | **89% (8/9)** | 100% (9/9) | **100% (9/9)** |
| &nbsp;&nbsp;negative | 100% (6/6) | **100% (6/6)** | 100% (6/6) | **100% (6/6)** | 100% (6/6) | **100% (6/6)** |
| fidelity | 88% (15/17) | **76% (13/17)** | 88% (15/17) | **76% (13/17)** | 88% (15/17) | **94% (16/17)** |
| &nbsp;&nbsp;positive | 100% (10/10) | **80% (8/10)** | 100% (10/10) | **80% (8/10)** | 100% (10/10) | **100% (10/10)** |
| &nbsp;&nbsp;negative | 71% (5/7) | **71% (5/7)** | 71% (5/7) | **71% (5/7)** | 71% (5/7) | **86% (6/7)** |
| list_vs_sentences | 85% (33/39) | **92% (36/39)** | 85% (33/39) | **95% (37/39)** | 82% (32/39) | **90% (35/39)** |
| &nbsp;&nbsp;positive | 89% (17/19) | **89% (17/19)** | 89% (17/19) | **89% (17/19)** | 84% (16/19) | **84% (16/19)** |
| &nbsp;&nbsp;negative | 80% (16/20) | **95% (19/20)** | 80% (16/20) | **100% (20/20)** | 80% (16/20) | **95% (19/20)** |
| misheard | 85% (11/13) | **100% (13/13)** | 85% (11/13) | **92% (12/13)** | 92% (12/13) | **100% (13/13)** |
| &nbsp;&nbsp;positive | 83% (5/6) | **100% (6/6)** | 83% (5/6) | **83% (5/6)** | 100% (6/6) | **100% (6/6)** |
| &nbsp;&nbsp;negative | 86% (6/7) | **100% (7/7)** | 86% (6/7) | **100% (7/7)** | 86% (6/7) | **100% (7/7)** |
| prompt_vs_speech | 97% (29/30) | **100% (30/30)** | 90% (27/30) | **100% (30/30)** | 97% (29/30) | **97% (29/30)** |
| &nbsp;&nbsp;positive | 93% (14/15) | **100% (15/15)** | 80% (12/15) | **100% (15/15)** | 93% (14/15) | **100% (15/15)** |
| &nbsp;&nbsp;negative | 100% (15/15) | **100% (15/15)** | 100% (15/15) | **100% (15/15)** | 100% (15/15) | **93% (14/15)** |
| self_correction | 56% (23/41) | **85% (35/41)** | 56% (23/41) | **88% (36/41)** | 68% (28/41) | **88% (36/41)** |
| &nbsp;&nbsp;positive | 29% (7/24) | **79% (19/24)** | 29% (7/24) | **79% (19/24)** | 46% (11/24) | **79% (19/24)** |
| &nbsp;&nbsp;negative | 94% (16/17) | **94% (16/17)** | 94% (16/17) | **100% (17/17)** | 100% (17/17) | **100% (17/17)** |
| terminal | 100% (16/16) | **100% (16/16)** | 94% (15/16) | **100% (16/16)** | 100% (16/16) | **100% (16/16)** |
| &nbsp;&nbsp;positive | 100% (9/9) | **100% (9/9)** | 89% (8/9) | **100% (9/9)** | 100% (9/9) | **100% (9/9)** |
| &nbsp;&nbsp;negative | 100% (7/7) | **100% (7/7)** | 100% (7/7) | **100% (7/7)** | 100% (7/7) | **100% (7/7)** |

### By polarity, difficulty and length

| | app baseline | app final | groq baseline | groq final | haiku baseline | haiku final |
|---|---:|---:|---:|---:|---:|---:|
| positive | 79% (85/108) | **89% (96/108)** | 74% (80/108) | **88% (95/108)** | 84% (91/108) | **92% (99/108)** |
| negative | 91% (82/90) | **96% (86/90)** | 91% (82/90) | **98% (88/90)** | 91% (82/90) | **97% (87/90)** |
| easy | 89% (94/106) | **94% (100/106)** | 86% (91/106) | **93% (99/106)** | 91% (96/106) | **96% (102/106)** |
| hard | 79% (73/92) | **89% (82/92)** | 77% (71/92) | **91% (84/92)** | 84% (77/92) | **91% (84/92)** |
| easy positive | 82% (50/61) | **90% (55/61)** | 77% (47/61) | **89% (54/61)** | 87% (53/61) | **95% (58/61)** |
| easy negative | 98% (44/45) | **100% (45/45)** | 98% (44/45) | **100% (45/45)** | 96% (43/45) | **98% (44/45)** |
| hard positive | 74% (35/47) | **87% (41/47)** | 70% (33/47) | **87% (41/47)** | 81% (38/47) | **87% (41/47)** |
| hard negative | 84% (38/45) | **91% (41/45)** | 84% (38/45) | **96% (43/45)** | 87% (39/45) | **96% (43/45)** |
| short | 85% (70/82) | **94% (77/82)** | 84% (69/82) | **91% (75/82)** | 85% (70/82) | **93% (76/82)** |
| medium | 87% (61/70) | **94% (66/70)** | 84% (59/70) | **96% (67/70)** | 89% (62/70) | **96% (67/70)** |
| long | 78% (36/46) | **85% (39/46)** | 74% (34/46) | **89% (41/46)** | 89% (41/46) | **93% (43/46)** |

### By app group

| | app baseline | app final | groq baseline | groq final | haiku baseline | haiku final |
|---|---:|---:|---:|---:|---:|---:|
| claude_code | 82% (18/22) | **100% (22/22)** | 77% (17/22) | **95% (21/22)** | 91% (20/22) | **95% (21/22)** |
| codex | 94% (17/18) | **94% (17/18)** | 89% (16/18) | **94% (17/18)** | 94% (17/18) | **100% (18/18)** |
| editor | 100% (8/8) | **88% (7/8)** | 100% (8/8) | **88% (7/8)** | 100% (8/8) | **100% (8/8)** |
| terminal | 94% (16/17) | **94% (16/17)** | 88% (15/17) | **94% (16/17)** | 94% (16/17) | **94% (16/17)** |
| ai_apps | 92% (24/26) | **92% (24/26)** | 92% (24/26) | **92% (24/26)** | 96% (25/26) | **96% (25/26)** |
| chat_apps | 76% (31/41) | **88% (36/41)** | 73% (30/41) | **90% (37/41)** | 85% (35/41) | **88% (36/41)** |
| email_apps | 87% (26/30) | **87% (26/30)** | 83% (25/30) | **90% (27/30)** | 87% (26/30) | **97% (29/30)** |
| notes | 95% (18/19) | **100% (19/19)** | 95% (18/19) | **100% (19/19)** | 95% (18/19) | **100% (19/19)** |
| todo | 53% (9/17) | **88% (15/17)** | 53% (9/17) | **88% (15/17)** | 47% (8/17) | **82% (14/17)** |

### Latency (test split, ms)

| | p50 baseline | p50 final | p95 baseline | p95 final |
|---|---:|---:|---:|---:|
| app | 513 | 480 | 1341 | 1186 |
| groq | 485 | 501 | 939 | 824 |
| haiku | 1541 | 1653 | 2024 | 2084 |

A second run of the final build on the test split (`app`): 92% (183/198).

## Train and dev (for completeness)

| split | app baseline | app final | groq baseline | groq final | haiku baseline | haiku final |
|---|---:|---:|---:|---:|---:|---:|
| train | 82% (220/267) | **96% (256/267)** | 82% (220/267) | **95% (253/267)** | 87% (231/267) | **97% (258/267)** |
| dev | 78% (152/195) | **92% (179/195)** | 76% (148/195) | **90% (176/195)** | 83% (161/195) | **93% (182/195)** |

## How the gains were made (tuning log, dev split, `app` setup)

| step | change | dev | decision |
|---|---|---|---|
| baseline | Last pushed version (22bf7db): model decides layout with no stated decision, correction leniency from fixed cue words, rule-based list/prompt shortcuts. | 78% | reference |
| current | Work before the expanded eval: model states its layout (<layout>), reports self-corrections (<correction>) that the guardrail verifies, few-shot positives and negatives for corrections, prompt layout and lists; misheard-word repair; fixed scorer. | 92% | starting point for tuning |
| E1 | Bug fixes: a correction may legitimately repeat a replaced word later (count-based check); spoken symbols don't count as lost words in shell commands. | 91% / 91% | kept (correctness; within noise) |
| E2 | Only corrections the model reported and that verify loosen the guardrail (no fixed cue-word list). | 92% / 92% | kept (same score, the model decides instead of a word list) |
| E3 | E2 without the misheard-word repair pass. | 90% / 91%; misheard 75%; p50 330 ms | rejected (repair is worth ~200 ms) |
| E4 | E2 with Groq reasoning effort medium. | 94% / 93%; p50 1.1 s, p95 2.6 s | rejected (+1-2 points for double the latency) |
| E5 | E2 plus few-shot examples drawn from the train split: correction followed by a reason, 'no' and 'sorry' that are not corrections, stacked hedges, chat slang, to-do lists, an email checklist, a shell correction. | 94% / 92%; Haiku alone 92% -> 95% | kept |
| E6 | E5 plus more train-sourced examples (correction a sentence later, numbered steps in Notes, repair negatives) and a 'keep units as spoken' rule. | 92% / 92%; corrections 93% -> 88% / 85%; train 96% -> 97% | rejected (overfit: train up, dev down) |
| final | E5 + email title fix ('Dear Ms. Varga'); verified-only corrections made the app default. | 93% / 93% | shipped |

## Known gaps

- **Fidelity** fell on the held-out split (app chain 88% → 76%, 2 cases) and was the weakest category on dev
  too: the model sometimes drops a stacked hedge or abbreviates a word. A rule for it overfit on dev (step E6),
  so it needs better examples, not another rule. It is the next thing to work on.
- One email and one code-editor case regressed on test; both are single cases.

## Limits

- Transcripts are written to look like ElevenLabs Scribe output; they are not recordings. Recognition errors on real audio are measured separately (`scenario_eval.py replay`, BENCHMARKS.md).
- The cases and their audit were written by language models from a shared spec; labels are checked automatically and by a second model, not by people.
- Each score is from one run; per-category test sets are 6–40 cases, so a single case can move a cell by several points.

## Reproduce

```
cd bench
python3 behavior_eval.py build
python3 behavior_eval.py run --name final --config app --split all     # also --config groq / haiku
python3 behavior_eval.py publish --baseline baseline --final final
```
