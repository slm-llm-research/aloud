# 04 — STT + LLM Post-Processing Options for a macOS Push-to-Talk Dictation App

*Research date: 2026-10-30. Target: Apple Silicon Mac, English (with technical/coding vocabulary), 3–30 s utterances, under ~500–700 ms from key-up to inserted text.*

**How to read the numbers**
- **[V]** = vendor-claimed (model card, vendor blog, vendor docs).
- **[I]** = independently measured (Artificial Analysis, HF Open ASR Leaderboard, community benchmark repos, third-party tests).
- **[E]** = estimate or derived by me (arithmetic from other numbers). Not measured.
- Leaderboard WERs are **not comparable across leaderboards**. LibriSpeech test-clean is near-saturated (~1.5–2.5% for every good model). The HF Open ASR average (~5–7%) and Artificial Analysis AA-WER v2 (~2–6%; agent-talk + VoxPopuli + Earnings22) use different data and normalisation. Compare models only within one column.
- Several sources disagree. Where they do, I give the range and say so. Re-verify prices on the vendor page before you commit.

---

## TL;DR recommendation

| Role | Choice | Why |
|---|---|---|
| **Primary STT** | **ElevenLabs Scribe v2 Realtime** over WebSocket. Stream mic audio *while the key is held*. Send a manual `commit` on key-up. Add up to 50 keyterms from the project/codebase. | Scribe v2 (batch) has the best AA-WER on the independent leaderboard (2.2% [I]). The Realtime variant claims ~150 ms latency [V]. You already have keys. Price $0.39/h + $0.08/h for keyterms [V, official pricing]. |
| **Local fallback (also the offline/privacy mode)** | **NVIDIA Parakeet TDT 0.6B v2 (English) via FluidAudio (CoreML/ANE, Swift)**. Run it *in parallel* on the same buffered audio. | ~0.19 s for a short clip on an M4 [I, community speedtest]. 146× RTFx on M4 Pro and 2.1% LibriSpeech-clean [V]. Has CTC vocabulary boosting. Apache/MIT-style licence (CC-BY-4.0 weights). Uses the ANE, which leaves the GPU free for a local LLM. |
| **Hedge policy** | On key-up, take the cloud final if it arrives within ~350 ms. Otherwise take the local Parakeet result, which should be ready by then. | Removes the network tail from p95. |
| **Cleanup LLM (default mode)** | **Groq `openai/gpt-oss-20b` (reasoning_effort=low)** or **`llama-3.1-8b-instant`**. Alternatives: **Claude Haiku 5.5** at low effort, or Gemini 3.1 Flash-Lite. Skip the LLM entirely for short or clean utterances. | ~1000 tok/s [V, Groq docs] and ~0.7 s first chunk measured by AA with default reasoning [I]. A 60–120-token cleanup finishes in ~0.1 s of decode. TTFT dominates, so the prompt prefix must be warm and cached. |
| **"Coding-agent restructure" mode** | **Cerebras `gpt-oss-120b`** (~3000 tok/s [V]) or **Claude Haiku 5.5 / Sonnet 5.5**. Stream output into the target app. | Restructuring needs more reasoning. The user explicitly opts in, so a ~1–1.5 s budget is acceptable if tokens stream. |
| **Local LLM (offline)** | Qwen3-4B-Instruct-2507 4-bit via mlx-lm (135 tok/s gen, 1600 tok/s prefill on M4 Max [I]), or Qwen3-1.7B for lower latency. | Fits the budget only for short outputs. Use it offline, not as the default. |

Expected end-to-end with the primary path [E]: STT final 150–300 ms after key-up, then cleanup LLM 250–450 ms, then insert 20–50 ms. That gives **~450–800 ms p50**. Skipping the LLM gives **~200–350 ms**.

---

## A. Local STT on Apple Silicon

### A.1 Comparison table (local)

| Engine / model | Accuracy | Speed on M-series | Streaming | Size / RAM | Licence | Integration | Custom vocab / prompt |
|---|---|---|---|---|---|---|---|
| **Parakeet TDT 0.6B v2 (EN) — FluidAudio CoreML/ANE** | LibriSpeech-clean 2.1% WER (FluidAudio bench, M4 Pro) [V]. HF Open ASR avg ~6.0–6.05% [I]. AA-WER 6.4% (NVIDIA-hosted) [I] | 145.8× RTFx on LS-clean, M4 Pro [V]. **0.19 s** per test clip on an M4 24 GB, fastest of 9 engines [I, mac-whisper-speedtest] | Batch, plus sliding-window manager. Separate **Parakeet EOU 120M** streaming model: 4.87% WER at 320 ms chunks [V] | ~0.6B params, a few hundred MB CoreML | Weights CC-BY-4.0. FluidAudio Apache-2.0 | **Swift SPM**, CLI. macOS 14+/iOS 17+ | **CTC vocabulary boosting**: 99.3% precision / 85.2% recall on Earnings22 terms [V] |
| **Parakeet TDT 0.6B v3 (25 langs)** | Avg 6.32–6.34% on HF Open ASR (model card / leaderboard paper) [V/I]. AA-WER 4.5% (Together-hosted) [I]. FluidAudio LS-clean 2.5% [V] | 155–210× RTFx M4 Pro (FluidAudio) [V]. ~110–190× quoted in different READMEs [V] | as above | same | CC-BY-4.0 | FluidAudio / parakeet-mlx | as above |
| **parakeet-mlx (Python, MLX GPU)** | same weights | 0.50 s on the same M4 test clip, about 2.6× slower than CoreML [I]. 73× RTFx on M3 Max for an MLX port (sonic-speech card) [V] | chunked streaming API | ~2–3 GB peak | Apache-2.0 | Python, CLI | none built-in |
| **WhisperKit (Argmax OSS SDK, CoreML/ANE)** | Paper: large-v3-turbo streaming, confirmed WER ~2.2% on TIMIT [V, ICML'25 paper] | Paper: hypothesis latency **0.46 s**, confirmed-text ~1.7 s (M3 Max) [V]. Encoder 612 ms → 218 ms with a block-diagonal mask (M3 Max ANE) [V]. Community: large-v3 2.2 s on M4 [I] (non-turbo, so slow) | **Yes**: real-time streaming with hypothesis/confirmed text | turbo ~0.8B, ~1.6 GB CoreML (quantized variants smaller) | MIT (OSS). **Parakeet in WhisperKit is Pro-only (paid)** | **Swift SPM** (now `argmax-oss-swift`) | Whisper `prompt`/prefix tokens |
| **whisper.cpp (Metal + optional CoreML encoder)** | large-v3-turbo ≈ HF Open ASR ~7.8% avg [I, leaderboard; same as reference turbo] | 1.23 s (turbo q5_0) on the M4 test clip [I] | `stream` example (sliding window, crude) | turbo q5 ~550 MB | MIT | C/C++, CLI, Swift bindings | `--prompt` initial prompt. GBNF grammars |
| **mlx-whisper (Apple MLX)** | same as turbo | **1.02 s** on the M4 clip, fastest Whisper variant there [I] | no native | ~1.6 GB fp16 | MIT | Python | `initial_prompt` |
| **lightning-whisper-mlx** | distil/large variants | 1.82 s on the M4 clip [I], so the "10× faster" claim [V] did not hold there | no | — | MIT | Python | limited |
| **faster-whisper (CTranslate2)** | same as Whisper | **CPU only on Mac (no Metal)**. 6.96 s on the M4 clip [I] | no | — | MIT | Python | `initial_prompt`, `hotwords` |
| **distil-whisper large-v3 / v3.5** | ~1 pt worse WER than large-v3 on long form [V] | ~1.5–2× faster than turbo on the decoder side [V] | no | 756M | MIT | via whisper.cpp / MLX | prompt |
| **Moonshine v2 (streaming, Useful Sensors)** | Medium-streaming 6.65%, Small 7.84%, Tiny 12.0% avg WER [V, via README/blog] | Latency 34 / 73 / 107 ms (CPU, MacBook Pro) [V]. ~50/148/258 ms on M3 per a paper summary [V] | **Yes**, constant TTFT regardless of length (ergodic encoder) [V] | 27M–~250M params | MIT (EN models) | Python, C++, ONNX | none |
| **Apple SpeechAnalyzer / SpeechTranscriber (macOS 26)** | LS-clean 2.12%, harder speech 4.56% (Inscribe, M2 Pro) [I]. 1.98% vs whisper.cpp small 4.28% (IraVoice, 40 speakers, vendor of a dictation app) [I, commercial interest]. **Apple publishes no WER** | ~3× faster than Whisper-small (no exact timings published) [I] | **Yes**, volatile + final results | OS-managed asset, ~0 app RAM | OS API, free | **Swift only**, macOS 26+ | `contextualStrings` (≤100 phrases) **only helps `DictationTranscriber`, not `SpeechTranscriber`** (Apple forum answer) [V] |
| **Kyutai STT (delayed-streams)** | Kyutai claims the 2.6B matches non-streaming models [V]. Only the 2.6B was benchmarked | 1B en/fr: **0.5 s delay**. 2.6B en: 2.5 s delay [V] | **Yes**, native | 1B / 2.6B | CC-BY-4.0 (weights), MIT/Apache code | **MLX** (`moshi_mlx`), Rust, Swift (moshi-swift) | none |
| **Qwen3-ASR 0.6B / 1.7B (MLX ports)** | HF Open ASR (Oct 2026 update) puts 1.7B at the top of the English track, ~5.40% avg [I, secondary]. mlx-qwen3-asr: 0.6B LS-clean 2.29% (RTF 0.096), 1.7B 1.99% (RTF 0.27) on M4 Pro [V/I community] | 0.6B 5-bit RTF 0.014 on M5 Pro (speech-swift) [V] | partial | 0.6B ~1 GB, 1.7B ~1.9 GB peak (5-bit) | Apache-2.0 | Python MLX, Swift (soniqo speech-swift) | LLM-based, so it accepts context text (biasing support in the MLX ports not confirmed) |
| **NVIDIA Canary-Qwen-2.5B** | 5.63% HF Open ASR avg (was #1 in mid-2025) [I]. AA-WER 4.3% [I] | Slow on Mac (LLM decoder). AA speed factor 8.4× on Replicate GPU [I] | no | 2.5B | CC-BY-4.0 | NeMo (no good Mac path) | prompt |
| **IBM Granite Speech 4.1 / 5.0 2B** | 4.1: 5.96% HF avg [I, secondary]. 5.0 2B: 5.06% (IBM chart) [V] | LLM-based, slower | no | 2B | Apache-2.0 | transformers | prompt |
| **Voxtral Mini 4B Realtime (open, Apache-2.0)** | Paper: at 480 ms delay, competitive with Scribe v2 Realtime [V] | Needs a ≥16 GB GPU in BF16 per the vLLM recipe [V]. Unproven on Mac | **Yes**, configurable delay down to sub-200 ms [V] | 4.4B | Apache-2.0 | vLLM. ONNX community port exists | prompt |

**Local takeaways**
1. **Parakeet on the ANE (FluidAudio) is the local speed king** by a wide margin. A 30 s clip should take ~0.2–0.3 s [E from 146× RTFx], so batch is fine for push-to-talk. No streaming is needed. It is also more accurate than Whisper-turbo on the leaderboard average.
2. **Whisper engines are 5–6× slower** for similar or worse accuracy. Keep them only if you need Whisper's prompting or language breadth.
3. **Apple SpeechTranscriber** is free, zero-download and genuinely good on clean speech. However, it has no custom-vocab support (only DictationTranscriber has it) and Apple publishes no accuracy numbers. It is worth including in the benchmark as a "zero-dependency" option.
4. **Qwen3-ASR-0.6B/1.7B** is the newest strong open model and may beat Parakeet v2 on technical text because it has an LLM decoder. Benchmark it on your coding test set.

---

## B. Cloud STT

### B.1 Independent accuracy + price (Artificial Analysis, non-streaming leaderboard, fetched 2026-10-30) [I]

AA-WER v2 = duration-weighted WER on ~8 h of audio (50% AA-AgentTalk, 25% VoxPopuli, 25% Earnings22). Speed factor = audio seconds per wall-second (batch).

| Model (provider) | AA-WER | Speed factor | $/1000 min (AA) |
|---|---|---|---|
| Voxtral Small Transcribe 3 (Mistral) | **2.1%** | 64.6× | 4.00 |
| **Scribe v2 (ElevenLabs)** | **2.2%** | 73.4× | 3.67 |
| Voxtral Mini Transcribe 3 (Mistral) | 2.2% | 76.9× | 3.50 |
| Universal-3.5 Pro (AssemblyAI) | 3.0% | 101.6× | 3.50 |
| Universal-3 Pro (AssemblyAI) | 3.1% | 100.1× | 3.50 |
| gpt-transcribe (OpenAI, Jul 2026) | 3.31% (per The Decoder citing AA) | ~34× [V] | 4.50 |
| Universal (AssemblyAI) | 3.8% | 102.8× | 2.50 |
| GPT-4o Transcribe (OpenAI) | 4.0% | 37.8× | 6.00 |
| Speechmatics Enhanced | 4.0% | 56.8× | 12.50 |
| GPT-4o Mini Transcribe | 4.5% | 46.5× | 3.00 |
| Parakeet TDT 0.6B v3 (Together) | 4.5% | 664.6× | 1.50 |
| Whisper Large v3 Turbo (Groq) | 4.6% | 279.6× | 0.67 |
| Speechmatics Melia | 4.9% | 178.6× | 4.00 |
| Nova-3 (Deepgram) | 5.2% | 625.6× | 4.30 |
| Parakeet TDT 0.6B v2 (NVIDIA) | 6.4% | 98.4× | — |

The page also shows "Fun-Realtime-ASR-preview" at 1.7% in one snapshot. The leaderboard moves monthly.

### B.2 Per-vendor detail

| Vendor / model | Batch round-trip, 10 s clip [E unless noted] | Streaming finalisation latency | Keyterms / custom vocab | Price |
|---|---|---|---|---|
| **ElevenLabs Scribe v2 (batch)** | 10 s ÷ 73× ≈ 0.14 s compute + upload + RTT ≈ **0.35–0.6 s** [E] | — | Up to **1000 keyterms**, ≤50 chars each [V, docs] | **$0.22/h** + $0.05/h keyterms [V, official pricing] |
| **ElevenLabs Scribe v2 Realtime** | — | **~150 ms** [V]. Manual `commit` (`{"type":"commit"}`) or VAD commit (`commit_strategy=vad`, `vad_silence_threshold_secs` default 1.5 s) [V, docs]. For PTT use **manual commit on key-up** | Up to **50 keyterms**, ≤20 chars [V] | **$0.39/h** + $0.08/h keyterms [V]. Silence is billed |
| OpenAI gpt-transcribe (batch, Jul 2026) | ~34× RT [V], so ~0.3 s compute + RTT ≈ 0.5–0.8 s [E] | — | free-form context/prompt (semantic accuracy 38.5% → 44.6% with context on OpenAI's benchmark [V]) | $0.0045/min = $0.27/h [V] |
| OpenAI gpt-4o-transcribe / mini | 37.8× / 46.5× [I], so ~0.5–0.9 s [E] | Realtime API transcription (hypothesis not exposed for gpt-4o-transcribe per WhisperKit paper) [V] | `prompt` | $0.006 / $0.003 per min ($0.36 / $0.18 /h) [V] |
| OpenAI gpt-live-transcribe / gpt-realtime-whisper | — | tunable delay ("minimal"/"low") [secondary]. No ms figures published | context | $0.017/min = $1.02/h [V] |
| OpenAI whisper-1 | slow (~28× per AA for v2) [I] | — | prompt (224 tok) | $0.006/min [V] |
| **Groq whisper-large-v3-turbo** | 216× RT [V], 280× [I]. Third-party dictation app reports 300–800 ms for <30 s clips [V, app vendor] | no streaming | `prompt` (Whisper 224-token prompt) | **$0.04/h**, 10 s minimum billing per request [V] |
| Deepgram Nova-3 | 626× [I], so ~0.25–0.4 s mostly RTT [E] | WhisperKit paper measured 0.83 s hypothesis latency, ~1.7 s confirmed (TIMIT) [I-ish, competitor paper] | **Keyterm prompting**, up to 100 terms, +$0.0013/min [secondary] | $0.0043/min batch, ~$0.0077/min streaming [secondary] |
| Deepgram Flux | — | **~260 ms end-of-turn detection p50** [V, docs]. Eager EOT trims another ~100–200 ms [V]. Built for voice agents. "Nova-3-level accuracy" [V]. In AssemblyAI's Pipecat test, 15.6% pooled WER vs Scribe v2 9.8% vs U-3.5 Pro RT 7.0% [competitor-run] | keyterms | ~$0.0065–0.0077/min [secondary, conflicting] |
| AssemblyAI Universal-3.5 Pro Realtime (`u3-rt-pro`) | — | "sub-300 ms time to complete transcript" for <10 s utterances [V]. 256 ms P50 [V]. ForceEndpoint message available | Keyterms prompting + prompt together on streaming [V] | $0.45/h, **billed on WebSocket open time** (close it between utterances, or pre-open only briefly) [V]. Async U-3 Pro $0.21/h |
| Speechmatics (Melia / Enhanced RT) | 178.6× (Melia) [I] | `max_delay` configurable (no current ms figure found) | Custom dictionary (additional_vocab) | RT ~$0.20–0.43/h [secondary, conflicting] |
| Mistral Voxtral Mini Transcribe Realtime | — | sub-200 ms configurable [V] | context | $0.006/min [V] |

**Cloud takeaways**
- **Accuracy leaders (independent):** Scribe v2 ≈ Voxtral Transcribe 3 (2.1–2.2%), then AssemblyAI U-3/3.5 Pro (~3.0%), then OpenAI gpt-transcribe (~3.3%). Deepgram Nova-3 is fast but less accurate (5.2%).
- **The independent streaming leaderboard** (artificialanalysis.ai/speech-to-text/streaming, "AA-WER Streaming" + "time to final") exists, but its values render only in charts. Read them off the live page before you finalise.
- **For PTT, "streaming finalisation latency" is what matters, not turn-detection latency.** Every streaming API above lets you force-finalise (ElevenLabs `commit`, AssemblyAI `ForceEndpoint`, Deepgram `Finalize`). Measure the time from that message to the final transcript yourself.

---

## C. Streaming vs batch for push-to-talk

**Latency anatomy** [E]:
```
batch:     key-up ─► encode/upload (10–30 s of audio; 16 kHz PCM16 = 32 KB/s, so 0.3–1 MB) ─► server compute (clip/RTFx) ─► RTT ─► text
streaming: key-up ─► send "commit"/finalize ─► server finalises last ~0.5–1 s of context ─► RTT ─► text
```
- Batch latency grows with clip length: upload plus compute. At 30 s on a 73× model that is ~0.4 s compute plus ~0.1–0.3 s upload. Streaming latency is roughly constant (~150–300 ms) because the server has already decoded everything except the tail.
- **Locally**, Parakeet on the ANE is so fast (≥100× RT) that batch-on-release costs ~0.1–0.3 s even at 30 s, so streaming adds complexity for little gain. For Whisper-class local models (5–30× RT), use **chunked inference while recording**: transcribe committed 5–10 s windows during the hold, and on key-up decode only the tail.

**Techniques**
1. **Pre-warm everything on key-down, or earlier:**
   - open the WebSocket on key-down. With ElevenLabs the session is billed per audio sent, so a pre-opened socket is cheap. With AssemblyAI the open socket is billed.
   - keep the HTTP/2 or TLS connection to the LLM provider alive.
   - load CoreML models at app launch. The first ANE compile is seconds: FluidAudio shows encoder 3.4 s cold vs 162 ms warm on an iPhone [V]. Run one dummy inference after launch to warm it.
2. **Ring-buffer pre-roll** of ~300 ms before key-down, so the first word isn't clipped.
3. **Tail padding / release grace**: keep capturing ~150–250 ms after key-up, because people release mid-word. Then commit.
4. **VAD trimming** (Silero VAD or FluidAudio VAD) of leading and trailing silence before batch upload. This cuts upload time and compute, and reduces Whisper hallucinations on silence.
5. **Hedged requests**: send to cloud streaming *and* run local Parakeet on the same buffer. Take the first acceptable result, or prefer the cloud result if it arrives within a deadline (e.g. 350 ms).
6. **Audio format**: send PCM16 at 16 kHz mono (no encode latency). Opus only helps on slow uplinks.
7. **Keyterms**: feed identifiers from the active repo, such as file names, symbols and package names. The limit is 50 for ElevenLabs realtime and 1000 for batch. Refresh the list when the frontmost project changes.

---

## D. LLM cleanup pass

### D.1 What the pass needs
Input ~30–150 words (~40–200 tokens) plus a system prompt (~300–800 tokens, cacheable). Output is about the same length. **TTFT dominates**: at ≥500 tok/s, a 100-token output decodes in ≤0.2 s. At 85 tok/s it takes 1.2 s.

### D.2 Hosted options

| Option | Speed | TTFT | Price (in/out per MTok) | Notes |
|---|---|---|---|---|
| **Groq `openai/gpt-oss-20b`** | 1000 tok/s [V, Groq docs]. 846–854 tok/s [I, AA] | First chunk 0.73 s, but 3.1 s to the first *answer* token at default reasoning [I, AA]. **Set `reasoning_effort: low`** | $0.075 / $0.30 [V] | Fastest decode. Reasoning tokens are the trap: use low effort and a short system prompt |
| Groq `llama-3.1-8b-instant` | 560 tok/s [V] | non-reasoning, so TTFT is typically ~0.1–0.3 s [secondary, unverified] | contact sales [V] | Simplest and lowest-TTFT "dumb cleanup" model. Weaker at self-corrections |
| Groq `openai/gpt-oss-120b` | 500 tok/s [V] | as above | $0.15 / $0.60 [V] | Better quality, still fast |
| **Cerebras `gpt-oss-120b`** | ~3000 tok/s [V] | 0.35 s median / 1.10 s p95 end-to-end request (benchlm, Sep 2026) [I] | $0.35 / $0.75 [secondary, Oct 2026] | Best for restructure mode |
| **Claude Haiku 5.5** (`claude-haiku-5-5`, released 2026-10-07) | "Fastest" in the Claude lineup [V]. No tok/s figure published | Haiku 4.5 measured ~0.56 s time to first text, ~85 tok/s [I, third-party]. Haiku 5.5 not yet independently measured | **$0.10 / $0.50** (≤100k prompt). Cache read $0.01 [V] | Adaptive thinking on by default (effort `medium`). For cleanup **set effort low, or disable thinking if the Models API reports `thinking.types.disabled.supported`**. Min cacheable prompt 512 tokens. Note: the new tokenizer counts ~30% more tokens than Haiku 4.5 |
| Claude Sonnet 5.5 | "Fast" [V] | — | $2 / $10 [V] | Use it for restructure mode when quality matters more than speed |
| **Gemini 3.1 Flash-Lite** (preview, Mar 2026) | ~363 tok/s [I, AA-cited] | "2.5× faster TTFT than 2.5 Flash" [V] | $0.25 / $1.50 [secondary] | Good, cheap. It is still a preview |
| OpenAI gpt-4.1-nano | — | **0.62 s** TTFT [I, AA] | $0.10 / $0.40 [V] | Non-reasoning and predictable |
| OpenAI gpt-4.1-mini | — | ~similar | $0.40 / $1.60 [V] | Better quality |
| OpenAI gpt-5-nano / gpt-5.4-nano / gpt-6-luna | — | Reasoning models, so TTFT is large unless effort=minimal (83 s reported "TTFT" counts reasoning [I, benchlm]) | $0.05/$0.40; $0.20/$1.25; $0.10/$0.50 [V] | Use minimal reasoning only |

### D.3 Local options (MLX / llama.cpp)

| Model | Hardware | Prefill | Decode | Peak RAM | Source |
|---|---|---|---|---|---|
| Qwen3-4B-Instruct-2507 4-bit | M4 Max 64 GB, mlx-lm 0.28.2 | 1622 tok/s | **134.5 tok/s** | 3.35 GB | [I, Awni Hannun gist] |
| Qwen3-4B-Instruct-2507 8-bit | same | 1607 | 86.9 | 5.25 GB | [I] |
| Qwen3-30B-A3B-Instruct 4-bit (MoE) | same | 1754 | 113.3 | 18.2 GB | [I] |
| Qwen3-4B Q4 | M4 Pro 24 GB | — | ~118 tok/s (estimate) | — | [E, llmcheck] |
| Qwen3-1.7B / Llama-3.2-3B / Gemma-3-4B 4-bit | M-series | — | roughly 1.5–2.5× the 4B decode on the same chip (bandwidth-bound) | 1–3 GB | [E] |

Local budget for 600 prompt tokens and 100 output tokens with Qwen3-4B q4 on an M4 Max [E]: 0.37 s prefill (≈0 with a KV-cached system prompt) + 0.74 s decode ≈ **0.8–1.1 s**. On a base M-chip with lower bandwidth it is roughly 2× slower. The conclusion is **local LLM only for offline mode or for short outputs, unless you fine-tune a ≤1.7B model**.

### D.4 Techniques
1. **Gate the LLM**:
   - skip it when the transcript is ≤N words (e.g. 8) and has no fillers ("um", "uh", "like", "you know") and no self-correction cues ("actually", "I mean", "scratch that", "no wait").
   - do capitalisation and punctuation with the STT output, which Scribe, Parakeet and Whisper all punctuate, plus regex filler removal.
   - expect 30–60% of dictations to skip the LLM [E].
2. **Stream output** and start inserting at the first sentence boundary for long outputs. Default mode is under 0.3 s of decode anyway, so it may be simpler to insert once.
3. **Prompt caching**: keep a static system prompt with few-shot examples first and the dynamic transcript last.
   - Haiku 5.5 needs a ≥512-token prefix to cache [V]. Cache reads cost $0.01/MTok.
   - OpenAI and Groq cache automatically for long prefixes.
   - Locally, reuse the mlx-lm prompt cache (KV of the system prompt).
4. **Constrain output length** (`max_tokens ≈ 1.5 × input tokens + 20`). Forbid preambles ("Here is the cleaned text:"). Use no JSON, just raw text.
5. **Disable or minimise reasoning** on reasoning models (gpt-oss: `reasoning_effort: low`; Claude: low effort or thinking disabled; GPT-5 family: `minimal`).
6. **Small fine-tuned model**: once you have ~1–3k (raw → cleaned) pairs from your own usage, fine-tune Qwen3-1.7B or 0.6B (LoRA in mlx-lm). Local cleanup could then run at ~200+ tok/s with a tiny prompt [E]. This is the long-term path to an LLM pass that is both private and under 300 ms.
7. **Context injection** for coding mode: pass the active app, window title or repo name, and identifier list. This helps fix "use state" → `useState`. Keep it under ~200 tokens to protect TTFT.
8. **Pre-connect**: send a no-op request or keep an HTTP/2 connection warm when the key goes down. Cold TLS adds 100–300 ms.

---

## E. Recommendation and benchmark methodology

### E.1 Recommended architecture
```
key-down ─► start mic (with 300 ms pre-roll) ─► open Scribe v2 Realtime WS (manual commit, keyterms) ─► stream PCM16 16k
         └► local ring buffer (for Parakeet fallback)          └► warm LLM HTTP/2 connection
key-up   ─► +200 ms grace ─► send {"type":"commit"} ─────────────► cloud final (target ≤300 ms p50)
                         └► Parakeet v2 (FluidAudio/ANE) on buffer ─► local final (target ≤250 ms p50)
         ─► choose: cloud if arrived by deadline (350 ms) else local
         ─► gate: short/clean? ─► insert directly
                  else ─► cleanup LLM (Groq gpt-oss-20b low / Haiku 5.5 low-effort) ─► insert
mode "agent restructure" ─► Cerebras gpt-oss-120b or Claude Haiku/Sonnet 5.5, streamed insert (budget 1–1.5 s)
```
- **Primary STT:** ElevenLabs Scribe v2 Realtime. Best independent accuracy family, you have keys, and keyterms are supported.
  - Also benchmark **Scribe v2 batch** ($0.22/h, 1000 keyterms). For ≤10 s utterances its round-trip may be within ~100 ms of streaming. It may also be slightly more accurate than realtime.
- **Fallback / offline:** Parakeet TDT v2 (FluidAudio). Second choice: Qwen3-ASR-0.6B (MLX) if it wins on your coding set. Third: Apple SpeechTranscriber (zero download).
- **Cloud alternates to A/B:** AssemblyAI U-3.5 Pro Realtime (strong accuracy, but billed per socket-open time) and Groq whisper-turbo (cheapest, 4.6% AA-WER, no streaming).
- **Cleanup LLM:** Groq gpt-oss-20b with `reasoning_effort: low`, with Claude Haiku 5.5 as the quality alternate. A/B both on the latency and edit-quality metrics below. Local Qwen3-4B 4-bit is for offline only.
- **Restructure mode:** Cerebras gpt-oss-120b (speed) or Claude Haiku 5.5 / Sonnet 5.5 (quality), streamed.

### E.2 Test set composition (aim for ~300 utterances, ~45 min total, recorded on *your* mic/room)

| Bucket | Share | Content |
|---|---|---|
| Short commands | 20% | 2–5 s: "run the tests", "commit with message fix typo" |
| Medium prose | 25% | 8–15 s: emails and Slack-style messages |
| Long dictation | 15% | 20–30 s: paragraphs with natural pauses |
| **Technical / coding vocab** | 25% | identifiers (`useEffect`, `kubectl`, `pyproject.toml`, `snake_case_var`), library names, CLI flags, numbers/versions, acronyms (gRPC, JWT, CUDA) |
| Disfluent / self-correcting | 15% | fillers, restarts, "no wait, make that…", which test the LLM pass |

- Include 2–3 speakers if possible, plus a noisy subset (fan, café) of ~15%.
- **References**: hand-transcribe *verbatim* (for STT WER) **and** write a *clean intended* version (for LLM-pass evaluation).
- Keep a separate **keyterm list** per utterance to compute keyterm recall.
- Optional public sanity anchors: 100 LibriSpeech test-clean, 100 Earnings22 utterances, to compare against the published numbers.

### E.3 Accuracy metrics
```python
import jiwer
from whisper_normalizer.english import EnglishTextNormalizer  # same normalizer as HF Open ASR leaderboard
norm = EnglishTextNormalizer()
wer = jiwer.wer([norm(r) for r in refs], [norm(h) for h in hyps])   # corpus-level, not mean of per-utt
cer = jiwer.cer(...)
```
- Report **corpus WER** overall and per bucket. Report **technical-bucket WER separately**, because it is the one that matters.
- **Case/symbol-sensitive "identifier accuracy"**: exact-match rate of each keyterm in the *un-normalised* hypothesis (`useState`, not "use state"). The normaliser hides exactly the errors that matter for coding.
- For the LLM pass:
  - compute **WER(clean_ref, llm_output)**
  - compute **meaning-preservation rate**, judged by a stronger LLM on a pass/fail rubric (no added content, no dropped content, self-corrections applied), on all 300 items
  - spot-check 50 by hand.
- Track **hallucination rate**: words in the output not supported by the audio. Test on 10 silent or near-silent clips.

### E.4 Latency instrumentation
Use `mach_absolute_time` / `ContinuousClock` and log one JSON line per utterance:

| Timestamp | Meaning |
|---|---|
| `t0_keydown` | key-down event received |
| `t1_ws_open` | streaming socket ready (should be < first audio frame or buffered) |
| `t2_keyup` | key-up event (**the zero point**) |
| `t3_commit_sent` | commit/finalize message sent (t2 + grace) |
| `t4_stt_first_partial` | first partial received (streaming only) |
| `t5_stt_final` | final transcript received (cloud) / inference returned (local) |
| `t6_llm_req_sent` | (if LLM gated in) |
| `t7_llm_first_token` | TTFT |
| `t8_llm_done` | last token |
| `t9_inserted` | after paste/AX insertion confirmed |

Derived metrics, all relative to `t2_keyup`:
- **STT-final latency** = t5 − t2
- **LLM TTFT** = t7 − t6
- **LLM total** = t8 − t6
- **Insert** = t9 − t8
- **E2E** = t9 − t2

Also log the audio duration, bytes sent, network RTT (a ping to the API host at session start), the model or provider used, whether the LLM was skipped, and whether the fallback was taken.

**Targets**

| Metric | p50 | p95 |
|---|---|---|
| STT final (cloud streaming) | ≤ 250 ms | ≤ 500 ms |
| STT final (local Parakeet, 30 s clip) | ≤ 250 ms | ≤ 400 ms |
| LLM total (cleanup) | ≤ 350 ms | ≤ 700 ms |
| Insert | ≤ 30 ms | ≤ 80 ms |
| **E2E, LLM skipped** | **≤ 300 ms** | **≤ 600 ms** |
| **E2E, with cleanup** | **≤ 650 ms** | **≤ 1100 ms** |
| E2E, restructure mode | ≤ 1.2 s to first char | ≤ 2.5 s |

**Protocol**
- Replay the recorded WAVs through the real pipeline in real time. Use a virtual mic or BlackHole loopback, with a scripted key-down/key-up at the recorded boundaries. Measured latency then includes real streaming behaviour, not just file upload.
- Run each configuration ≥3 times, at different times of day (cloud variance).
- Run on battery and on AC, and on the lowest-spec Mac you support.
- Report p50, p90 and p95, with bootstrap CIs.
- Plot E2E latency vs utterance length for batch vs streaming. The crossover point tells you whether batch Scribe v2 is good enough for short utterances.

---

## Sources

**Leaderboards / independent**
- Artificial Analysis STT (non-streaming): https://artificialanalysis.ai/speech-to-text/non-streaming
- Artificial Analysis STT (streaming, AA-WER Streaming + time-to-final): https://artificialanalysis.ai/speech-to-text/streaming
- The Decoder on AA-WER v2: https://the-decoder.com/elevenlabs-and-google-dominate-artificial-analysis-updated-speech-to-text-benchmark/
- The Decoder on gpt-transcribe: https://the-decoder.com/gpt-transcribe-improves-on-its-predecessor-but-cant-catch-elevenlabs-google-or-mistral-on-error-rates/
- Open ASR Leaderboard paper (arXiv 2510.06961): https://arxiv.org/html/2510.06961v1
- Open ASR 2026 roundups (secondary): https://pinggy.io/blog/best_open_source_self_hosted_speech_to_text_models/ , https://www.orcarouter.ai/blog/granite-speech-5-0-2b-explained , https://northflank.com/blog/best-open-source-speech-to-text-stt-model-in-2026-benchmarks
- mac-whisper-speedtest (M4, 9 engines): https://github.com/anvanvan/mac-whisper-speedtest
- mlx-lm benchmark gist (Qwen3 on M4 Max): https://gist.github.com/awni/c1790e4c3a39be6e8f1c4afd42423d2d
- AA gpt-oss-20b providers: https://artificialanalysis.ai/models/gpt-oss-20b/providers
- AA gpt-4.1-nano providers: https://artificialanalysis.ai/models/gpt-4-1-nano/providers
- benchlm Cerebras host data: https://benchlm.ai/hosts/cerebras

**Local STT**
- FluidAudio: https://github.com/FluidInference/FluidAudio ; benchmarks: https://docs.fluidinference.com/reference/benchmarks.md ; CoreML v3: https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml
- NVIDIA Parakeet TDT v3 (NGC): https://catalog.ngc.nvidia.com/orgs/nim/nvidia/containers/parakeet-0.6b-tdt/-
- parakeet-mlx: https://pypi.org/project/parakeet-mlx/
- WhisperKit paper (ICML'25, arXiv 2507.10860): https://arxiv.org/html/2507.10860v1 ; Argmax ParakeetKit Pro: https://huggingface.co/argmaxinc/parakeetkit-pro
- Moonshine v2 paper: https://arxiv.org/html/2602.12241
- Kyutai STT: https://kyutai.org/stt ; https://github.com/kyutai-labs/delayed-streams-modeling
- Qwen3-ASR MLX: https://github.com/moona3k/mlx-qwen3-asr/ ; https://soniqo.audio/es/benchmarks/qwen3-asr-vs-whisper
- Voxtral Mini 4B Realtime: https://huggingface.co/mistralai/Voxtral-Mini-4B-Realtime-2602 ; https://mistral.ai/news/voxtral-transcribe-2 ; paper https://arxiv.org/html/2602.11298
- Apple SpeechAnalyzer benchmark coverage: https://www.gigazine.net/gsc_news/en/20250619-apple-speech-analyzer ; https://dev.to/iravoice/apple-speechanalyzer-vs-whispercpp-a-40-speaker-mac-benchmark-40i4
- Apple contextualStrings: https://developer.apple.com/documentation/speech/analysiscontext/contextualstrings ; forum: https://developer.apple.com/forums/thread/811083

**Cloud STT**
- ElevenLabs STT docs: https://elevenlabs.io/docs/capabilities/speech-to-text ; pricing: https://elevenlabs.io/pricing/api ; commit strategies: https://elevenlabs.io/docs/eleven-api/guides/cookbooks/speech-to-text/realtime/transcripts-and-commit-strategies ; realtime page: https://elevenlabs.io/realtime-speech-to-text
- OpenAI pricing: https://developers.openai.com/api/docs/pricing ; gpt-transcribe / gpt-live-transcribe announcement: https://community.openai.com/t/gpt-live-transcribe-and-gpt-transcribe-two-new-transcription-models-in-the-api/1388318
- Groq models/pricing: https://console.groq.com/docs/models ; https://console.groq.com/docs/model/whisper-large-v3-turbo
- Deepgram Flux config: https://developers.deepgram.com/docs/flux/configuration ; eager EOT: https://developers.deepgram.com/docs/flux/voice-agent-eager-eot/llms.txt ; pricing (secondary): https://diyai.io/ai-tools/speech-to-text/deepgram-pricing-2026/
- AssemblyAI streaming U-3 Pro: https://assemblyai.com/docs/streaming/universal-3-pro ; pricing: https://www.assemblyai.com/pricing.md ; vendor streaming benchmark: https://assemblyai.com/blog/daily-co-voice-agent-with-assemblyai-universal-3-pro-streaming
- Speechmatics pricing (secondary): https://usagepricing.com/blueprint/speechmatics

**LLMs**
- Claude models overview: https://platform.claude.com/docs/en/about-claude/models/overview ; Haiku 5.5: https://platform.claude.com/docs/en/models/haiku-5-5/overview
- Groq models: https://console.groq.com/docs/models
- Cerebras gpt-oss-120b: https://www.cerebras.ai/blog/cerebras-launches-openai-s-gpt-oss-120b-at-a-blistering-3-000-tokens-sec ; current catalog (secondary): https://claudelog.com/faqs/cerebras-models/
- Gemini 3.1 Flash-Lite (secondary): https://www.eweek.com/de/news/gemini-3-1-flash-lite-launch/ ; https://llmx-tech.pages.dev/blog/gemini-31-flash-lite-review-2026
- OpenAI pricing: https://developers.openai.com/api/docs/pricing

## Open questions / to verify before committing
- Scribe v2 *Realtime* AA-WER and time-to-final. Read them from the AA streaming chart, or measure them yourself.
- Whether Claude Haiku 5.5 accepts `thinking: {type: "disabled"}`. Check `capabilities.thinking.types.disabled` via the Models API.
- Groq `llama-3.1-8b-instant` pricing is now "contact sales". Confirm it is still self-serve.
- Deepgram, Speechmatics and Cerebras prices come from secondary aggregators with conflicting values.
- Qwen3-ASR context-biasing support in the MLX/Swift ports.
