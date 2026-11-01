"""Behavior evals for the cleanup: does each app get the right transformation, and only when it should?

The dataset (behavior/cases.jsonl, spec in behavior/SPEC.md) holds labelled dictations: positives where a
transformation should happen (lay out a prompt, make a list, apply a self-correction, repair a misheard
word) and negatives that look similar but must be left alone. Cases are split into `dev` (failures may be
read and used to improve the prompts) and `test` (held out: scored at the end, never used for tuning).

    python3 behavior_eval.py build                              # parts/*.jsonl -> cases.jsonl, validated, split
    python3 behavior_eval.py run --name base --config app       # the app's chain (Groq, then Haiku)
    python3 behavior_eval.py run --name base --config groq      # or one model alone: groq / haiku
    python3 behavior_eval.py report --name base                 # pass rates by category/polarity + dev failures
    python3 behavior_eval.py report --name v2 --against base    # before/after
    python3 behavior_eval.py report --name v2 --split test      # held-out score (only at the end)

`run` uses the app's API keys from ~/Library/Application Support/Aloud/keys.env (never printed) and the
Swift runner app/Tests/CleanupKitTests/BehaviorReplay.swift, i.e. the same cleanup code the app ships.
Standard library only.
"""

import argparse
import collections
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
DATA = HERE / "behavior"
CASES = DATA / "cases.jsonl"
RESULTS = HERE / "results" / "behavior"
APP = HERE.parent / "app"
KEYS = Path.home() / "Library/Application Support/Aloud/keys.env"

FIELDS = ["id", "category", "polarity", "app", "bundle", "title", "say", "format", "must", "must_not", "why"]
DIFFICULTY = {"easy", "hard"}
SEEN = DATA / "seen.json"  # cases read while debugging: never in the held-out test split
FORMATS = {"prompt", "paragraph", "list", "email", "single_line", "any"}
CATEGORIES = {"prompt_vs_speech", "list_vs_sentences", "self_correction", "chat", "email", "ai_chat",
              "terminal", "misheard", "fidelity"}
SPLITS = ["train", "dev", "test"]


def app_group(case):
    b, t = case.get("bundle", ""), case.get("title", "").lower()
    if b in ("com.apple.Terminal", "com.mitchellh.ghostty", "com.googlecode.iterm2"):
        return "claude_code" if ("claude" in t or "✳" in t) else "terminal"
    if b == "com.openai.codex":
        return "codex"
    if b in ("com.todesktop.230313mzl4w4u92", "com.microsoft.VSCode"):
        return "editor"
    if b in ("net.whatsapp.WhatsApp", "com.tinyspeck.slackmacgap", "com.apple.MobileSMS", "com.hnc.Discord",
             "com.microsoft.teams2"):
        return "chat_apps"
    if b in ("com.apple.mail", "com.microsoft.Outlook") or "gmail" in t:
        return "email_apps"
    if b in ("com.anthropic.claudefordesktop", "com.openai.chat") or t in ("claude", "chatgpt"):
        return "ai_apps"
    if b in ("com.apple.Notes",):
        return "notes"
    if b in ("com.apple.reminders", "com.culturedcode.ThingsMac"):
        return "todo"
    return "other"


def length_of(case):
    n = len(case["say"].split())
    return "short" if n <= 12 else "medium" if n <= 40 else "long"
CONFIGS = ["app", "groq", "haiku"]


def load_jsonl(path):
    return [json.loads(l) for l in Path(path).read_text().splitlines() if l.strip()]


# ---------- build ----------

def validate(case):
    problems = [f"missing {f}" for f in FIELDS if f not in case]
    if case.get("format") not in FORMATS:
        problems.append(f"format {case.get('format')!r}")
    if case.get("category") not in CATEGORIES:
        problems.append(f"category {case.get('category')!r}")
    if case.get("difficulty", "easy") not in DIFFICULTY:
        problems.append(f"difficulty {case.get('difficulty')!r}")
    if case.get("polarity") not in ("positive", "negative"):
        problems.append(f"polarity {case.get('polarity')!r}")
    for f in ("must", "must_not"):
        if not isinstance(case.get(f), list):
            problems.append(f"{f} not a list")
    # A required phrase that's also forbidden can never pass.
    clash = {m.lower() for m in case.get("must", [])} & {m.lower() for m in case.get("must_not", [])}
    if clash:
        problems.append(f"must and must_not share {sorted(clash)}")
    return problems


def cmd_build(args):
    cases, seen_ids, bad = [], set(), 0
    for part in sorted((DATA / "parts").glob("*.jsonl")) + sorted((DATA / "parts2").glob("*.jsonl")):
        for c in load_jsonl(part):
            problems = validate(c)
            if c.get("id") in seen_ids:
                problems.append("duplicate id")
            if c.get("drop"):
                problems.append(f"dropped in audit: {c['drop']}")
            if problems:
                bad += 1
                print(f"skip {part.name} {c.get('id')}: {'; '.join(problems)}")
                continue
            seen_ids.add(c["id"])
            c.setdefault("difficulty", "unrated")
            c["length"], c["app_group"] = length_of(c), app_group(c)
            cases.append(c)
    # Stratified 40/30/30 split by category, polarity and difficulty, in a fixed pseudo-random order.
    # Cases read while debugging go to train/dev only, so the held-out test set stays unseen.
    seen = set(json.loads(SEEN.read_text())) if SEEN.exists() else set()
    groups = collections.defaultdict(list)
    for c in cases:
        groups[(c["category"], c["polarity"], c["difficulty"])].append(c)
    for group in groups.values():
        group.sort(key=lambda c: hashlib.sha1(c["id"].encode()).hexdigest())
        n_test = round(len(group) * 0.3)
        for c in [c for c in group if c["id"] not in seen][:n_test]:
            c["split"] = "test"
        rest = [c for c in group if "split" not in c]
        n_train = round(len(group) * 0.4)
        for i, c in enumerate(rest):
            c["split"] = "train" if i < n_train else "dev"
    cases.sort(key=lambda c: c["id"])
    CASES.write_text("".join(json.dumps(c, ensure_ascii=False) + "\n" for c in cases))
    print(f"{len(cases)} cases ({bad} skipped) -> {CASES}")
    for key in ("split", "category", "polarity", "difficulty", "length", "app_group"):
        print(f"  {key:11} " + "  ".join(f"{k}={v}" for k, v in sorted(collections.Counter(c[key] for c in cases).items())))
    leaked = [c["id"] for c in cases if c["split"] == "test" and c["id"] in seen]
    assert not leaked, leaked


# ---------- run ----------

def load_keys():
    env = {}
    if KEYS.exists():
        for line in KEYS.read_text().splitlines():
            m = re.match(r"\s*([A-Z_]+)\s*=\s*(.+?)\s*$", line)
            if m:
                env[m.group(1)] = m.group(2).strip("\"'")
    return env


def run_path(name, config):
    return RESULTS / f"{name}-{config}.jsonl"


def cmd_run(args):
    cases = [c for c in load_jsonl(CASES) if args.split == "all" or c["split"] == args.split]
    if args.only:
        cases = [c for c in cases if c["id"] in set(args.only.split(","))]
    RESULTS.mkdir(parents=True, exist_ok=True)
    inp = RESULTS / f".in-{args.name}-{args.config}.jsonl"
    inp.write_text("".join(json.dumps({k: c[k] for k in ("id", "say", "bundle", "title", "app")}) + "\n" for c in cases))
    out = run_path(args.name, args.config)
    env = {**os.environ, **load_keys(), "ALOUD_BEHAVIOR_IN": str(inp), "ALOUD_BEHAVIOR_OUT": str(out),
           "ALOUD_BEHAVIOR_CHAIN": args.config, "ALOUD_BEHAVIOR_PAR": str(args.par),
           "ALOUD_BEHAVIOR_FIXUPS": "0" if args.no_fixups else "1",
           "ALOUD_BEHAVIOR_MARKERS": "1" if args.markers else "0",
           "ALOUD_BEHAVIOR_REPAIR": "0" if args.no_repair else "1",
           "ALOUD_BEHAVIOR_GROQ_EFFORT": args.groq_effort}
    print(f"running {len(cases)} cases ({args.split}) with {args.config} -> {out.name}", flush=True)
    r = subprocess.run(["swift", "test", "--filter", "BehaviorReplay"], cwd=args.app_dir or APP, env=env,
                       capture_output=True, text=True)
    if r.returncode != 0 or not out.exists():
        print(r.stdout[-3000:], r.stderr[-2000:])
        sys.exit("run failed")
    inp.unlink()
    print(f"done: {len(load_jsonl(out))} outputs")


# ---------- score ----------

def has_phrase(text, phrase):
    """Case-insensitive; plain words match whole words only, a trailing plural still counts."""
    # "noise-cancelling" and "noise cancelling" are the same words.
    def norm(x, words_hyphen):
        x = x.lower().replace("`", "").replace("\u2019", "'").replace("\u2018", "'")  # code form, curly quotes
        x = re.sub(r"(\d):00\b", r"\1", x)                  # "5:00" and "5" are the same time
        for full, short in (("do not", "don't"), ("does not", "doesn't"), ("did not", "didn't"), ("can not", "can't"),
                            ("cannot", "can't"), ("will not", "won't"), ("is not", "isn't"), ("are not", "aren't")):
            x = re.sub(r"\b" + full + r"\b", short, x)          # "Do not" and "don't" are the same words
        if words_hyphen:                                       # "noise-cancelling" matches "noise cancelling",
            x = re.sub(r"(?<=[a-z])-(?=[a-z])", " ", x)       # but flags ("-f") and "docker-compose" stay literal
        return re.sub(r"(?<=\w)[,;:](?=\s)", "", x)           # "yeah, nah" matches "yeah nah"
    hyphen_free = "-" not in phrase
    low, p = norm(text, hyphen_free), norm(phrase, hyphen_free)
    if re.fullmatch(r"[\w' ]+", p):
        return re.search(r"(?<![\w'])" + re.escape(p) + r"(?:s|es|'s)?(?![\w'])", low) is not None
    return p in low


LABEL = re.compile(r"(?im)^(goal|tasks|context|constraints|done when):")


def layout_ok(fmt, typed):
    t = typed.strip()
    lines = [l.strip() for l in t.splitlines() if l.strip()]
    bullets = [l for l in lines if re.match(r"^([-*•]|\d+[.)])\s", l)]
    if fmt == "prompt":
        return t.lower().startswith("goal:")
    if fmt == "list":
        return len(bullets) >= 2
    if fmt == "paragraph":
        return not bullets and not LABEL.search(t)
    if fmt == "email":
        return len(lines) >= 2 and not LABEL.search(t)  # greeting / body / sign-off on their own lines
    if fmt == "single_line":
        return "\n" not in t and (not t.endswith(".") or t.endswith(".."))  # "cd ../.." is a command
    return True


def score(case, row):
    typed = row.get("typed", "")
    reasons = []
    if not layout_ok(case["format"], typed):
        reasons.append(f"layout≠{case['format']}")
    reasons += [f"missing '{m}'" for m in case["must"] if not has_phrase(typed, m)]
    reasons += [f"has '{m}'" for m in case["must_not"] if has_phrase(typed, m)]
    return reasons


def evaluate(name, config, split):
    cases = {c["id"]: c for c in load_jsonl(CASES) if split == "all" or c["split"] == split}
    path = run_path(name, config)
    if not path.exists():
        return None
    rows = {r["id"]: r for r in load_jsonl(path)}
    return [(cases[i], rows[i], score(cases[i], rows[i])) for i in cases if i in rows]


def rates(results):
    by = collections.defaultdict(lambda: [0, 0])
    for case, _, reasons in results:
        keys = [("all",), (case["category"],), (case["category"], case["polarity"]), ("polarity", case["polarity"]),
                ("difficulty", case.get("difficulty", "unrated")), ("length", case.get("length", "")),
                ("app", case.get("app_group", "")), ("difficulty+polarity", f"{case.get('difficulty')} {case['polarity']}")]
        for key in keys:
            by[key][0] += not reasons
            by[key][1] += 1
    return by


def pct(p):
    return f"{100 * p[0] / p[1]:.0f}% ({p[0]}/{p[1]})" if p and p[1] else "–"


def cmd_report(args):
    md = [f"# Behavior eval: {args.name} ({args.split})", ""]
    configs = [c for c in CONFIGS if run_path(args.name, c).exists()]
    now = {c: evaluate(args.name, c, args.split) for c in configs}
    before = {c: evaluate(args.against, c, args.split) for c in configs} if args.against else {}
    cats = sorted({r[0]["category"] for res in now.values() for r in res})
    keys = [("all",)] + [k for cat in cats for k in [(cat,), (cat, "positive"), (cat, "negative")]]
    extra = sorted({k for c in configs for k in rates(now[c]) if k[0] in ("polarity", "difficulty", "length", "app", "difficulty+polarity")})
    keys += extra
    head = "| | " + " | ".join(f"{c}" + (f" (was)" if before.get(c) else "") for c in configs) + " |"
    md += [head, "|---|" + "---|" * len(configs)]
    rn = {c: rates(now[c]) for c in configs}
    rb = {c: rates(before[c]) for c in configs if before.get(c)}
    for k in keys:
        label = k[0] if len(k) == 1 else (f"&nbsp;&nbsp;{k[1]}" if k[0] in CATEGORIES else f"{k[0]}: {k[1]}")
        cells = []
        for c in configs:
            cell = pct(rn[c].get(k))
            if c in rb:
                cell += f" (was {pct(rb[c].get(k)).split(' ')[0]})"
            cells.append(cell)
        md.append(f"| {label} | " + " | ".join(cells) + " |")
    lat = {c: sorted(r[1].get("ms", 0) for r in now[c]) for c in configs}
    md += ["", "Latency p50 / p95 (ms): " + ", ".join(
        f"{c} {lat[c][len(lat[c]) // 2]} / {lat[c][int(len(lat[c]) * .95) - 1]}" for c in configs if lat[c])]
    if args.split != "test" or args.show_test:
        for c in configs:
            fails = [r for r in now[c] if r[2]]
            md += ["", f"## Failures: {c} ({len(fails)})", ""]
            for case, row, reasons in fails:
                md.append(f"- **{case['id']}** ({case['polarity']}, {case['app']}): {'; '.join(reasons)}  ")
                md.append(f"  said: `{case['say']}`  ")
                md.append(f"  typed: `{row.get('typed', '').replace(chr(10), ' ⏎ ')}`  ")
                md.append(f"  via {row.get('via')} · {'; '.join(n for n in row.get('notes', []) if 'mode=' not in n)}")
    summary = {c: {"/".join(k): {"pass": v[0], "total": v[1]} for k, v in rn[c].items()} for c in configs}
    for c in configs:
        summary[c]["latency_ms"] = {"p50": lat[c][len(lat[c]) // 2], "p95": lat[c][int(len(lat[c]) * .95) - 1]} if lat[c] else {}
    (HERE / "results" / f"behavior-{args.name}-{args.split}.json").write_text(json.dumps(summary, indent=1, sort_keys=True))
    text = "\n".join(md) + "\n"
    out = HERE / "results" / f"behavior-{args.name}-{args.split}.md"
    out.write_text(text)
    print(text if args.verbose else "\n".join(md[:len(keys) + 6]))
    print(f"-> {out}")


def cmd_publish(args):
    """The published report: baseline vs final on the held-out test split, by every breakdown."""
    cases = load_jsonl(CASES)
    base, final = args.baseline, args.final
    def table(split, rows_keys, title):
        out = [f"### {title}", "", "| | " + " | ".join(f"{c} baseline | {c} final" for c in CONFIGS) + " |",
               "|---|" + "---:|---:|" * len(CONFIGS)]
        rb = {c: rates(evaluate(base, c, split) or []) for c in CONFIGS}
        rf = {c: rates(evaluate(final, c, split) or []) for c in CONFIGS}
        for k in rows_keys:
            if not any(rf[c].get(k) for c in CONFIGS):
                continue
            label = k[0] if len(k) == 1 else (f"&nbsp;&nbsp;{k[1]}" if k[0] in CATEGORIES else f"{k[1]}")
            out.append(f"| {label} | " + " | ".join(f"{pct(rb[c].get(k))} | **{pct(rf[c].get(k))}**" for c in CONFIGS) + " |")
        return out + [""]
    cats = sorted(CATEGORIES)
    cat_keys = [("all",)] + [k for c in cats for k in [(c,), (c, "positive"), (c, "negative")]]
    other = lambda dim, vals: [(dim, v) for v in vals]
    md = ["# Behavior evals: baseline vs final", ""]
    rt = {c: rates(evaluate(final, c, "test")) for c in CONFIGS}
    rbt = {c: rates(evaluate(base, c, "test")) for c in CONFIGS}
    md += ["**Held-out test split** (" + str(sum(c['split'] == 'test' for c in cases)) + " cases never used for tuning): "
           + ", ".join(f"{c} {pct(rbt[c][('all',)]).split(' ')[0]} → **{pct(rt[c][('all',)]).split(' ')[0]}**" for c in CONFIGS)
           + ". `app` is what ships: Groq (gpt-oss-120b) first, Claude Haiku as fallback, with the app's timeouts.", ""]
    md += ["## What is measured", "",
           "Each case is a realistic speech-to-text transcript dictated into a specific app, labelled with what Aloud's "
           "cleanup must do there (`positive`: a transformation should happen, e.g. lay out a prompt, make a list, apply "
           "a self-correction, repair a misheard word) or must not do (`negative`: a look-alike that must be left alone). "
           "A case passes when the output has the expected layout, keeps every required phrase and contains no forbidden "
           "one. Spec and schema: [`behavior/SPEC.md`](../behavior/SPEC.md).", "",
           "- **Dataset:** " + f"{len(cases)} cases, written per app group by separate agents from a shared spec, then "
           "audited case by case by three more agents (label fixes are recorded in each case's `audit` field; 5 ambiguous "
           "cases were dropped).",
           "- **Splits (40/30/30, stratified by category, polarity and difficulty):** `train` is the prompt-construction "
           "set (its failures were read and few-shot examples come from it); `dev` chose between prompt variants and "
           "settings (scores only); `test` was scored for the baseline and once at the end. Cases read while debugging "
           "before this eval are never in `test`.",
           "- **Setups:** `app` (the shipped chain), `groq` and `haiku` (each model alone, 8 s timeout).",
           "- **Baseline:** the last pushed version before this work (commit `22bf7db`), run on the same cases with the same scorer.",
           "- **Noise:** a repeat run of the same build moves a split's overall score by about ±1–2 points.", ""]
    comp = collections.Counter((c["category"], c["polarity"], c["difficulty"]) for c in cases)
    md += ["## Dataset", "", "| category | positive easy | positive hard | negative easy | negative hard | total |", "|---|---:|---:|---:|---:|---:|"]
    for cat in cats:
        row = [comp[(cat, p, d)] for p in ("positive", "negative") for d in ("easy", "hard")]
        md.append(f"| {cat} | " + " | ".join(map(str, row)) + f" | {sum(row)} |")
    for dim in ("split", "length", "app_group"):
        md.append("")
        md.append(f"**By {dim}:** " + ", ".join(f"{k} {v}" for k, v in sorted(collections.Counter(c[dim] for c in cases).items())))
    md += ["", "## Results on the held-out test split", ""]
    md += table("test", cat_keys, "By category and polarity")
    md += table("test", other("polarity", ["positive", "negative"]) + other("difficulty", ["easy", "hard"])
                + other("difficulty+polarity", ["easy positive", "easy negative", "hard positive", "hard negative"])
                + other("length", ["short", "medium", "long"]), "By polarity, difficulty and length")
    md += table("test", other("app", ["claude_code", "codex", "editor", "terminal", "ai_apps", "chat_apps", "email_apps", "notes", "todo"]),
                "By app group")
    md += ["### Latency (test split, ms)", "", "| | p50 baseline | p50 final | p95 baseline | p95 final |", "|---|---:|---:|---:|---:|"]
    for c in CONFIGS:
        lb = sorted(r[1].get("ms", 0) for r in evaluate(base, c, "test")); lf = sorted(r[1].get("ms", 0) for r in evaluate(final, c, "test"))
        q = lambda l, f: l[min(len(l) - 1, int(len(l) * f))]
        md.append(f"| {c} | {q(lb, .5)} | {q(lf, .5)} | {q(lb, .95)} | {q(lf, .95)} |")
    if args.repeat:
        r2 = rates(evaluate(args.repeat, "app", "test"))
        md += ["", f"A second run of the final build on the test split (`app`): {pct(r2[('all',)])}."]
    md += ["", "## Train and dev (for completeness)", "", "| split | " + " | ".join(f"{c} baseline | {c} final" for c in CONFIGS) + " |",
           "|---|" + "---:|---:|" * len(CONFIGS)]
    for sp in ("train", "dev"):
        md.append(f"| {sp} | " + " | ".join(f"{pct(rates(evaluate(base, c, sp))[('all',)])} | **{pct(rates(evaluate(final, c, sp))[('all',)])}**" for c in CONFIGS) + " |")
    log = json.loads((DATA / "experiments.json").read_text())
    md += ["", "## How the gains were made (tuning log, dev split, `app` setup)", "", "| step | change | dev | decision |", "|---|---|---|---|"]
    md += [f"| {e['id']} | {e['change']} | {e['dev_app']} | {e['decision']} |" for e in log]
    md += ["", "## Limits", "",
           "- Transcripts are written to look like ElevenLabs Scribe output; they are not recordings. Recognition errors on "
           "real audio are measured separately (`scenario_eval.py replay`, BENCHMARKS.md).",
           "- The cases and their audit were written by language models from a shared spec; labels are checked automatically "
           "and by a second model, not by people.",
           "- Each score is from one run; per-category test sets are 6–40 cases, so a single case can move a cell by several points.", "",
           "## Reproduce", "", "```", "cd bench", "python3 behavior_eval.py build",
           "python3 behavior_eval.py run --name final --config app --split all     # also --config groq / haiku",
           "python3 behavior_eval.py publish --baseline baseline --final final",
           "```", ""]
    out = HERE / "results" / "BEHAVIOR.md"
    out.write_text("\n".join(md))
    summary = {"test": {c: {"baseline": rbt[c][("all",)], "final": rt[c][("all",)]} for c in CONFIGS},
               "cases": len(cases), "splits": dict(collections.Counter(c["split"] for c in cases))}
    (HERE / "results" / "behavior-summary.json").write_text(json.dumps(summary, indent=1))
    print(f"-> {out}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("build")
    r = sub.add_parser("run")
    r.add_argument("--name", required=True)
    r.add_argument("--config", choices=CONFIGS, default="app")
    r.add_argument("--split", choices=SPLITS + ["all"], default="dev")
    r.add_argument("--only", help="comma-separated case ids")
    r.add_argument("--par", type=int, default=3)
    r.add_argument("--no-fixups", action="store_true", help="turn off the rule-based fix-ups after the model")
    r.add_argument("--app-dir", help="another checkout's app/ folder (e.g. the baseline commit)")
    r.add_argument("--markers", action="store_true", help="also loosen the checks on correction cue words (old behaviour)")
    r.add_argument("--no-repair", action="store_true", help="no misheard-word repair pass")
    r.add_argument("--groq-effort", default="low", help="Groq reasoning effort")
    p = sub.add_parser("report")
    p.add_argument("--name", required=True)
    p.add_argument("--against")
    p.add_argument("--split", choices=SPLITS + ["all"], default="dev")
    p.add_argument("--show-test", action="store_true", help="list test-set failures too (only at the very end)")
    p.add_argument("--verbose", action="store_true")
    q = sub.add_parser("publish")
    q.add_argument("--baseline", default="baseline")
    q.add_argument("--final", default="final")
    q.add_argument("--repeat", help="a second final run on the test split (app), to show run-to-run noise")
    args = ap.parse_args()
    {"build": cmd_build, "run": cmd_run, "report": cmd_report, "publish": cmd_publish}[args.cmd](args)


if __name__ == "__main__":
    main()
