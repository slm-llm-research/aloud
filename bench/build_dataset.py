"""Build the M0 benchmark manifest.

Two sets, both written as 16 kHz mono WAV under data/audio/:
  libri  - a fixed, speaker-diverse sample of LibriSpeech test-clean (real human speech, read prose)
  tech   - coding/technical sentences and filler/self-correction sentences synthesized with macOS `say`
           (synthetic voice: good for identifier and latency checks, NOT representative of your mic)

Your own recordings (PLAN.md section 10) replace/extend these later.
"""

import json
import random
import subprocess
from pathlib import Path

import soundfile as sf

ROOT = Path(__file__).parent
DATA = ROOT / "data"
AUDIO = DATA / "audio"
LIBRI = DATA / "librispeech" / "LibriSpeech" / "test-clean"
N_LIBRI = 100
SAY_VOICE = "Samantha"


def libri_items():
    items = []
    for trans in sorted(LIBRI.glob("*/*/*.trans.txt")):
        for line in trans.read_text().splitlines():
            utt_id, text = line.split(" ", 1)
            flac = trans.parent / f"{utt_id}.flac"
            info = sf.info(flac)
            if 3.0 <= info.duration <= 20.0:
                items.append((utt_id, flac, text, info.duration))
    # One pass round-robin over speakers so the sample isn't dominated by a few voices.
    random.Random(0).shuffle(items)
    by_speaker = {}
    for it in items:
        by_speaker.setdefault(it[0].split("-")[0], []).append(it)
    picked = []
    while len(picked) < N_LIBRI:
        for spk in sorted(by_speaker):
            if by_speaker[spk] and len(picked) < N_LIBRI:
                picked.append(by_speaker[spk].pop())
    return picked


def to_wav16k(src: Path, dst: Path):
    subprocess.run(
        ["ffmpeg", "-loglevel", "error", "-y", "-i", str(src), "-ac", "1", "-ar", "16000", str(dst)],
        check=True,
    )


def main():
    AUDIO.mkdir(parents=True, exist_ok=True)
    manifest = []

    for utt_id, flac, text, dur in libri_items():
        wav = AUDIO / f"libri_{utt_id}.wav"
        if not wav.exists():
            to_wav16k(flac, wav)
        manifest.append({"id": f"libri_{utt_id}", "set": "libri", "wav": str(wav.relative_to(ROOT)),
                         "ref": text.lower(), "duration": round(dur, 2), "identifiers": []})

    for line in (DATA / "tech_prompts.jsonl").read_text().splitlines():
        p = json.loads(line)
        aiff = AUDIO / f"{p['id']}.aiff"
        wav = AUDIO / f"{p['id']}.wav"
        if not wav.exists():
            subprocess.run(["say", "-v", SAY_VOICE, "-o", str(aiff), p["text"]], check=True)
            to_wav16k(aiff, wav)
            aiff.unlink()
        manifest.append({"id": p["id"], "set": "tech" if p["id"].startswith("tech") else "filler",
                         "wav": str(wav.relative_to(ROOT)), "ref": p["text"],
                         "duration": round(sf.info(wav).duration, 2), "identifiers": p["identifiers"]})

    out = DATA / "manifest.jsonl"
    out.write_text("".join(json.dumps(m) + "\n" for m in manifest))
    total = sum(m["duration"] for m in manifest)
    print(f"{len(manifest)} items, {total / 60:.1f} min -> {out}")


if __name__ == "__main__":
    main()
