# InstructFlow benchmarks

```bash
cd voice-flow/bench
uv run python build_dataset.py                       # LibriSpeech sample + synthetic tech/filler clips -> data/manifest.jsonl
uv run python stt_bench.py --engines parakeet,whisper_turbo,eleven_batch,eleven_rt,groq_turbo
uv run python stt_bench.py --engines parakeet,eleven_batch --sets tech,filler --keyterms
uv run python cleanup_bench.py --engines qwen3_1.7b,qwen3_4b,groq_gptoss20b,haiku55
```

Cloud engines need keys in `voice-flow/.env` (see `.env.example`); they are skipped otherwise.
Results land in `results/` (per-item CSV/JSONL + summary JSON); the summary table is printed at the end.

Caveats: `tech`/`filler` audio is macOS `say` TTS, not your voice; latency here is in-process
(no mic, no insertion), so the app adds capture/insert overhead on top. Your own recordings
(PLAN.md §10) are the real acceptance set.

## Scenario evals (end to end, your voice, the real app)

`scenarios.jsonl` has 37 scenarios across every mode (notes, lists, email, chat, AI chat, coding agent,
shell), including self-corrections, negations, numbers, slang, stutters and five background-noise
variants. Each one gives where to dictate, what to say, the expected text and checks.

```bash
uv run python scenario_eval.py run                  # guided: shows each scenario, reads what the app heard and typed
uv run python scenario_eval.py run --tags noise     # a subset (--only ids, --mode email, --redo)
uv run python scenario_eval.py report               # results/scenario-report-<session>.md + .json
uv run python scenario_eval.py import observed.tsv  # results copied by hand: id<TAB>observed[<TAB>heard]
```

The app writes one JSON line per dictation to `~/Library/Logs/InstructFlow/dictations.jsonl` (what
speech-to-text heard, what was typed, the app, the mode, latency), which `run` pairs with the scenario
on screen. Sessions are named by date (`--session` to choose) and resume where you left off.

| Metric | Compares | What it shows |
|---|---|---|
| STT WER / CER | heard vs the script | speech-to-text accuracy (normalized: case, punctuation, number spelling) |
| Output WER / CER | typed vs expected, normalized | did the right words end up on screen |
| Strict CER | typed vs expected, exact characters | formatting: lists, email layout, `-b` flags, line breaks |
| Novel-word rate | typed content words not said | made-up words (an LLM rewording, or a mishearing like "love" for "lol") |
| Kept-word recall | expected content words present | dropped words |
| Pass rate | must / must-not, layout, negations, numbers, mode | the scenario's behaviour overall |
| Latency p50 / p95 | key-up to text typed | speed |

**No human needed:** `uv run python scenario_eval.py replay` speaks every scenario with macOS text-to-speech
(noise scenarios get another LibriSpeech speaker mixed in at 5 dB SNR), sends it to live Scribe with the
app's settings and keyterms, and runs the app's own cleanup code (`ScenarioReplay` Swift test: same Groq →
Haiku chain, timeouts and dictionary). It skips only the mic and the typing, so latency is speech-to-text
+ cleanup. Synthetic voices mishear some things a real voice wouldn't (shell commands, "btw"); confirm with `run`.

`results/scenario-report-baseline-1031.md` scores the 2026-10-31 field test (before the fixes from it)
as the baseline to compare against.
