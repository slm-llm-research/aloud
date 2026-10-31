"""STT benchmark: accuracy (WER, identifier exact-match) and push-to-talk latency.

Latency definitions (all "key-up -> final transcript", the number that matters for PTT):
  local batch engines  : wall time of transcribe() on the whole clip (model already warm)
  cloud batch engines  : HTTP round trip for the whole clip
  eleven_rt            : audio is streamed at real-time pace; latency = commit sent -> committed_transcript

Usage:
  uv run python stt_bench.py --engines parakeet,whisper_turbo [--sets libri,tech,filler] [--limit N] [--keyterms]
Cloud engines read keys from ../.env (ELEVENLABS_API_KEY, GROQ_API_KEY) and are skipped if unset.
"""

import argparse
import asyncio
import base64
import csv
import json
import os
import statistics
import time
from datetime import datetime
from pathlib import Path

import httpx
import jiwer
import numpy as np
import soundfile as sf
from dotenv import load_dotenv
from whisper_normalizer.english import EnglishTextNormalizer

ROOT = Path(__file__).parent
load_dotenv(ROOT.parent / ".env")
normalize = EnglishTextNormalizer()


# ---------------------------------------------------------------- engines

class Parakeet:
    name = "parakeet"

    def __init__(self, repo="mlx-community/parakeet-tdt-0.6b-v2"):
        from parakeet_mlx import from_pretrained
        self.model = from_pretrained(repo)

    def transcribe(self, wav, keyterms=None):
        return self.model.transcribe(wav).text


class WhisperTurbo:
    name = "whisper_turbo"

    def __init__(self, repo="mlx-community/whisper-large-v3-turbo"):
        import mlx_whisper
        self.mw, self.repo = mlx_whisper, repo

    def transcribe(self, wav, keyterms=None):
        prompt = ", ".join(keyterms) if keyterms else None
        return self.mw.transcribe(wav, path_or_hf_repo=self.repo, language="en",
                                  initial_prompt=prompt)["text"]


class ElevenBatch:
    name = "eleven_batch"

    def __init__(self):
        self.key = os.environ["ELEVENLABS_API_KEY"]
        self.client = httpx.Client(http2=False, timeout=60)

    def transcribe(self, wav, keyterms=None):
        data = {"model_id": "scribe_v2", "language_code": "en"}
        if keyterms:
            data["keyterms"] = list(keyterms)  # httpx sends a list value as repeated form fields
        with open(wav, "rb") as f:
            r = self.client.post("https://api.elevenlabs.io/v1/speech-to-text",
                                 headers={"xi-api-key": self.key}, data=data,
                                 files={"file": (Path(wav).name, f, "audio/wav")})
        r.raise_for_status()
        return r.json()["text"]


class GroqWhisper:
    name = "groq_turbo"

    def __init__(self):
        self.key = os.environ["GROQ_API_KEY"]
        self.client = httpx.Client(timeout=60)

    def transcribe(self, wav, keyterms=None):
        data = {"model": "whisper-large-v3-turbo", "language": "en", "response_format": "json"}
        if keyterms:
            data["prompt"] = ", ".join(keyterms)
        with open(wav, "rb") as f:
            r = self.client.post("https://api.groq.com/openai/v1/audio/transcriptions",
                                 headers={"Authorization": f"Bearer {self.key}"}, data=data,
                                 files={"file": (Path(wav).name, f, "audio/wav")})
        r.raise_for_status()
        return r.json()["text"]


class ElevenRealtime:
    """Streams the clip at real-time pace like a held key, commits on 'key-up', times the final."""
    name = "eleven_rt"
    CHUNK_S = 0.1

    def __init__(self):
        self.key = os.environ["ELEVENLABS_API_KEY"]
        self.last_latency = None

    def transcribe(self, wav, keyterms=None):
        return asyncio.run(self._run(wav, keyterms))

    async def _run(self, wav, keyterms):
        import websockets
        params = [("model_id", "scribe_v2_realtime"), ("audio_format", "pcm_16000"),
                  ("commit_strategy", "manual"), ("language_code", "en")]
        params += [("keyterms", k) for k in (keyterms or [])[:50]]
        url = "wss://api.elevenlabs.io/v1/speech-to-text/realtime?" + str(httpx.QueryParams(params))
        pcm = (sf.read(wav, dtype="int16")[0]).tobytes()
        step = int(16000 * self.CHUNK_S) * 2
        async with websockets.connect(url, additional_headers={"xi-api-key": self.key}) as ws:
            chunks = [pcm[i:i + step] for i in range(0, len(pcm), step)]
            for i, c in enumerate(chunks):
                last = i == len(chunks) - 1
                await ws.send(json.dumps({"message_type": "input_audio_chunk", "commit": last,
                                          "audio_base_64": base64.b64encode(c).decode(),
                                          "sample_rate": 16000}))
                if last:
                    t_commit = time.perf_counter()
                else:
                    await asyncio.sleep(self.CHUNK_S)
            texts = []
            while True:
                msg = json.loads(await asyncio.wait_for(ws.recv(), timeout=15))
                mt = msg.get("message_type")
                if mt == "committed_transcript":
                    self.last_latency = time.perf_counter() - t_commit
                    texts.append(msg["text"])
                    return " ".join(texts)
                if mt not in ("session_started", "partial_transcript"):
                    raise RuntimeError(f"eleven_rt: {msg}")


ENGINES = {"parakeet": Parakeet, "whisper_turbo": WhisperTurbo, "eleven_batch": ElevenBatch,
           "groq_turbo": GroqWhisper, "eleven_rt": ElevenRealtime}
NEEDS_KEY = {"eleven_batch": "ELEVENLABS_API_KEY", "eleven_rt": "ELEVENLABS_API_KEY",
             "groq_turbo": "GROQ_API_KEY"}


# ---------------------------------------------------------------- scoring

def wer(refs, hyps):
    r = [normalize(x) or "<empty>" for x in refs]
    h = [normalize(x) or "<empty>" for x in hyps]
    return jiwer.wer(r, h)


def pct(xs, q):
    return float(np.percentile(xs, q)) if xs else float("nan")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--engines", default="parakeet,whisper_turbo")
    ap.add_argument("--sets", default="libri,tech,filler")
    ap.add_argument("--limit", type=int, default=0, help="max items per set (0 = all)")
    ap.add_argument("--keyterms", action="store_true",
                    help="pass identifiers from the tech set as keyterms/prompt")
    args = ap.parse_args()

    items = [json.loads(l) for l in (ROOT / "data/manifest.jsonl").read_text().splitlines()]
    sets = args.sets.split(",")
    items = [i for i in items if i["set"] in sets]
    if args.limit:
        items = [i for s in sets for i in [x for x in items if x["set"] == s][:args.limit]]
    keyterms = sorted({k for i in items for k in i["identifiers"]}) if args.keyterms else None

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    out_dir = ROOT / "results"
    out_dir.mkdir(exist_ok=True)
    summary = []

    for name in args.engines.split(","):
        if name in NEEDS_KEY and not os.environ.get(NEEDS_KEY[name]):
            print(f"skip {name}: {NEEDS_KEY[name]} not set in voice-flow/.env")
            continue
        t0 = time.perf_counter()
        eng = ENGINES[name]()
        load_s = time.perf_counter() - t0
        eng.transcribe(str(ROOT / items[0]["wav"]), keyterms)  # warm-up (model compile / TLS)
        rows = []
        for it in items:
            t = time.perf_counter()
            try:
                hyp = eng.transcribe(str(ROOT / it["wav"]), keyterms)
                err = ""
            except Exception as e:  # keep going; record the failure
                hyp, err = "", repr(e)[:200]
            lat = getattr(eng, "last_latency", None) or (time.perf_counter() - t)
            ids_hit = sum(k in hyp for k in it["identifiers"])
            rows.append({**it, "engine": name, "hyp": hyp, "latency_s": round(lat, 4),
                         "ids_total": len(it["identifiers"]), "ids_hit": ids_hit, "error": err})
            print(f"{name:14s} {it['id']:28s} {lat*1000:7.0f} ms  {hyp[:70]!r}")

        with open(out_dir / f"stt-{stamp}-{name}.csv", "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
            w.writeheader()
            w.writerows(rows)

        for s in sets:
            rs = [r for r in rows if r["set"] == s and not r["error"]]
            if not rs:
                continue
            lats = [r["latency_s"] * 1000 for r in rs]
            durs = [r["duration"] for r in rs]
            ids_t = sum(r["ids_total"] for r in rs)
            summary.append({
                "engine": name, "set": s, "n": len(rs), "errors": sum(1 for r in rows if r["set"] == s and r["error"]),
                "wer": round(wer([r["ref"] for r in rs], [r["hyp"] for r in rs]) * 100, 2),
                "id_exact_pct": round(100 * sum(r["ids_hit"] for r in rs) / ids_t, 1) if ids_t else None,
                "lat_p50_ms": round(pct(lats, 50)), "lat_p95_ms": round(pct(lats, 95)),
                "mean_clip_s": round(statistics.mean(durs), 1),
                "rtf_x": round(sum(durs) / (sum(lats) / 1000), 1),
                "load_s": round(load_s, 1), "keyterms": bool(keyterms),
            })

    (out_dir / f"stt-{stamp}-summary.json").write_text(json.dumps(summary, indent=2))
    print("\n| engine | set | n | WER % | identifier exact % | p50 ms | p95 ms | mean clip s | speed ×RT |")
    print("|---|---|---|---|---|---|---|---|---|")
    for s in summary:
        print(f"| {s['engine']}{' +kt' if s['keyterms'] else ''} | {s['set']} | {s['n']} | {s['wer']} | "
              f"{s['id_exact_pct'] if s['id_exact_pct'] is not None else '—'} | {s['lat_p50_ms']} | "
              f"{s['lat_p95_ms']} | {s['mean_clip_s']} | {s['rtf_x']} |")


if __name__ == "__main__":
    main()
