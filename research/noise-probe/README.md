# Scribe noise probes (2026-10-31)

Scripts used for the noise findings in `research/06-intent-aware-cleanup.md` ("Field test 2026-10-31 and noise resilience"):
word logprobs (`include_timestamps`), `filter_background_audio`, and chat keyterms against TTS speech with a second speaker mixed in.
Run from `bench/` with `uv run python -I ../research/noise-probe/p3.py <speech.wav> <babble.wav>`. Reads the ElevenLabs key from
`~/Library/Application Support/InstructFlow/keys.env`.
