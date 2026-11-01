"""End-to-end dictation evals: you speak a scenario into the real app, the harness pairs it with what
was heard and typed, and scores it against the expected text.

    uv run python scenario_eval.py list                         # the scenarios
    uv run python scenario_eval.py run                          # guided session (resumes where you left off)
    uv run python scenario_eval.py run --only chat-lol,list-cue # or --tags noise / --mode email / --redo
    uv run python scenario_eval.py import observed.tsv          # observed text you copied by hand (id<TAB>observed)
    uv run python scenario_eval.py report                       # metrics -> results/scenario-report-<session>.md/.json
    uv run python scenario_eval.py replay                       # no human: TTS -> live Scribe -> the app's cleanup
    uv run python scenario_eval.py reclean --session S          # same heard text, current cleanup code -> session S-reclean
    uv run python scenario_eval.py compare S1 S2 ...            # before/after table of sessions
    uv run python scenario_eval.py selftest                     # checks the metrics on built-in examples

`run` reads the app's capture file (~/Library/Logs/InstructFlow/dictations.jsonl, one line per
dictation with what speech-to-text heard and what was typed), so nothing has to be copied by hand.

Metrics (per scenario, then per mode and overall):
- STT WER / CER: what speech-to-text heard vs the script you were asked to say (normalized: case,
  punctuation, number spelling). Fillers in the script are removed by the normalizer on both sides.
- Output WER / CER: what was typed vs the expected text, normalized. Measures meaning-level accuracy.
- Strict CER: typed vs expected character by character, case, punctuation and line breaks included.
  Measures formatting (lists, email layout, `-b` flags).
- Novel-word rate: share of typed content words the speaker never said (made-up words).
- Kept-word recall: share of the expected text's content words that were typed.
- Checks: must / must-not phrases, layout for the mode, negations kept, numbers kept, mode routed right.
- Latency: key-up to text typed, p50 / p95.
"""

import argparse
import json
import re
import statistics
import sys
import time
from datetime import datetime
from pathlib import Path

import jiwer
from whisper_normalizer.english import EnglishTextNormalizer

HERE = Path(__file__).parent
SCENARIOS = HERE / "scenarios.jsonl"
RESULTS = HERE / "results"
CAPTURE = Path.home() / "Library/Logs/InstructFlow/dictations.jsonl"

_normalizer = EnglishTextNormalizer()


def normalize(s):
    # "at 5:00" and "at 5" mean the same; the strict CER still sees the difference.
    return _normalizer(re.sub(r"\b(\d{1,2}):00\b", r"\1", s))

STOPWORDS = set("""a an the and or but if then so to of in on at for by with from as into about up out is are was were be
been am do does did have has had will would can could should it its this that these those there here i me my we us our
you your he she him her they them their what which who also too just let please all any some one s t ll re ve d m""".split())
FILLERS = {"um", "umm", "uh", "uhh", "erm", "er", "ah", "hmm", "mm", "like", "okay", "ok", "well", "yeah", "wait", "sorry", "mean"}
LABELS = {"goal", "context", "constraints", "done", "when"}
NEGATION = re.compile(r"\b(not|never|no|none|nothing|nobody|cannot|nor|\w+n't|dont|cant|wont|isnt|didnt|doesnt)\b")


def load_scenarios():
    return [json.loads(line) for line in SCENARIOS.read_text().splitlines() if line.strip()]


def session_path(name):
    return RESULTS / f"scenarios-{name}.jsonl"


def load_session(name):
    p = session_path(name)
    rows = {}
    if p.exists():
        for line in p.read_text().splitlines():
            if line.strip():
                r = json.loads(line)
                rows[r["id"]] = r  # the latest attempt wins
    return rows


def save_row(name, row):
    # Window titles can carry an account's email address (a Gmail tab); results are meant to be shared.
    if row.get("title"):
        row["title"] = re.sub(r"[\w.%+-]+@[\w.-]+\.[A-Za-z]{2,}", "<email>", row["title"])
    RESULTS.mkdir(exist_ok=True)
    with session_path(name).open("a") as f:
        f.write(json.dumps(row, ensure_ascii=False) + "\n")


# ---------------------------------------------------------------- metrics

def content_words(s):
    words = re.findall(r"[a-z0-9]+", re.sub(r"([a-z])([A-Z])", r"\1 \2", s).lower())
    return [w for w in words if w not in STOPWORDS and w not in FILLERS and w not in LABELS and (len(w) > 1 or w.isdigit())]


def wer_cer(ref, hyp):
    r, h = normalize(ref) or "<empty>", normalize(hyp) or "<empty>"
    return jiwer.wer(r, h), jiwer.cer(r, h)


def strict_cer(ref, hyp):
    flat = lambda s: re.sub(r"[ \t]+", " ", s.strip()).replace("`", "")
    return jiwer.cer(flat(ref) or "<empty>", flat(hyp) or "<empty>")


def has_phrase(text, phrase):
    """Case-insensitive; plain words match whole words only ("um" is not in "number")."""
    low, p = text.lower(), phrase.lower()
    if re.fullmatch(r"[\w' ]+", p):
        # A trailing plural still counts ("passport" in "passports").
        return re.search(r"(?<![\w'])" + re.escape(p) + r"(?:s|es)?(?![\w'])", low) is not None
    return p in low


def layout_ok(fmt, expected, typed):
    lines = [l.strip() for l in typed.strip().splitlines() if l.strip()]
    bullets = [l for l in lines if re.match(r"^([-*•]|\d+[.)])\s", l)]
    if fmt == "list":
        return len(bullets) >= 2
    if fmt == "email":
        return len([p for p in re.split(r"\n\s*\n", typed.strip()) if p.strip()]) == \
            len([p for p in re.split(r"\n\s*\n", expected.strip()) if p.strip()])
    if fmt == "single_line":
        return "\n" not in typed.strip() and not typed.strip().endswith(".")
    if fmt == "goal_layout":
        want = {l.split(":")[0].lower() for l in expected.splitlines() if ":" in l}
        got = {l.split(":")[0].lower() for l in lines if ":" in l}
        return typed.strip().lower().startswith("goal:") and want <= got
    if fmt == "paragraph":
        return not bullets and not re.search(r"(?im)^(goal|context|constraints):", typed)
    return True  # "any": the layout is the model's call; only the words are checked


def parse_mode(cleanup):
    m = re.search(r"mode=(\w+)", cleanup or "")
    return m.group(1) if m else None


BROWSERS = {"com.google.Chrome", "com.apple.Safari", "company.thebrowser.Browser", "company.thebrowser.dia",
            "com.brave.Browser", "org.mozilla.firefox", "com.microsoft.edgemac"}
TERMINALS = {"com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable",
             "net.kovidgoyal.kitty", "io.alacritty", "com.github.wez.wezterm"}
AGENT_TITLE = re.compile(r"claude|codex|aider|gemini|cursor-agent|opencode|✳", re.I)
APPS_FOR_MODE = {
    "email": BROWSERS | {"com.apple.mail", "com.microsoft.Outlook"},
    "chat": {"net.whatsapp.WhatsApp", "desktop.WhatsApp", "com.tinyspeck.slackmacgap", "com.apple.MobileSMS",
             "com.microsoft.teams2", "com.hnc.Discord", "ru.keepcoder.Telegram"},
    "aiChat": BROWSERS | {"com.anthropic.claudefordesktop", "com.openai.chat"},
}


def wrong_app(sc, row):
    """The scenario was dictated somewhere other than where it says (e.g. a shell scenario typed into
    Claude Code). Such rows say nothing about the scenario, so they're reported apart, not as failures."""
    app, title = row.get("app"), row.get("title") or ""
    if not app:
        return False  # entered by hand
    m = sc["mode"]
    if m == "terminal":
        return app not in TERMINALS or bool(AGENT_TITLE.search(title))
    if m == "codingAgent":
        return app in TERMINALS and not AGENT_TITLE.search(title) or app in APPS_FOR_MODE["aiChat"] - BROWSERS \
            or app in APPS_FOR_MODE["chat"] or app == "com.apple.Notes"
    if m in APPS_FOR_MODE:
        return app not in APPS_FOR_MODE[m]
    return app in TERMINALS or app in APPS_FOR_MODE["chat"]  # prose / list: notes-like apps


def score(sc, row):
    typed, heard = row.get("typed", ""), row.get("heard")
    out_wer, out_cer = wer_cer(sc["expected"], typed)
    said = set(content_words(sc["say"]))
    typed_words = content_words(typed)
    novel = [w for w in typed_words if w not in said and w not in set(content_words(sc["expected"]))
             and not any(w in s or s in w for s in said if len(s) > 2)]
    exp_words = content_words(sc["expected"])
    recall = sum(1 for w in exp_words if w in set(typed_words)) / len(exp_words) if exp_words else 1.0
    nums = lambda s: set(re.findall(r"\d+", normalize(s)))
    checks = {
        "must": [m for m in sc["must"] if not any(has_phrase(typed, alt) for alt in m.split("|"))],
        "must_not": [m for m in sc["must_not"] if has_phrase(typed, m)],
        "layout": layout_ok(sc["format"], sc["expected"], typed),
        "negations": len(NEGATION.findall(typed.lower())) == len(NEGATION.findall(sc["expected"].lower())),
        "numbers": nums(sc["expected"]) <= nums(typed),
    }
    got_mode = parse_mode(row.get("cleanup"))
    checks["mode"] = got_mode is None or got_mode == sc["mode"]  # unknown when entered by hand
    passed = not checks["must"] and not checks["must_not"] and all(
        checks[k] for k in ("layout", "negations", "numbers", "mode"))
    s = {
        "wrong_app": wrong_app(sc, row),
        "out_wer": out_wer, "out_cer": out_cer, "strict_cer": strict_cer(sc["expected"], typed),
        "novel_rate": len(novel) / len(typed_words) if typed_words else 0.0, "novel": novel, "recall": recall,
        "checks": checks, "passed": passed, "mode_seen": got_mode,
    }
    if heard:
        s["stt_wer"], s["stt_cer"] = wer_cer(sc["say"], heard)
    return s


def pct(xs, q):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(round(q * (len(xs) - 1))))] if xs else None


def aggregate(pairs):
    """pairs: [(scenario, row, score)] -> summary dict."""
    if not pairs:
        return {}
    def mean(key):
        v = [s[key] for _, _, s in pairs if key in s]
        return statistics.mean(v) if v else None
    heard = [(sc, r) for sc, r, _ in pairs if r.get("heard")]
    lat = [r["total_ms"] for _, r, _ in pairs if r.get("total_ms") is not None]
    via = {}
    for _, r, _ in pairs:
        k = (r.get("cleanup") or "manual").split(" ")[0]
        via[k] = via.get(k, 0) + 1
    corpus = lambda refs, hyps: jiwer.wer([normalize(x) or "<empty>" for x in refs], [normalize(x) or "<empty>" for x in hyps])
    return {
        "n": len(pairs),
        "pass_rate": sum(s["passed"] for _, _, s in pairs) / len(pairs),
        "stt_wer": corpus([sc["say"] for sc, _ in heard], [r["heard"] for _, r in heard]) if heard else None,
        "stt_cer": mean("stt_cer"),
        "out_wer": corpus([sc["expected"] for sc, _, _ in pairs], [r["typed"] for _, r, _ in pairs]),
        "out_cer": mean("out_cer"),
        "strict_cer": mean("strict_cer"),
        "novel_rate": mean("novel_rate"),
        "recall": mean("recall"),
        "layout_ok": sum(s["checks"]["layout"] for _, _, s in pairs) / len(pairs),
        "mode_ok": sum(s["checks"]["mode"] for _, _, s in pairs) / len(pairs),
        "negations_ok": sum(s["checks"]["negations"] for _, _, s in pairs) / len(pairs),
        "numbers_ok": sum(s["checks"]["numbers"] for _, _, s in pairs) / len(pairs),
        "latency_p50_ms": pct(lat, 0.5), "latency_p95_ms": pct(lat, 0.95),
        "cleanup_via": via,
    }


# ---------------------------------------------------------------- commands

def pick(scenarios, args):
    out = scenarios
    if args.only:
        ids = set(args.only.split(","))
        out = [s for s in out if s["id"] in ids]
    if args.tags:
        tags = set(args.tags.split(","))
        out = [s for s in out if tags & set(s["tags"])]
    if args.mode:
        out = [s for s in out if s["mode"] == args.mode]
    return out


def latest_capture(after_ts):
    if not CAPTURE.exists():
        return None
    rows = [json.loads(l) for l in CAPTURE.read_text().splitlines() if l.strip()]
    rows = [r for r in rows if r.get("ts", 0) > after_ts and r.get("mode") == "dictation"]
    return rows[-1] if rows else None


def show_result(sc, row):
    s = score(sc, row)
    c = s["checks"]
    print(f"  heard:    {row.get('heard', '(not captured)')!r}")
    print(f"  typed:    {row['typed']!r}")
    print(f"  expected: {sc['expected']!r}")
    bad = [k for k in ("layout", "negations", "numbers", "mode") if not c[k]]
    if c["must"]: bad.append(f"missing {c['must']}")
    if c["must_not"]: bad.append(f"has {c['must_not']}")
    stt = f"STT WER {s['stt_wer']:.0%}  " if "stt_wer" in s else ""
    print(f"  {'PASS' if s['passed'] else 'FAIL'}  {stt}output WER {s['out_wer']:.0%}  strict CER {s['strict_cer']:.0%}"
          + (f"  mode={s['mode_seen']}" if s["mode_seen"] else "") + (f"  ({'; '.join(bad)})" if bad else ""))


def cmd_list(args):
    for s in pick(load_scenarios(), args):
        print(f"{s['id']:32} {s['mode']:12} {', '.join(s['tags'])}\n    say: {s['say']}")


def cmd_run(args):
    scenarios = pick(load_scenarios(), args)
    done = load_session(args.session)
    todo = [s for s in scenarios if args.redo or s["id"] not in done]
    if not CAPTURE.exists():
        print(f"Note: {CAPTURE} doesn't exist yet. It appears after the first dictation with the current app build.")
    print(f"Session '{args.session}': {len(todo)} of {len(scenarios)} scenarios to go. Results: {session_path(args.session)}\n"
          "For each one: go to the app, hold Right Shift, say the line, come back here.\n"
          "Keys: Enter = use the dictation you just did, m = type the observed text by hand, s = skip, q = quit.\n")
    for i, sc in enumerate(todo, 1):
        print(f"[{i}/{len(todo)}] {sc['id']}  ({sc['mode']})")
        print(f"  where: {sc['app']}")
        if sc.get("note"):
            print(f"  note:  {sc['note']}")
        print(f"  SAY:   \"{sc['say']}\"")
        start = time.time()
        while True:
            key = input("  > ").strip().lower()
            if key == "q":
                return
            if key == "s":
                break
            if key == "m":
                print("  Paste what appeared on screen; finish with an empty line:")
                lines = []
                while (l := input()) != "":
                    lines.append(l)
                row = {"typed": "\n".join(lines), "source": "manual"}
            else:
                cap = latest_capture(start)
                if not cap:
                    print("  No dictation captured since this scenario was shown. Dictate it, or press m to enter it by hand.")
                    continue
                row = {k: cap.get(k) for k in ("heard", "typed", "app", "title", "cleanup", "stt", "stt_ms", "total_ms", "audio_s")}
                row["source"] = "capture"
            row.update(id=sc["id"], at=datetime.now().isoformat(timespec="seconds"))
            save_row(args.session, row)
            show_result(sc, row)
            print()
            break
    print("Done. Run `uv run python scenario_eval.py report` for the metrics.")


def cmd_import(args):
    """id<TAB>observed[<TAB>heard]; observed may use \\n for line breaks."""
    ids = {s["id"] for s in load_scenarios()}
    n = 0
    for line in Path(args.file).read_text().splitlines():
        parts = line.split("\t")
        if len(parts) < 2 or parts[0] not in ids:
            continue
        row = {"id": parts[0], "typed": parts[1].replace("\\n", "\n"), "source": "manual",
               "at": datetime.now().isoformat(timespec="seconds")}
        if len(parts) > 2 and parts[2]:
            row["heard"] = parts[2]
        save_row(args.session, row)
        n += 1
    print(f"Imported {n} rows into session '{args.session}'.")


def fmt(v, kind="pct"):
    if v is None:
        return "–"
    return f"{v:.1%}" if kind == "pct" else f"{v:.0f}"


def cmd_report(args):
    scenarios = {s["id"]: s for s in load_scenarios()}
    rows = load_session(args.session)
    scored = [(scenarios[i], r, score(scenarios[i], r)) for i, r in rows.items() if i in scenarios]
    misplaced = [p for p in scored if p[2]["wrong_app"]]
    pairs = [p for p in scored if not p[2]["wrong_app"]]
    if not pairs:
        sys.exit(f"No results in session '{args.session}'. Run `scenario_eval.py run` first.")
    overall = aggregate(pairs)
    by_mode = {}
    for p in pairs:
        by_mode.setdefault(p[0]["mode"], []).append(p)
    clean = [p for p in pairs if "noise" not in p[0]["tags"]]
    noisy = [p for p in pairs if "noise" in p[0]["tags"]]

    md = [f"# InstructFlow scenario eval: {args.session}", "",
          f"{overall['n']} of {len(scenarios)} scenarios. Source: {', '.join(sorted({r.get('source', 'manual') for _, r, _ in pairs}))}. "
          + (" Replay = text-to-speech into live speech-to-text and the app's cleanup code (no mic, no typing into the app). "
             if any(r.get('source', '').startswith('replay') for _, r, _ in pairs) else "")
          + "Lower is better for error rates; higher for the rest.", "",
          "| | Pass | STT WER | Output WER | Output CER | Strict CER | Novel words | Kept words | Layout | Mode | p50 ms | p95 ms |",
          "|---|---|---|---|---|---|---|---|---|---|---|---|"]
    def line(name, a):
        return (f"| {name} ({a['n']}) | {fmt(a['pass_rate'])} | {fmt(a['stt_wer'])} | {fmt(a['out_wer'])} | {fmt(a['out_cer'])} | "
                f"{fmt(a['strict_cer'])} | {fmt(a['novel_rate'])} | {fmt(a['recall'])} | {fmt(a['layout_ok'])} | "
                f"{fmt(a['mode_ok'])} | {fmt(a['latency_p50_ms'], 'n')} | {fmt(a['latency_p95_ms'], 'n')} |")
    md.append(line("**All**", overall))
    for m, ps in sorted(by_mode.items()):
        md.append(line(m, aggregate(ps)))
    if clean and noisy:
        md.append(line("quiet room", aggregate(clean)))
        md.append(line("background noise", aggregate(noisy)))
    md += ["", f"Negations kept: {fmt(overall['negations_ok'])}. Numbers kept: {fmt(overall['numbers_ok'])}. "
           f"Cleanup path: {', '.join(f'{k} {v}' for k, v in sorted(overall['cleanup_via'].items()))}.", "",
           ]
    if misplaced:
        md += [f"**Not scored ({len(misplaced)}):** dictated into a different app than the scenario asks, so they test "
               "that app's mode instead: " + "; ".join(f"{sc['id']} (in {r.get('app')}"
               + (f" \"{r.get('title')}\"" if r.get('title') else "") + f", routed {s['mode_seen']})" for sc, r, s in misplaced)
               + ". Redo them with `run --only " + ",".join(sc["id"] for sc, _, _ in misplaced) + " --redo`.", ""]
    md += ["## Scenarios", ""]
    for sc, r, s in sorted(pairs, key=lambda p: (p[2]["passed"], p[0]["id"])):
        c = s["checks"]
        issues = [k for k in ("layout", "negations", "numbers", "mode") if not c[k]]
        if c["must"]: issues.append("missing " + ", ".join(c["must"]))
        if c["must_not"]: issues.append("has " + ", ".join(c["must_not"]))
        if s["novel"]: issues.append("novel words: " + ", ".join(s["novel"][:6]))
        md += [f"### {'✅' if s['passed'] else '❌'} {sc['id']} ({sc['mode']})", "",
               f"- **Said:** {sc['say']}"]
        if r.get("heard"):
            md.append(f"- **Heard:** {r['heard']}  (STT WER {s['stt_wer']:.0%})")
        md += [f"- **Expected:**\n\n```\n{sc['expected']}\n```",
               f"- **Observed:**\n\n```\n{r['typed']}\n```",
               f"- Output WER {s['out_wer']:.0%}, strict CER {s['strict_cer']:.0%}"
               + (f", mode {s['mode_seen']}" if s["mode_seen"] else "") + (f", {r['total_ms']} ms" if r.get("total_ms") else "")
               + (f", cleanup {r['cleanup']}" if r.get("cleanup") else ""),
               ]
        if issues:
            md.append(f"- **Issues:** {'; '.join(issues)}")
        md.append("")
    out = RESULTS / f"scenario-report-{args.session}.md"
    out.write_text("\n".join(md))
    (RESULTS / f"scenario-report-{args.session}.json").write_text(json.dumps({
        "session": args.session, "overall": overall, "by_mode": {m: aggregate(ps) for m, ps in by_mode.items()},
        "scenarios": [{"id": sc["id"], "mode": sc["mode"], **{k: v for k, v in s.items()}} for sc, _, s in pairs],
    }, indent=2, default=str))
    print("\n".join(md[:6 + len(by_mode) + 4]))
    print(f"\nFull report: {out}")


# ---------------------------------------------------------------- replay (no human)

CHAT_KEYTERMS = ["lol", "omg", "btw", "idk", "tbh", "brb"]  # as ModeRouter.chatKeyterms


def dictionary_terms():
    """The plain lines of the app's dictionary, which the app sends to Scribe as keyterms."""
    p = Path.home() / "Library/Application Support/InstructFlow/dictionary.txt"
    if not p.exists():
        return []
    return [l.strip() for l in p.read_text().splitlines()
            if l.strip() and not l.startswith("#") and "->" not in l and len(l.strip()) <= 20][:50]
CHAT_APPS = {"net.whatsapp.WhatsApp", "com.tinyspeck.slackmacgap", "com.apple.MobileSMS"}


def keys():
    env = {}
    for line in (Path.home() / "Library/Application Support/InstructFlow/keys.env").read_text().splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            k, v = line.split("=", 1)
            env[k.strip()] = v.strip().strip('"')
    return env


def tts(text, path):
    import subprocess
    subprocess.run(["say", "-v", args_voice, "-o", str(path), "--data-format=LEI16@16000", text], check=True)


def with_noise(audio, snr_db, seed):
    """Another speaker (LibriSpeech clip) plus a little hiss, at the given speech-to-noise ratio."""
    import numpy as np
    import soundfile as sf
    rng = np.random.default_rng(seed)
    clips = sorted((HERE / "data/audio").glob("libri_*.wav"))
    other, _ = sf.read(clips[seed % len(clips)], dtype="float32")
    noise = np.resize(other, len(audio)) + 0.05 * rng.standard_normal(len(audio)).astype("float32")
    p = lambda x: float(np.mean(x ** 2)) + 1e-12
    noise *= (p(audio) / (p(noise) * 10 ** (snr_db / 10))) ** 0.5
    return np.clip(audio + noise, -1, 1)


async def scribe(audio, keyterms, key):
    """The app's Scribe settings; audio sent faster than real time, latency timed from the commit."""
    import asyncio, base64
    import numpy as np
    import websockets
    q = "&".join(["model_id=scribe_v2_realtime", "audio_format=pcm_16000", "commit_strategy=manual", "language_code=en",
                  "filter_background_audio=true"] + ["keyterms=" + __import__("urllib.parse").parse.quote(k) for k in keyterms])
    async with websockets.connect("wss://api.elevenlabs.io/v1/speech-to-text/realtime?" + q,
                                  additional_headers={"xi-api-key": key}) as ws:
        await ws.recv()
        pcm = (audio * 32767).astype("<i2").tobytes()
        t_commit = time.time()
        for i in range(0, len(pcm), 3200):
            last = i + 3200 >= len(pcm)
            if last:
                t_commit = time.time()
            await ws.send(json.dumps({"message_type": "input_audio_chunk", "commit": last, "sample_rate": 16000,
                                      "audio_base_64": base64.b64encode(pcm[i:i + 3200]).decode()}))
            await asyncio.sleep(0.02)
        parts = []
        while True:
            m = json.loads(await asyncio.wait_for(ws.recv(), 15))
            if m["message_type"].startswith("committed"):
                parts.append(m.get("text", ""))
                return " ".join(parts).strip(), int((time.time() - t_commit) * 1000)
            if "error" in m["message_type"] or m["message_type"] in ("commit_throttled", "invalid_request"):
                raise RuntimeError(m)


def clean_with_app_code(items):
    """Runs the app's cleanup (ScenarioReplay Swift test) over [{id, heard, bundle, title}] -> rows."""
    import os, subprocess, tempfile
    env = keys()
    work = Path(tempfile.mkdtemp(prefix="clean-"))
    inp, out = work / "in.jsonl", work / "out.jsonl"
    inp.write_text("".join(json.dumps(i, ensure_ascii=False) + "\n" for i in items))
    run_env = dict(os.environ, **{k: v for k, v in env.items() if k in ("GROQ_API_KEY", "ANTHROPIC_API_KEY")},
                   INSTRUCTFLOW_REPLAY_IN=str(inp), INSTRUCTFLOW_REPLAY_OUT=str(out))
    r = subprocess.run(["swift", "test", "--filter", "ScenarioReplay"], cwd=HERE.parent / "app", env=run_env,
                       capture_output=True, text=True)
    if not out.exists():
        sys.exit("Cleanup replay failed:\n" + r.stdout[-3000:] + r.stderr[-2000:])
    return [json.loads(l) for l in out.read_text().splitlines() if l.strip()]


def cmd_reclean(args):
    """Before/after on identical input: what speech-to-text heard in a real session, cleaned by today's code."""
    rows = [r for r in load_session(args.session).values() if r.get("heard")]
    items = [{"id": r["id"], "heard": r["heard"], "bundle": r.get("app") or "", "title": r.get("title") or ""} for r in rows]
    print(f"Re-cleaning {len(items)} transcripts from session '{args.session}' with the current cleanup code...")
    by_id = {r["id"]: r for r in rows}
    new = args.session + "-reclean"
    session_path(new).unlink(missing_ok=True)
    for row in clean_with_app_code(items):
        old = by_id[row["id"]]
        row.update(title=old.get("title"), stt_ms=old.get("stt_ms"), audio_s=old.get("audio_s"),
                   total_ms=(old.get("stt_ms") or 0) + row.pop("cleanup_ms"),
                   source=f"reclean of {args.session} (same heard text, current code)", at=datetime.now().isoformat(timespec="seconds"))
        save_row(new, row)
    args.session = new
    cmd_report(args)


def cmd_compare(args):
    scenarios = {s["id"]: s for s in load_scenarios()}
    cols = [("Pass", "pass_rate"), ("STT WER", "stt_wer"), ("Output WER", "out_wer"), ("Output CER", "out_cer"),
            ("Strict CER", "strict_cer"), ("Novel words", "novel_rate"), ("Kept words", "recall"), ("Layout", "layout_ok"),
            ("Mode", "mode_ok"), ("Negations", "negations_ok"), ("Numbers", "numbers_ok")]
    lines = ["| Session | n | " + " | ".join(c for c, _ in cols) + " | p50 ms | p95 ms |",
             "|---" * (len(cols) + 4) + "|"]
    for name in args.sessions:
        scored = [(scenarios[i], r, score(scenarios[i], r)) for i, r in load_session(name).items() if i in scenarios]
        pairs = [p for p in scored if not p[2]["wrong_app"]]
        if not pairs:
            continue
        a = aggregate(pairs)
        lines.append(f"| {name} | {a['n']} | " + " | ".join(fmt(a[k]) for _, k in cols)
                     + f" | {fmt(a['latency_p50_ms'], 'n')} | {fmt(a['latency_p95_ms'], 'n')} |")
    print("\n".join(lines))
    if args.out:
        Path(args.out).write_text("\n".join(lines) + "\n")


def cmd_replay(args):
    import asyncio, subprocess, tempfile
    import soundfile as sf
    global args_voice
    args_voice = args.voice
    env = keys()
    scenarios = pick(load_scenarios(), args)
    work = Path(tempfile.mkdtemp(prefix="replay-"))
    items = []
    for n, sc in enumerate(scenarios):
        wav = work / f"{sc['id']}.wav"
        tts(sc["say"].replace("sub- sub-agent", "sub, sub-agent"), wav)
        audio, _ = sf.read(wav, dtype="float32")
        if "noise" in sc["tags"]:
            audio = with_noise(audio, args.snr, n)
        terms = dictionary_terms() + (CHAT_KEYTERMS if sc["bundle"] in CHAT_APPS else [])
        try:
            heard, stt_ms = asyncio.run(scribe(audio, terms, env["ELEVENLABS_API_KEY"]))
        except Exception as e:
            print(f"  {sc['id']}: speech-to-text failed: {e}")
            continue
        print(f"  {sc['id']:32} heard: {heard}")
        items.append({"id": sc["id"], "heard": heard, "bundle": sc["bundle"], "title": sc["title"],
                      "stt_ms": stt_ms, "audio_s": len(audio) / 16000})
    inp, out = work / "in.jsonl", work / "out.jsonl"
    inp.write_text("".join(json.dumps(i, ensure_ascii=False) + "\n" for i in items))
    print(f"Cleaning {len(items)} transcripts with the app's cleanup chain...")
    run_env = dict(__import__("os").environ, **{k: v for k, v in env.items() if k in ("GROQ_API_KEY", "ANTHROPIC_API_KEY")},
                   INSTRUCTFLOW_REPLAY_IN=str(inp), INSTRUCTFLOW_REPLAY_OUT=str(out))
    r = subprocess.run(["swift", "test", "--filter", "ScenarioReplay"], cwd=HERE.parent / "app", env=run_env,
                       capture_output=True, text=True)
    if not out.exists():
        sys.exit("Cleanup replay failed:\n" + r.stdout[-3000:] + r.stderr[-2000:])
    stt = {i["id"]: i for i in items}
    for line in out.read_text().splitlines():
        row = json.loads(line)
        i = stt[row["id"]]
        row.update(title=i["title"], stt_ms=i["stt_ms"], audio_s=i["audio_s"], total_ms=i["stt_ms"] + row.pop("cleanup_ms"),
                   source=f"replay: say -v {args.voice}" + (f", noise {args.snr} dB SNR" if "noise" in row["id"] else ""),
                   at=datetime.now().isoformat(timespec="seconds"))
        save_row(args.session, row)
    cmd_report(args)


def cmd_selftest(_):
    scs = {s["id"]: s for s in load_scenarios()}
    def run(i, typed, heard=None, cleanup=None):
        return score(scs[i], {"typed": typed, "heard": heard, "cleanup": cleanup})
    perfect = run("list-grocery", scs["list-grocery"]["expected"], scs["list-grocery"]["say"], "groq [mode=list (spoken cue)]")
    assert perfect["passed"] and perfect["out_wer"] == 0 and perfect["strict_cer"] == 0 and perfect["stt_wer"] == 0, perfect
    lol = run("chat-lol", "Love, yeah, that works for me. See you at 5:00.", cleanup="groq [mode=chat (app: chat)]")
    assert not lol["passed"] and "lol" in " ".join(lol["checks"]["must"]) and "love" in lol["checks"]["must_not"], lol
    assert "love" in lol["novel"], lol
    flat = run("email-checkin", "Hi, Sarah. Just checking in on the contract. Let me know if you need anything. Thanks. Shekhar.")
    assert not flat["checks"]["layout"] and flat["out_wer"] < 0.2, flat
    neg = run("prose-negation", "I think we should ship this before the security review is done.")
    assert not neg["checks"]["negations"], neg
    shell = run("shell-git", "git checkout -b fix/auth", cleanup="groq [mode=terminal (app: terminal at a shell prompt)]")
    assert shell["passed"], shell
    wrong_mode = run("shell-git", "git checkout -b fix/auth", cleanup="groq [mode=codingAgent (app: terminal)]")
    assert not wrong_mode["passed"] and not wrong_mode["checks"]["mode"]
    assert not has_phrase("the number is 5", "um") and has_phrase("um, so", "um") and has_phrase("two passports", "passport")
    misplaced = score(scs["shell-git"], {"typed": "x", "app": "com.apple.Terminal", "title": "✳ Claude Code"})
    assert misplaced["wrong_app"]
    assert not score(scs["shell-git"], {"typed": "x", "app": "com.apple.Terminal", "title": "-zsh"})["wrong_app"]
    assert score(scs["code-thinking"], {"typed": "x", "app": "com.anthropic.claudefordesktop"})["wrong_app"]
    assert not score(scs["email-checkin"], {"typed": "x", "app": "com.apple.mail"})["wrong_app"]
    print("selftest ok")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("compare")
    p.add_argument("sessions", nargs="+")
    p.add_argument("--out")
    for name in ("list", "run", "import", "report", "selftest", "replay", "reclean"):
        p = sub.add_parser(name)
        p.add_argument("--session", default=datetime.now().strftime("%Y%m%d"))
        if name == "replay":
            p.set_defaults(session="replay-" + datetime.now().strftime("%Y%m%d"))
            p.add_argument("--voice", default="Samantha")
            p.add_argument("--snr", type=float, default=5.0, help="speech-to-noise ratio for noise scenarios, dB")
        if name in ("list", "run", "replay"):
            p.add_argument("--only")
            p.add_argument("--tags")
            p.add_argument("--mode")
        if name == "run":
            p.add_argument("--redo", action="store_true", help="redo scenarios already in the session")
        if name == "import":
            p.add_argument("file")
    args = ap.parse_args()
    {"list": cmd_list, "run": cmd_run, "import": cmd_import, "report": cmd_report, "selftest": cmd_selftest,
     "replay": cmd_replay, "reclean": cmd_reclean, "compare": cmd_compare}[args.cmd](args)


if __name__ == "__main__":
    main()
