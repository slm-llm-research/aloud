"""Publishes the scenario eval results: BENCHMARKS.md (repo root), docs/results/results.json and
docs/results/index.html (a self-contained page, also served by GitHub Pages).

    uv run python export_results.py

Which sessions are compared is set in RUNS / COMPARISONS below; add a new run there after
`scenario_eval.py run` or `replay`, then re-run this script.
"""

import json
import platform
import subprocess
from datetime import date
from pathlib import Path

import scenario_eval as se

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs" / "results"

RUNS = [
    {"id": "baseline-1031", "label": "Field test, before any fixes", "kind": "Real voice",
     "about": "The first hands-on test, scored from the app's log. Small: 6 scenarios matched the set."},
    {"id": "20261031", "label": "Real voice, build under test", "kind": "Real voice",
     "about": "Scenarios spoken into the real apps; what was typed by the build installed at the time."},
    {"id": "20261031-reclean", "label": "Real voice, current code", "kind": "Real voice",
     "about": "The same speech-to-text transcripts, cleaned again by the current code. Same input, so the difference is the code."},
    {"id": "replay-20261031", "label": "Synthetic voice, first run", "kind": "Synthetic voice",
     "about": "macOS text-to-speech into live speech-to-text and the app's cleanup code, before the fixes it found."},
    {"id": "replay-20261031-v3", "label": "Synthetic voice, current code", "kind": "Synthetic voice",
     "about": "The same replay after the fixes."},
]
COMPARISONS = [
    {"title": "Real voice", "before": "20261031", "after": "20261031-reclean",
     "note": "Identical speech-to-text transcripts from the author's voice, cleaned by the build under test and by the current code."},
    {"title": "Synthetic voice", "before": "replay-20261031", "after": "replay-20261031-v3",
     "note": "All 37 scenarios spoken by macOS text-to-speech; noise scenarios mix in a second speaker at 5 dB SNR."},
]
MODE_NAMES = {"prose": "Notes / prose", "email": "Email", "chat": "Chat", "list": "Lists", "aiChat": "AI chat",
              "codingAgent": "Coding agent", "terminal": "Shell"}
METRICS = [("pass_rate", "Pass", True), ("stt_wer", "STT WER", False), ("out_wer", "Output WER", False),
           ("out_cer", "Output CER", False), ("strict_cer", "Strict CER", False), ("novel_rate", "Novel words", False),
           ("recall", "Kept words", True), ("layout_ok", "Layout", True), ("mode_ok", "Mode", True),
           ("negations_ok", "Negations kept", True), ("numbers_ok", "Numbers kept", True)]


def app_name(row):
    app, title = row.get("app") or "", row.get("title") or ""
    if app == "com.apple.Terminal":
        return "Claude Code (Terminal)" if se.AGENT_TITLE.search(title) else "Terminal (zsh)"
    if app in se.BROWSERS:
        t = title.lower()
        return "Gmail (Chrome)" if "mail" in t else "ChatGPT (Chrome)" if "chatgpt" in t else "Chrome"
    return {"com.apple.Notes": "Notes", "net.whatsapp.WhatsApp": "WhatsApp", "com.anthropic.claudefordesktop": "Claude desktop",
            "com.openai.codex": "Codex app", "com.apple.mail": "Mail"}.get(app, app or "entered by hand")


def scored(session):
    scs = {s["id"]: s for s in se.load_scenarios()}
    rows = se.load_session(session)
    out = [(scs[i], r, se.score(scs[i], r)) for i, r in rows.items() if i in scs]
    return [p for p in out if not p[2]["wrong_app"]], [p for p in out if p[2]["wrong_app"]]


def summary(pairs):
    a = se.aggregate(pairs)
    return {k: (round(v, 4) if isinstance(v, float) else v) for k, v in a.items()}


def group(pairs, key):
    groups = {}
    for p in pairs:
        groups.setdefault(key(p), []).append(p)
    return groups


def environment():
    def sh(*cmd):
        try:
            return subprocess.run(cmd, capture_output=True, text=True).stdout.strip()
        except OSError:
            return ""
    return {
        "mac": f"{sh('sysctl', '-n', 'machdep.cpu.brand_string')} ({sh('sysctl', '-n', 'hw.model')})",
        "macos": f"macOS {platform.mac_ver()[0]}",
        "speech_to_text": "ElevenLabs Scribe v2 realtime (filter_background_audio on, dictionary + chat keyterms)",
        "cleanup": "Groq openai/gpt-oss-120b (1.5 s timeout), then Claude Haiku 5.5 (2.5 s), then rule-based fallback",
        "synthetic_voice": "macOS `say -v Samantha`, 16 kHz; noise scenarios add a LibriSpeech speaker plus hiss at 5 dB SNR",
        "latency": "Real voice: key release to text typed. Synthetic: speech-to-text commit to result, plus cleanup.",
    }


def build():
    data = {"generated": date.today().isoformat(), "environment": environment(), "runs": [], "comparisons": [],
            "by_mode": [], "by_app": [], "by_condition": [], "scenarios": [], "not_scored": []}
    cache = {}
    for run in RUNS:
        pairs, misplaced = scored(run["id"])
        cache[run["id"]] = pairs
        data["runs"].append({**run, **summary(pairs)})
        for m, ps in group(pairs, lambda p: p[0]["mode"]).items():
            data["by_mode"].append({"run": run["id"], "mode": MODE_NAMES.get(m, m), **summary(ps)})
        for sc, r, s in misplaced:
            data["not_scored"].append({"run": run["id"], "scenario": sc["id"], "asked_for": sc["app"],
                                       "dictated_in": app_name(r), "routed_as": MODE_NAMES.get(s["mode_seen"], s["mode_seen"])})
    for c in COMPARISONS:
        data["comparisons"].append({**c, "before_metrics": next(r for r in data["runs"] if r["id"] == c["before"]),
                                    "after_metrics": next(r for r in data["runs"] if r["id"] == c["after"])})
    # Real voice, per app actually used.
    before, after = cache["20261031"], {p[0]["id"]: p for p in cache["20261031-reclean"]}
    for app, ps in group(before, lambda p: app_name(p[1])).items():
        aps = [after[p[0]["id"]] for p in ps if p[0]["id"] in after]
        b, a = summary(ps), summary(aps)
        data["by_app"].append({"app": app, "scenarios": b["n"], "modes": sorted({MODE_NAMES[p[0]["mode"]] for p in ps}),
                               "pass_before": b["pass_rate"], "pass_after": a["pass_rate"],
                               "out_wer_before": b["out_wer"], "out_wer_after": a["out_wer"],
                               "stt_wer": b["stt_wer"], "latency_p50_ms": b["latency_p50_ms"]})
    data["by_app"].sort(key=lambda r: -r["scenarios"])
    # Synthetic, quiet room vs background noise.
    for rid in ("replay-20261031", "replay-20261031-v3"):
        for cond, ps in group(cache[rid], lambda p: "Background noise" if "noise" in p[0]["tags"] else "Quiet room").items():
            data["by_condition"].append({"run": rid, "condition": cond, **summary(ps)})
    # Scenario detail: real voice before/after, and the synthetic run.
    for sc, r, s in before:
        a_sc, a_r, a_s = after[sc["id"]]
        data["scenarios"].append({"set": "Real voice", "scenario": sc["id"], "mode": MODE_NAMES[sc["mode"]], "app": app_name(r),
                                  "said": sc["say"], "heard": r.get("heard", ""), "expected": sc["expected"],
                                  "before": r["typed"], "after": a_r["typed"], "pass_before": s["passed"], "pass_after": a_s["passed"],
                                  "stt_wer": round(s.get("stt_wer", 0), 4)})
    first = {p[0]["id"]: p for p in cache["replay-20261031"]}
    for sc, r, s in cache["replay-20261031-v3"]:
        f = first.get(sc["id"])
        data["scenarios"].append({"set": "Synthetic voice", "scenario": sc["id"], "mode": MODE_NAMES[sc["mode"]],
                                  "app": app_name(r), "said": sc["say"], "heard": r.get("heard", ""), "expected": sc["expected"],
                                  "before": f[1]["typed"] if f else "", "after": r["typed"],
                                  "pass_before": f[2]["passed"] if f else None, "pass_after": s["passed"],
                                  "stt_wer": round(s.get("stt_wer", 0), 4)})
    return data


def pct(v):
    return "–" if v is None else f"{v:.1%}"


def delta(b, a, higher_better):
    if b is None or a is None:
        return ""
    d = (a - b) * 100
    if abs(d) < 0.05:
        return " (±0)"
    good = (d > 0) == higher_better
    return f" ({'+' if d > 0 else '−'}{abs(d):.1f} pts {'✓' if good else '✗'})"


def markdown(data):
    env = data["environment"]
    L = ["# Aloud benchmarks", "",
         f"Measured {data['generated']} with the scenario eval harness ([`bench/scenario_eval.py`](bench/scenario_eval.py)). "
         "Interactive version: [`docs/results/index.html`](docs/results/index.html) "
         "(served at https://slm-llm-research.github.io/aloud/results/). Regenerate everything with "
         "`cd bench && uv run python export_results.py`.", "",
         "## Before and after", ""]
    for c in data["comparisons"]:
        b, a = c["before_metrics"], c["after_metrics"]
        L += [f"### {c['title']} ({a['n']} scenarios)", "", c["note"], "",
              "| Metric | Before | After |", "|---|---|---|"]
        for k, name, hb in METRICS:
            if b.get(k) is None and a.get(k) is None:
                continue
            L.append(f"| {name} | {pct(b.get(k))} | **{pct(a.get(k))}**{delta(b.get(k), a.get(k), hb)} |")
        L.append(f"| Latency p50 / p95 | {b['latency_p50_ms']} / {b['latency_p95_ms']} ms | {a['latency_p50_ms']} / {a['latency_p95_ms']} ms |")
        L.append("")
    L += ["Error rates (WER, CER, novel words): lower is better. Everything else: higher is better.", "",
          "## Every run", "", "| Run | Voice | Scenarios | Pass | STT WER | Output WER | Strict CER | Novel words | Negations kept | p50 ms | p95 ms |",
          "|---|---|---|---|---|---|---|---|---|---|---|"]
    for r in data["runs"]:
        L.append(f"| {r['label']} | {r['kind']} | {r['n']} | {pct(r['pass_rate'])} | {pct(r['stt_wer'])} | {pct(r['out_wer'])} | "
                 f"{pct(r['strict_cer'])} | {pct(r['novel_rate'])} | {pct(r['negations_ok'])} | {r['latency_p50_ms']} | {r['latency_p95_ms']} |")
    L += ["", "## By app (real voice)", "",
          "Where each scenario was actually dictated, and how it did before and after on the same transcripts.", "",
          "| App | Modes | Scenarios | Pass before | Pass after | Output WER before | Output WER after | STT WER | p50 ms |",
          "|---|---|---|---|---|---|---|---|---|"]
    for r in data["by_app"]:
        L.append(f"| {r['app']} | {', '.join(r['modes'])} | {r['scenarios']} | {pct(r['pass_before'])} | **{pct(r['pass_after'])}** | "
                 f"{pct(r['out_wer_before'])} | {pct(r['out_wer_after'])} | {pct(r['stt_wer'])} | {r['latency_p50_ms']} |")
    L += ["", "## By mode", "", "| Mode | " + " | ".join(r["label"] for r in data["runs"][1:]) + " |",
          "|---" * len(data["runs"]) + "|"]
    for m in MODE_NAMES.values():
        cells = []
        for r in data["runs"][1:]:
            x = next((b for b in data["by_mode"] if b["run"] == r["id"] and b["mode"] == m), None)
            cells.append(f"{pct(x['pass_rate'])} ({x['n']})" if x else "–")
        L.append(f"| {m} | " + " | ".join(cells) + " |")
    L += ["", "Pass rate (scenarios scored).", "", "## Quiet room vs background noise (synthetic voice)", "",
          "| Run | Condition | Scenarios | Pass | STT WER | Output WER | Novel words |", "|---|---|---|---|---|---|---|"]
    for r in data["by_condition"]:
        label = next(x["label"] for x in data["runs"] if x["id"] == r["run"])
        L.append(f"| {label} | {r['condition']} | {r['n']} | {pct(r['pass_rate'])} | {pct(r['stt_wer'])} | {pct(r['out_wer'])} | {pct(r['novel_rate'])} |")
    L += ["", "## How it was tested", "",
          "- **Scenarios:** [`bench/scenarios.jsonl`](bench/scenarios.jsonl), 37 lines to speak across Notes, Gmail, WhatsApp, "
          "ChatGPT, Claude Code and a shell. They cover self-corrections, negations, numbers, names, slang, stutters, lists, "
          "email layout, shell symbols, and five background-noise variants. Each has the expected text and checks.",
          "- **Real voice:** the author spoke each scenario into the named app with the installed app build. The app records "
          "what speech-to-text heard and what it typed (`~/Library/Logs/Aloud/dictations.jsonl`), and `scenario_eval.py run` "
          "pairs each record with its scenario.",
          "- **Before/after on identical input:** `scenario_eval.py reclean` runs the current cleanup code over the transcripts "
          "speech-to-text produced in the real-voice session, so speech recognition is held fixed.",
          "- **Synthetic voice:** `scenario_eval.py replay` speaks every scenario with macOS text-to-speech, streams it to live "
          "speech-to-text with the app's settings, and runs the app's cleanup code (the `ScenarioReplay` Swift test). It skips "
          "only the mic and typing into the app.",
          "- **Pass:** required phrases present, banned phrases absent, layout right for the app (list, email, single line, "
          "Goal/Context/Constraints), every negation and number kept, and the right mode chosen.",
          "- **Not scored:** a scenario dictated into a different app than it names (for example a shell scenario said into "
          "Claude Code) tests that other app's mode, so it is left out and listed below.", "",
          "| Environment | |", "|---|---|"]
    L += [f"| {k.replace('_', ' ').capitalize()} | {v} |" for k, v in env.items()]
    if data["not_scored"]:
        L += ["", "### Not scored", "", "| Run | Scenario | Asked for | Dictated in | Routed as |", "|---|---|---|---|---|"]
        for r in data["not_scored"]:
            L.append(f"| {r['run']} | {r['scenario']} | {r['asked_for']} | {r['dictated_in']} | {r['routed_as']} |")
    L += ["", "## Scenario by scenario (real voice)", "",
          "| Scenario | App | Heard (speech-to-text) | Typed before | Typed after | Before | After |", "|---|---|---|---|---|---|---|"]
    cell = lambda s: (s or "").replace("|", "\\|").replace("\n", "<br>")
    for r in sorted((x for x in data["scenarios"] if x["set"] == "Real voice"),
                    key=lambda x: (x["before"] == x["after"], x["pass_after"], x["scenario"])):
        L.append(f"| `{r['scenario']}` | {r['app']} | {cell(r['heard'])} | {cell(r['before'])} | {cell(r['after'])} | "
                 f"{'✅' if r['pass_before'] else '❌'} | {'✅' if r['pass_after'] else '❌'} |")
    L += ["", "Failures that remain are mostly speech-to-text mishearings that reach the cleanup already wrong "
          "(\"omg\" spelled out as \"Oh my God\", \"rename\" heard as \"Can you\"). The cleanup does not guess at those: a guess "
          "would break the promise to keep the speaker's words. Full per-scenario reports: [`bench/results/`](bench/results/).", ""]
    return "\n".join(L)


def main():
    data = build()
    DOCS.mkdir(parents=True, exist_ok=True)
    (DOCS / "results.json").write_text(json.dumps(data, indent=1, ensure_ascii=False))
    template = (Path(__file__).parent / "results_page.html").read_text()
    blob = json.dumps(data, ensure_ascii=False).replace("</", "<\\/")
    (DOCS / "index.html").write_text(template.replace("/*__DATA__*/null", blob))
    (ROOT / "BENCHMARKS.md").write_text(markdown(data))
    print(f"Wrote {DOCS / 'index.html'}, {DOCS / 'results.json'}, {ROOT / 'BENCHMARKS.md'}")


if __name__ == "__main__":
    main()
