# D. Developer and ML-Engineer Voice Workflows for agentd

*Research date: 2026-10-31. Scope: extending InstructFlow's `agentd` (Node 22 / TypeScript, typed `ToolContract`s with declared Effects, click-approval cards in the HUD/AgentPanel) into a voice control surface for coding agents, dev tooling, and ML infrastructure. Dictation, STT, cleanup, and macOS integration are covered elsewhere in `research/` and are not repeated here.*

---

## 0. TL;DR: design positions

1. **Use the Claude Agent SDK as the main coding-agent backend, not the `claude -p` subprocess.** `agentd` already runs on Node/TS. The SDK's `canUseTool` callback maps directly onto agentd's approval cards, `setPermissionMode()` can loosen permissions mid-session ("ok, accept edits from now on"), and the stream carries `session_id`, cost, and subagent messages tagged with `parent_tool_use_id`. Keep `claude -p --output-format stream-json` as the fallback and for the current `claude_code_task` tool. Put Codex behind the same interface through `@openai/codex-sdk`, and Cursor through its Cloud Agents REST API.
2. **"Voice fleet control" is the clearest gap in the market.** Conductor, crystl, Claude Squad, Vibe Kanban, Superset, Nimbalyst, and Sculptor all run parallel agents in git worktrees with a GUI or TUI. None of them has voice control or spoken status. Claude Code's own `/voice` (rolled out from March 2026) dictates into one session. It does not manage a fleet. A hold-to-talk "status?" that returns a 2-sentence spoken summary across 4 agents, with diffs and approvals on the HUD, is a feature nobody ships today.
3. **Speak the verdict and show the evidence.** Speech carries ≤2 sentences: counts, states, one blocker, one question. The HUD carries everything you scan visually: diffs, logs, tables, loss curves, commands. Never read code, hashes, paths, or log lines aloud.
4. **The effect model needs three additions** for developer and ML workflows (§4): `read_remote` (authenticated API reads: auto, but audited and rate-limited), `spend_compute` (paid GPU jobs: confirm with a budget cap, rather than the blocked `spend_money`), and `vcs_publish` (push, open PR, merge: always click-confirm, never voice-confirm for merges to the default branch).
5. **Ambient features carry the most value per unit of effort.** Examples: the CI watcher that speaks once when your PR goes red, the "agent 3 is waiting on you" nudge from Claude Code's `Notification` hook, the training-run watcher that catches a NaN loss, and "what was I doing in this repo?". These are mostly read-only, so they can run without approvals.

---

## 1. Orchestrating coding agents by voice

### 1.1 Backend capability matrix

| Capability | Claude Code headless (`claude -p`) | Claude Agent SDK (TS/Py) | Codex CLI `codex exec` / Codex SDK | Cursor Cloud Agents API |
|---|---|---|---|---|
| Start a task | `claude -p "<task>"` | `query({prompt, options})` | `codex exec "<task>"` / `codex.startThread().run()` | `POST /v1/agents` with `prompt.text`, `repos[]` |
| Streaming events | `--output-format stream-json --verbose --include-partial-messages`; last line is a `result` message with cost and session metadata | Async iterator of typed messages | `--json` emits JSONL: `thread.started`, `turn.started`, `item.started/updated/completed`, `turn.completed` (with `usage`), `turn.failed`, `error`. Item types include `agent_message`, `command_execution`, `file_change`, `mcp_tool_call`, `plan_update` | Poll status (`ACTIVE`; runs go `CREATING`→…). Webhooks exist in v0 and are "coming soon" in v1 |
| Structured final output | `--output-format json --json-schema '<schema>'` returns `structured_output` | `outputFormat`/schema option | `--output-schema PATH`; `-o/--output-last-message PATH` | n/a |
| Resume / follow-up | `--continue`, `--resume <session_id>` (works across directories) | `resume` option | `codex exec resume --last` / `resume <id>`; SDK `resumeThread(id)` | Follow-up endpoint (via MCP wrapper `cursor_add_followup`) |
| Permissions | `--permission-mode` (`default`/Manual, `acceptEdits`, `auto` classifier, `dontAsk`, `plan`, `bypassPermissions`), `--allowedTools "Bash(git diff *)"`, `--permission-prompt-tool`, `--permission-prompts none` for unattended runs | Same modes, plus a `canUseTool` callback and `setPermissionMode()` mid-stream. Evaluation order: hooks → deny → ask → mode → allow → `canUseTool` | `--sandbox read-only / workspace-write / danger-full-access`; `--full-auto` = workspace-write + on-request approvals; SDK `approvalPolicy` | Runs in Cursor's cloud VM. `mode: agent | plan`, `autoCreatePR` |
| Isolation | `--worktree <name>` / `-w` creates `.claude/worktrees/<name>/` on branch `worktree-<name>`. `-p` skips the trust check and **does not auto-clean** | Subagent `isolation: worktree` | You create worktrees yourself (`git worktree add`) | Branch per agent in the cloud |
| Hooks | Full hook system: `Notification` (matchers `permission_prompt`, `idle_prompt`), `Stop`, `SubagentStop`, `PermissionRequest`, `PreToolUse`, `SessionEnd`, `WorktreeCreate`…; `"type":"http"` hooks POST to a URL | Programmatic hooks | — | — |
| Cost tracking | `total_cost_usd` + per-model breakdown in the JSON result | Same | `usage` on `turn.completed` | Credit pool |
| Startup hygiene | `--bare` skips CLAUDE.md, hooks, MCP, and skills auto-discovery. Recommended for scripts and slated to become the `-p` default | `settingSources` | `--skip-git-repo-check` | — |

Sources: Claude Code headless docs, Agent SDK permissions docs, Claude Code worktrees docs, Claude Code hooks reference, Codex exec JSONL reference, Codex TS SDK article, Cursor Cloud Agents endpoints.

**Security note for agentd.** The headless docs warn that a non-`--bare` `-p` run "runs the hooks in a project's `.claude/settings.json` and connects the servers in its `.mcp.json`, even in a folder you've never trusted". There is no trust dialog. agentd should launch fleet agents with `--bare` (or SDK `settingSources` set explicitly) for repos outside a user-approved list. Without that, a cloned repo can execute hooks under the user's identity.

### 1.2 Recommended architecture: `FleetManager` inside agentd

```
HUD/AgentPanel (Swift) ⇄ JSON-RPC ⇄ agentd
                                     ├─ FleetManager
                                     │    ├─ ClaudeBackend   (Agent SDK query(), canUseTool → approval card)
                                     │    ├─ CodexBackend    (@openai/codex-sdk runStreamed)
                                     │    └─ CursorBackend   (REST /v1/agents, poll)
                                     ├─ WorktreeService      (git worktree add/list/remove, .worktreeinclude)
                                     ├─ HookReceiver         (localhost HTTP: Notification/Stop/PermissionRequest from
                                     │                        user-launched interactive claude sessions too)
                                     ├─ Summarizer           (cheap model: events → {state, 1-line, blocker, question})
                                     └─ AuditLog (JSONL, existing)
```

Normalized agent record (one per agent):

```ts
type FleetAgent = {
  id: string; nickname: string;          // "alpha", "bravo"... or a 2-word name: easy to say, easy for STT
  backend: "claude" | "codex" | "cursor";
  repo: string; worktree: string; branch: string;
  task: string;
  state: "starting" | "working" | "waiting_approval" | "waiting_input" | "idle_done" | "failed" | "merged";
  lastEvents: RingBuffer<NormalizedEvent>;   // tool calls, file changes, test runs
  pendingApproval?: { tool: string; summary: string; diffRef?: string };
  diffStat?: { files: number; plus: number; minus: number };
  testsLastRun?: { passed: number; failed: number; at: string };
  costUsd: number; startedAt: string; sessionId: string;
};
```

Key mappings:
- **Approvals.** The SDK `canUseTool(toolName, input)` resolves a promise that agentd holds open while it shows an approval card ("bravo wants to run `npm install zod`"). The existing 2-minute timeout should become a **deny-and-tell-agent** outcome, not a hang. The SDK docs warn that tools pre-approved by bare-name `allowedTools` never reach `canUseTool`. Use scoped rules like `Bash(npm test *)` so the checks you care about still run.
- **Mode escalation by voice.** "Bravo, accept edits" calls `setPermissionMode("acceptEdits")`. That loosens file edits only, inside the worktree, and agentd logs it. Never allow `bypassPermissions` by voice. Block it outright.
- **Interactive sessions the user started by hand** can join the fleet through Claude Code HTTP hooks (`Notification`, `Stop`, `PermissionRequest`) pointed at `http://localhost:<agentd>/hooks/...`. agentd then sees "waiting for permission" and "idle" events even for terminals it didn't spawn.

### 1.3 Worktree service

- Create: `claude -p --worktree <nick>` (or the SDK in a `git worktree add .claude/worktrees/<nick> -b fleet/<nick>` directory). Copy `.env` through `.worktreeinclude`. Set `worktree.baseRef: "head"` when the agents should build on in-progress local work.
- Environment bootstrap per worktree: detect `uv.lock` / `package-lock.json` / `pnpm-lock.yaml` and run the install as an `execute_process` step with click approval, or pre-approve it per repo.
- Cleanup: `-p` runs leave worktrees and locks in place. agentd should own cleanup. After a merge it runs `git worktree remove` and deletes the branch, and offers a voice "clean up merged agents" that runs as a single confirm card listing every directory to delete. `delete_local` is BLOCKED today, so add a narrow exception for paths under `.claude/worktrees/` whose branch is merged.
- Port collisions: dev servers in parallel worktrees fight over ports. Inject `PORT=$((3000+i))` per agent.

### 1.4 The "voice fleet control" interaction design

| Voice phrase (examples) | Action | Effect level | Spoken reply | HUD |
|---|---|---|---|---|
| "Spin up three agents on the eval repo: one adds retry logic to the judge client, one writes tests for the scorer, one updates the README." | Parse into N tasks → create N worktrees → start N sessions in `default` mode | CONFIRM once (one card lists the 3 tasks, repo, backend, budget cap) | "Starting three agents: alpha, bravo, charlie." | Fleet strip: 3 tiles with nickname, task, state dot |
| "Status?" / "How's the fleet?" | Summarizer over each agent's ring buffer | AUTO (read) | "Alpha's done, tests passing. Bravo is waiting for you to approve an npm install. Charlie is still writing." | Tiles update; the waiting tile pulses |
| "What's bravo stuck on?" | Show pending approval | AUTO | "It wants to install zod to validate the config." | Approval card with exact command |
| "Approve." / "Deny, use pydantic instead." | Resolve `canUseTool`; deny with message → agent gets the reason | Voice approval allowed for `execute_process` **in a worktree only**; click for anything else | "Approved." | Card closes |
| "Show me alpha's diff." | `git diff main...fleet/alpha` | AUTO | "Four files, plus 120, minus 30. The main change is in judge_client.py." | Side-by-side diff viewer, file list |
| "Tell alpha to add a jitter to the backoff." | Follow-up message to session (`resume`) | AUTO (agent's own tool calls still gated) | "Sent." | Tile goes back to working |
| "Run the tests on alpha." | `execute_process` in alpha's worktree | CONFIRM (or pre-approved `pytest` rule) | "Tests: 48 passed, 2 failed in test_scorer." | Test output, failing tests highlighted |
| "Merge alpha." | Rebase check → open PR (`gh pr create`) or local merge | `vcs_publish`: CLICK-CONFIRM only | "Opened PR 412. CI is running; I'll tell you when it's done." | PR card with link; CI watcher armed (§5) |
| "Kill charlie." | SDK `interrupt()` then close (SIGINT, not SIGTERM: SIGTERM leaves the turn unrecorded) | AUTO (stopping is safe) | "Charlie stopped. Its worktree is kept." | Tile greyed |
| "Pause everything." | Kill switch (existing) applied to the fleet | AUTO | "All agents paused." | Red banner |
| "Which one's cheapest so far?" / "What have I spent?" | Sum `total_cost_usd` | AUTO | "Three dollars ten across the fleet; bravo is two of that." | Cost column |

**Summarizer contract.** A small model (Haiku-class) turns event deltas into `{state, one_line, blocker?, question?}` per agent. agentd then builds the spoken sentence from a template with a priority ordering: *waiting on you* > *failed* > *done* > *working*. That way the most actionable item is always said first and the sentence never grows past ~25 words. Budget about 300 ms. Precompute the summary on every `Stop`/`Notification` event so "status?" is answered from cache with no LLM in the hot path.

**Reliable addressing.** Nicknames should be acoustically distinct (NATO alphabet, or pick from a list that STT reliably transcribes). Add them to the STT custom vocabulary or keyterms. Ordinals ("the second one") and anaphora ("approve it") should resolve to the most recently mentioned or most recently waiting agent. Read the resolution back ("Approving bravo") before acting.

**Concurrency limits.** The Claude Code docs note that a `-p` run can stay alive up to 10 minutes waiting for background work. Each agent also burns tokens. Set a fleet cap (default 4) and a per-agent `--max-budget-usd`.

### 1.5 Competitors and what voice adds

| Tool | Isolation | Agents supported | Review/merge | Notifications | Voice |
|---|---|---|---|---|---|
| Conductor (macOS) | worktree per workspace | Claude Code, Codex, Cursor | diff viewer + PR flow in one window | — | none |
| crystl (macOS) | opt-in worktree | any CLI agent; agents can spawn workers | activity panel of files touched | approval prompts and questions in one place | none |
| Claude Squad (tmux TUI, works over SSH) | worktree | Claude Code, Codex, Gemini, OpenCode, Amp, Aider | manual | — | none |
| Vibe Kanban (web UI) | worktree | 10+ CLI agents | diffs next to kanban board | — | none; **shut down April 2026, no commits since 24 Apr 2026** |
| Nimbalyst (formerly Crystal) | optional worktree | Claude Code, Codex, OpenCode, Copilot | desktop diff review + iOS app | mobile | none |
| Superset | worktree; desktop, CLI, **MCP server** | Claude Code, Codex, Cursor Agent, Amp, Gemini… | built-in diff | — | none |
| Sculptor (Imbue) | Docker container / worktree | Claude Code + Pi harness | agent tests, then you approve the pull into local | — | none |
| Cursor Cloud Agents | cloud VM, branch per agent | Cursor | auto-PR | Slack/Linear/GitHub triggers | none |
| Claude Code agent teams / `/voice` | worktree or none | Claude | lead summarizes workers | check from phone | `/voice` = dictation into one session |

Sources: crystl.dev 2026 roundup, Nimbalyst 2026 roundup, PCWorld on Claude Code voice mode.

**What voice adds that a GUI can't:**
1. **Eyes-free supervision.** You keep reading a paper or reviewing a PR in the browser and ask "status?" without switching windows. GUIs force a context switch, and that cost is exactly what parallel agents are supposed to remove.
2. **Interrupt-driven, not poll-driven.** The fleet speaks when it needs you ("bravo needs approval") instead of you scanning tiles.
3. **Steering in natural language at the moment of insight.** "Tell alpha to use exponential backoff" takes 2 seconds by voice and 20 seconds by click-into-terminal-and-type.
4. **Cross-tool composition.** A single utterance can span agent, git, CI, and calendar: "When alpha's PR is green, tell me, and if it's before my 3 pm, merge it." No orchestrator ships this because none of them see CI and calendar together.
5. **Integration path.** Superset exposes an MCP server. agentd could *drive* Superset or Conductor instead of reimplementing their UI, and act as the voice layer over the orchestrator a user already likes. Mount it as an MCP server once MCP mounting lands.

---

## 2. Developer workflows by voice

Legend: **Effect** uses agentd effects (§4 adds `read_remote`, `spend_compute`, `vcs_publish`). **AUTO** = no approval; **CONFIRM** = click card (voice "approve" allowed only where noted); **BLOCK** = never. Difficulty: S (≤1 day), M (2–5 days), L (1–2 weeks+).

### 2.1 Git and GitHub

| Voice phrase | Tools / APIs | Effect → level | Speak | HUD | Diff. |
|---|---|---|---|---|---|
| "What's the git status?" | `git status --porcelain=v2 -b` | read_local → AUTO | "On feature-retry, 3 modified, 1 untracked, 2 ahead of origin." | file list | S |
| "Commit this with a good message." | `git diff --staged` → LLM (Conventional Commits, repo's `git log` style as few-shot) → `git commit -F` | execute_process → CONFIRM (card shows message, editable) | "Proposed: 'fix(judge): retry on 429 with jittered backoff'. Commit?" | message + diffstat | S |
| "Stage everything except the notebook." | `git add -A && git restore --staged *.ipynb` | execute_process → CONFIRM (voice-approve OK) | "Staged 5 files." | staged list | S |
| "New branch for the tokenizer fix." | `git switch -c fix/tokenizer-…` | execute_process → CONFIRM | "Created fix/tokenizer-padding." | — | S |
| "Push and open a PR." | `git push -u` + `gh pr create --fill` (or LLM title/body from commits) | vcs_publish → CLICK | "PR 413 opened against main." | PR title/body preview before click | S |
| "What changed on main since yesterday?" | `git log origin/main --since=yesterday` + LLM digest | read_local → AUTO | "Six commits, mostly the eval refactor by Sam; one touches your scorer." | commit list | S |
| "Rebase on main." | `git fetch && git rebase origin/main` | execute_process → CONFIRM; on conflict, **hand off to a coding agent** | "Two conflicts in config.py. Want alpha to resolve them?" | conflict hunks | M |
| "Who wrote this function?" (cursor in editor) | `git blame -L` on focused file/line (window title + AX) | read_local → AUTO | "Sam, three weeks ago, in the 'add rubric' commit." | blame popover | M |

### 2.2 CI (GitHub Actions)

| Voice phrase | Tools / APIs | Effect → level | Speak | HUD | Diff. |
|---|---|---|---|---|---|
| "How's CI on my PR?" | `gh pr checks` / GitHub MCP Actions tools (`list_workflow_runs`, `get_workflow_run`) | read_remote → AUTO | "Four of five passed; lint failed." | checks table | S |
| "Why did it fail?" | `gh run view <id> --log-failed` / MCP `get_job_logs` → LLM extracts the first real error | read_remote → AUTO | "Ruff: unused import in scorer.py line 12." | trimmed failing log, error line highlighted | S |
| "Rerun the failed jobs." | `gh run rerun <id> --failed` / MCP `rerun_failed_jobs` | network_write → CONFIRM (voice-approve OK: idempotent, reversible) | "Rerunning lint." | run link | S |
| "Fix it." | Spawn a fleet agent in a worktree of the PR branch (`claude --worktree "#413"` fetches the PR head) with the log as context | spawns agent → CONFIRM | "Bravo is on it." | fleet tile | M |
| "Trigger the nightly eval workflow on this branch." | `gh workflow run eval.yml --ref <branch>` | network_write (+ spend_compute if GPU runners) → CONFIRM | "Triggered. About 40 minutes based on last runs." | run link | S |

Note: the GitHub MCP server has shipped Actions tools (`list_workflows`, `list_workflow_runs`, `get_job_logs`, `rerun_failed_jobs`, `run_workflow`, `cancel_workflow_run`, …; GitHub PR #491). Later releases group tools into toolsets, so check current names. **`gh` is simpler and already authenticated on most dev Macs**, so start with `gh … --json` through `run_shell` with an allowlist of `gh` subcommands, and move to MCP when mounting exists.

### 2.3 Code review

| Voice phrase | Tools / APIs | Effect → level | Speak | HUD | Diff. |
|---|---|---|---|---|---|
| "Summarize PR 410." | `gh pr view 410 --json title,body,files,reviews` + `gh pr diff` → LLM | read_remote → AUTO | "Sam's PR adds async batching to the judge; 6 files; the risky part is the shared session object." | per-file summary, risk flags | S |
| "Review it for bugs." | `gh pr diff \| claude -p --append-system-prompt "...review..." --output-format json` (pattern from the Claude Code docs) | read_remote + execute_process (read-only agent, `--permission-mode plan` or `dontAsk`) → AUTO | "Three findings; one likely race in the batcher." | findings list linked to lines | S |
| "Comment on line 88: this needs a lock." | `gh api` review comment, or `gh pr review --comment` | send_message → CLICK (shows exact text + location) | "Comment ready; confirm to post." | comment preview | M |
| "Approve the PR." | `gh pr review --approve` | vcs_publish → CLICK | — | — | S |

**Mentoring angle:** the owner mentors a junior engineer. "Draft review comments for Sam's PR that explain *why*" should produce teaching-style comments as a *draft*, never auto-posted.

### 2.4 Terminal, logs, containers, cloud, DB, tests, deps, docs

| Voice phrase | Tools / APIs | Effect → level | Speak | HUD | Diff. |
|---|---|---|---|---|---|
| "Explain that error." (terminal focused) | Read the last N lines of the focused terminal. iTerm2 Python API / Terminal.app AppleScript (`contents`/`history` of tab), or AX text value for Ghostty/WezTerm. Fallback: ask the user to select. | read_local → AUTO; **redact secrets** before the LLM | "CUDA OOM at batch 32: you're at 23 of 24 gigs. Halve the batch or turn on gradient checkpointing." | error + suggested fix command (click to insert, never auto-run) | M |
| "Run the failing tests." | `pytest --lf` / `npx vitest --changed`; detect runner from repo | execute_process → CONFIRM, or pre-approved per repo | "2 of 2 still failing; same assertion." | test output | S |
| "Tail the API logs and tell me if anything errors." | `docker logs -f <svc>` / `kubectl logs -f` piped into a watcher (§5) | execute_process (long-running) → CONFIRM once | (only on error) "Error spike: 12 500s in the last minute." | live log pane | M |
| "What containers are running?" | `docker ps --format json` | read_local → AUTO | "Four: postgres, redis, api, and the vllm server, up 3 hours." | table | S |
| "Restart the API container." | `docker restart api` | execute_process → CONFIRM | "Restarted." | — | S |
| "Any pods crashlooping in staging?" | kubernetes-mcp-server (talks to the K8s API directly, `read_only` config, toolsets) or `kubectl get pods -A` | read_remote → AUTO | "One: judge-worker, 7 restarts, OOMKilled." | pod table | M |
| "Scale judge-worker to 3." | MCP resources_scale / `kubectl scale` | network_write → CLICK | — | — | M |
| "What's my AWS spend this month?" / "List EC2 GPU instances." | AWS API MCP server (`call_aws`, `READ_OPERATIONS_ONLY=true`, `REQUIRE_MUTATION_CONSENT=true`). Note: superseded by the newer official AWS MCP server | read_remote → AUTO | "Three g5 instances running, one idle for 9 hours." | table | M |
| "How many eval rows failed yesterday?" | Read-only DB role; LLM writes SQL → **show SQL on HUD first** → run with `statement_timeout` | read_remote → CONFIRM SQL (reads, but generated code) | "214 of 5,000, mostly the tool-call category." | SQL + result table | M |
| "Bump transformers and see if tests pass." | Fleet agent in a worktree: `uv lock --upgrade-package transformers && pytest` | spawns agent → CONFIRM | "Upgraded to the latest; 3 tests break on tokenizer padding." | diff + test output | M |
| "How do I set gradient accumulation in TRL's SFTConfig?" | Context7 MCP (version-specific library docs), HF docs via HF MCP `hf_fs` docs search | read_remote → AUTO | 1–2 sentence answer | code snippet (click to insert) | S |

---

## 3. ML-engineer workflows by voice

### 3.1 API and MCP availability

| System | Official MCP | Programmatic API good enough for agentd | Notes |
|---|---|---|---|
| Hugging Face Hub | **Yes**: `https://huggingface.co/mcp`. Built-ins: `hf_fs` (Hub filesystem, search, docs), repo search and details, **Run and Manage Jobs**, Sandboxes, Contribute Repos, Dynamic Spaces (Gradio Spaces as tools) | `huggingface_hub`: `run_job`, `run_uv_job`, `inspect_job`, `fetch_job_logs`, `fetch_job_metrics` (incl. GPU), `cancel_job`, `wait_for_job`, scheduled jobs; CLI `hf jobs run/uv run/ls/wait/hardware/ssh` | Flavors such as `a10g-small` ($1/hr), `a100-large` ($2.50/hr), `h200`; default timeout 30 min |
| Weights & Biases | **Yes**: `https://mcp.withwandb.com/mcp` (hosted) or `uvx wandb-mcp-server`. Tools: `query_wandb_tool`, `query_weave_traces_tool`, `count_weave_traces_tool`, `create_wandb_report_tool`, `query_wandb_entity_projects`, `query_wandb_support_bot` | `wandb.Api().run(path).history()` / `scan_history()` / `.summary` | Weave traces matter for LLM eval work |
| MLflow | **Yes**: `mlflow mcp run` (`mlflow[mcp]>=3.5.1`). Documented tools cover traces and assessments (`search_traces`, `get_trace`, `log_feedback`…); `MLFLOW_MCP_TOOLS` names categories for experiments, runs, models | `MlflowClient().get_metric_history(run_id, key)` | Run-metrics coverage via MCP is unconfirmed, so use the Python client |
| TensorBoard | No | `tensorboard.backend.event_processing.EventAccumulator` over the logdir | Local/ssh only |
| RunPod | **Yes**: `runpod/runpod-mcp`, hosted with OAuth, or `npx @runpod/mcp-server`. Tools carry `readOnlyHint`/`destructiveHint` annotations (`pod-action`, `delete-pod` marked destructive, `list-gpu-types`, `list-billing`) | REST v2 | The annotations map directly onto agentd effects |
| Modal | Community only (`mcp-modal` on PyPI) | `modal app list`, `modal app logs`, `modal container list` CLI | Use the CLI with an allowlist |
| Lambda Cloud | Community MCP connectors | Cloud API: `listInstances`, `launchInstance`, `terminateInstance` | Launch → `spend_compute` |
| Bare GPU boxes | — | `ssh host nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader` | Needs an `ssh` allowlist entry per host |

### 3.2 Workflow table

| Voice phrase | Tools / APIs | Effect → level | Speak | HUD | Diff. |
|---|---|---|---|---|---|
| "Launch the SFT run on an A10G with the config in this repo." | `hf jobs uv run --flavor a10g-small --detach train.py` (or `run_uv_job(..., timeout="4h")`) | **spend_compute → CONFIRM** with card: flavor, $/hr, timeout, max cost | "Launch on a10g-small, 4-hour cap, at most four dollars?" → "Launched; job ID on screen." | job card, est. cost | M |
| "How's the loss on run X?" / "on the latest run?" | W&B MCP `query_wandb_tool` or `Api().run().history(keys=["train/loss","eval/loss"])`; MLflow `get_metric_history` | read_remote → AUTO | "Step 4,200: train loss 0.91, down from 1.4; eval loss flat for the last 800 steps, so it might be plateauing." | sparkline of train/eval loss + LR | M |
| "Compare it to yesterday's baseline." | Two runs' histories + summaries → LLM | read_remote → AUTO | "Eval loss 3% lower at the same step; throughput 12% slower." | overlay chart, config diff (only the hyperparams that differ) | M |
| "Is anything wrong with my training jobs?" | `inspect_job` + `fetch_job_logs` (grep `nan`, `OOM`, `Traceback`) + metrics | read_remote → AUTO | "Job 2 died 20 minutes ago with CUDA OOM; job 1 is healthy." | failing log excerpt | M |
| "Cancel job 2." | `cancel_job` / `hf jobs cancel` | network_write → CONFIRM (voice OK; stopping only saves money) | "Cancelled." | — | S |
| "How are the GPUs on the lab box?" | `ssh lab nvidia-smi --query-gpu=… --format=csv` | execute_process (allowlisted read) → AUTO | "All 4 at 95% utilization, 70 of 80 gigs; GPU 3 is at 84 degrees." | per-GPU table | S |
| "What's running on RunPod and what's it costing?" | RunPod MCP list pods + `list-billing` | read_remote → AUTO | "Two pods, one idle for 6 hours, burning about 1.80 an hour." | pod table | S |
| "Stop the idle pod." | RunPod `pod-action` stop | network_write → CONFIRM (voice OK) | — | — | S |
| "Show me 5 random rows from the eval dataset where the label is refusal." | `datasets.load_dataset(..., streaming=True)` filter, or HF dataset viewer API; HF MCP for Hub datasets | read_remote → AUTO | "Showing five. Two look mislabeled." | table view | M |
| "What's the token-length distribution of the train split?" | Script in sandbox (tokenizer + histogram) | execute_process → CONFIRM (or pre-approved analysis sandbox) | "Median 410 tokens, p99 3,900; 2% exceed your 4k max length." | histogram | M |
| "Run the evals on the new checkpoint and tell me what regressed." | Owner's bench harness / lm-eval / custom judge; diff vs stored baseline per slice | execute_process (+ spend_compute if remote) → CONFIRM | "Overall +1.2 points, but tool-call accuracy dropped 4 points on the multi-step slice." | per-slice delta table, red/green, worst examples | L |
| "Draft a model card for this checkpoint." | HF model card template + training config + W&B summary + eval table → LLM → `write_file README.md` | write_local → CONFIRM; pushing to the Hub = vcs_publish → CLICK | "Draft written; intended use and limitations need your review." | rendered card preview | M |
| "Run the notebook top to bottom and tell me where it breaks." | `jupyter nbconvert --to notebook --execute` or `papermill` | execute_process → CONFIRM | "Cell 14 fails: KeyError 'label'." | failing cell + traceback | M |
| "Benchmark latency for the 3B model at batch 1 and 8." | vLLM `benchmark_serving`/custom script; p50/p95 TTFT, tokens/s | execute_process / spend_compute → CONFIRM | "Batch 1: 38 ms TTFT p50, 112 tokens a second. Batch 8 triples throughput, p95 TTFT doubles." | table + percentiles | M |
| "Find me a small embedding model under 200M params that does well on retrieval." | HF MCP `hf_fs search hf://models …` + MTEB leaderboard Space | read_remote → AUTO | "Three candidates; on screen." | comparison table | S |

**ML-specific design rule: numbers need context to be speakable.** Raw "loss 0.9134 at step 4217" is useless by ear. The summarizer should always speak the **trend** (direction + magnitude over a window), **the comparison** (vs baseline or vs last check), and **the anomaly** (NaN, plateau, divergence between train and eval). Round to 2 significant figures.

---

## 4. Effect model: mapping and proposed additions

agentd today has: `read_local`, `launch_app`, `open_url`, `write_local`, `execute_process`, `network_write`, `send_message`, `delete_local`, `spend_money`, `system_settings`. Reads are auto. Write, execute, network_write, and send_message need a click. Delete, spend, and system settings are blocked.

| Proposed effect | Covers | Policy | Rationale |
|---|---|---|---|
| `read_remote` | Authenticated API reads: GitHub, W&B, HF, K8s get, AWS describe, DB SELECT | AUTO, audited, rate-limited. **Treat outputs as untrusted** (prompt injection via PR bodies, CI logs, issue comments) | Without it, every "status?" needs a click and voice becomes unusable. AWS's MCP docs warn not to connect to "untrusted data sources, such as user-generated content or raw logs". Run these outputs through a quarantine pass: no tool calls may be planned from raw remote text without user re-confirmation |
| `spend_compute` | Launching paid GPU jobs/pods/instances, triggering GPU CI | CONFIRM with **required budget fields** (flavor, $/hr, timeout, max $). Daily cap in settings; above cap → BLOCK | `spend_money` is blocked, which would block all training launches. Compute spend is bounded by a timeout and reversible by cancel, unlike purchases |
| `vcs_publish` | `git push`, `gh pr create`, PR approve/merge, Hub `push_to_hub` | CLICK-only, **never voice approval**; merge to default branch shows the final diffstat + CI status on the card | Publishing is the irreversible-ish boundary in dev work |
| (refine) `execute_process` scoped by **cwd** | Commands inside a fleet worktree | Voice approval allowed when cwd ⊂ `.claude/worktrees/*`; click elsewhere | Worktree isolation (Claude Code even blocks edits/git redirects into the main checkout) makes these lower-risk |
| (refine) `delete_local` exception | Removing merged worktrees | CONFIRM with explicit list | Needed for fleet hygiene |

**Voice-approval policy, consistent with CONTEXT.md ("voice approval never for send/spend/delete"):**
- Voice "approve" is OK for: `execute_process` in a worktree, `network_write` that is idempotent and reversible (rerun CI, cancel job, stop pod).
- Click only: `send_message` (PR comments), `vcs_publish`, `spend_compute`, anything touching the main checkout.
- Block: `bypassPermissions` mode for agents, `kubectl delete`, `terminateInstance` on instances not created by agentd, DB writes.

---

## 5. Background "ambient" developer features

These features run as watchers inside agentd (a scheduler plus event sources). Each produces at most one spoken sentence per event, and only through an **interruption policy**:
- Never speak while the mic is hot, during a calendar meeting (Google Calendar busy), or while screen-sharing. Show a HUD toast instead, and queue the speech for "what did I miss?".
- Coalesce events: one sentence for "2 PRs went green", not two.
- Severity tiers: *speak* (your PR red, training NaN, agent waiting > 2 min), *toast* (agent done, CI green), *digest only* (everything else).

| Feature | Trigger / sources | Effect | Output | Diff. |
|---|---|---|---|---|
| **CI watcher** | Armed automatically after "push"/"open PR", or "watch CI on 413". Poll `gh pr checks --json` with backoff (or GitHub webhooks via a relay later) | read_remote → AUTO | Red: "PR 413: unit tests failed in test_scorer. Want bravo to fix it?" Green: toast. Arms the follow-up ("fix it") | S |
| **Agent-needs-you nudge** | Claude Code `Notification` hook (`permission_prompt`, `idle_prompt`) and `Stop` via HTTP hook → agentd; fleet `canUseTool` pending > 90 s | AUTO | "Charlie's been waiting two minutes for approval." | S |
| **Training-run watcher** | Every 5 min: W&B/MLflow history + `inspect_job`; rules: NaN/inf loss, eval loss up for k evals, throughput drop > 30%, job state ERROR, GPU util < 20% for 15 min (wasted money) | read_remote → AUTO | "Run sft-v3 hit NaN loss at step 6,100. Cancel it?" (cancel = voice-approvable) | M |
| **Idle-compute sentinel** | RunPod/Lambda/HF Jobs/AWS listing; idle > N hours | read_remote → AUTO | "The 4090 pod has been idle 6 hours, about eleven dollars. Stop it?" | S |
| **Morning standup brief** ("brief me" or at first unlock after 8 am) | `git log --author=me --since=yesterday` across watched repos; open PRs + review requests (`gh search prs --review-requested=@me`); CI states; Linear MCP (assigned issues, cycle); Google Calendar (today's meetings); overnight training-run results | read_remote → AUTO | 30-second spoken brief: "Yesterday you merged the retry fix and opened the batching PR, which needs one more review. Two review requests from Sam. The overnight eval finished: plus one point overall. Meetings at 10 and 2." HUD: the full Yesterday/Today/Blockers draft, copyable into Slack | M |
| **End-of-day summary** ("wrap up") | Same sources + agentd audit log (what agents did) + uncommitted changes per repo + running jobs | read → AUTO; optional "post it" = send_message → CLICK | "You shipped 2 PRs, have uncommitted work in eval-harness, and one training job is still running; it'll finish around 11 pm." Offers: "Stash a WIP commit?" "Set a watcher?" | M |
| **"Remind me what I was doing in this repo"** | Focused repo (window title/cwd) → branch name, `git reflog` last 10, `git stash list`, uncommitted diff, last Claude Code session for this cwd (`--continue` finds the most recent session; read its transcript summary), agentd audit entries, last-touched files | read_local → AUTO | "You were on fix/tokenizer-padding, halfway through making the collator pad left; the test for it is written but failing. Last agent session suggested checking the attention mask." HUD: files + "Resume session" button (`claude --resume <id>`) | M |
| **PR review queue nudge** | Review requests older than 24 h, especially from the mentee | read_remote → AUTO | Toast in the morning brief; speak only if > 48 h | S |
| **Dependency/security drift** (weekly) | Dependabot alerts via `gh api`; `uv lock --upgrade --dry-run` | read → AUTO | Digest only; "fix" spawns a fleet agent | S |

**Context-sensitive "what's next?"** combines the above: "you have 40 minutes before your 2 pm; the two quickest wins are rerunning the flaky lint job and approving Sam's docs PR."

---

## 6. Features nobody ships (shortlist for the portfolio)

1. **Spoken fleet supervision with a priority-ordered verdict** (§1.4). Existing orchestrators are visual only.
2. **Cross-system conditional voice rules**: "when the PR is green *and* the eval job finishes, tell me; if eval regresses on any slice by more than 2 points, don't merge." This is a small rule engine over the watchers, a direct expression of the owner's evals-driven-development thesis.
3. **Eval-regression narrator.** After any agent change or new checkpoint, auto-run the bench suite in the background and speak only the slice-level regressions. It ties coding agents to evals, which no orchestrator does.
4. **Cost-aware compute guardrails as a first-class effect** (`spend_compute` with budget cards + idle sentinel). Most agent tools treat GPU spend as just another shell command.
5. **"Explain the terminal error" with redaction and a click-to-insert fix.** Wispr-style dictation tools can't read the terminal, and terminal AIs can't take hold-to-talk queries from outside the terminal.
6. **Repo re-entry memory** ("what was I doing?") built from git reflog, stash, the agent transcript, and the agentd audit log.

---

## 7. Build order

| Phase | Deliverable | Depends on | Est. |
|---|---|---|---|
| 1 | `read_remote` effect + `gh` allowlist; git status/commit-message/PR; CI status, failing log, rerun | — | 3–4 days |
| 2 | FleetManager with Claude Agent SDK backend, worktree service, `canUseTool` → approval cards, nickname addressing, cached summarizer, "status?" | phase 1 | 1.5–2 weeks |
| 3 | Ambient: CI watcher, agent-needs-you (HTTP hooks), interruption policy, morning brief / EOD | phases 1–2, Calendar | 1 week |
| 4 | ML: W&B/MLflow loss queries + speakable trend summarizer, HF Jobs launch with `spend_compute`, nvidia-smi over ssh, training watcher | MCP mounting (or Python sidecar) | 1–1.5 weeks |
| 5 | Codex + Cursor backends behind the same `FleetBackend` interface; eval-regression narrator wired to `bench/` | phase 2 | 1 week |
| 6 | Terminal buffer reader (iTerm2 API / AppleScript / AX), DB query with SQL preview, K8s/AWS read-only MCPs | AX work | 1 week |

**Python sidecar note:** W&B, MLflow, HF `huggingface_hub`, `datasets`, TensorBoard readers, and tokenizers are all Python-first. Rather than re-implementing them in Node, run a small `uv`-managed Python MCP server (stdio) that agentd mounts. It doubles as a showcase MCP server for the open-source repo.

---

## 8. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Prompt injection from PR descriptions, CI logs, issue text, dataset rows | `read_remote` output is tagged untrusted. The planner cannot chain a write effect from untrusted text without a fresh user utterance. Show provenance on approval cards ("suggested by CI log") |
| Untrusted repo config executing under `-p` (hooks, `.mcp.json`) | `--bare` / explicit `settingSources` for any repo not on the allowlist |
| Secrets read aloud or sent to the LLM (env dumps in logs, AWS outputs) | Regex + entropy redaction before LLM and TTS. Never speak strings > 20 chars that aren't words |
| Mis-addressed voice approval ("approve" goes to the wrong agent) | Read back the nickname before acting. Approvals expire after 2 min (existing) → deny-with-message |
| Runaway agent spend | Per-agent `--max-budget-usd`, fleet cap, spoken cost in "status?" |
| Worktree sprawl / locks left by `-p` | agentd owns cleanup; periodic sweep; `git worktree unlock` handling |
| Speaking during meetings | Interruption policy keyed on mic-in-use + calendar |

---

## Sources

- Claude Code headless / Agent SDK CLI: https://code.claude.com/docs/en/headless
- Claude Agent SDK permissions (evaluation order, modes, `canUseTool`, `setPermissionMode`): https://code.claude.com/docs/en/agent-sdk/permissions
- Claude Code worktrees (`--worktree`, `.worktreeinclude`, `isolation: worktree`, cleanup): https://code.claude.com/docs/en/worktrees
- Claude Code hooks reference (events, HTTP hooks, decisions): https://code.claude.com/docs/en/hooks?frame=0
- Claude Code voice mode coverage: https://www.pcworld.com/article/3079359/claude-code-goes-hands-free-with-voice-commands-now-rolling-out.html
- Voice coding with agents (practitioner write-up): https://dev.to/stevengonsalvez/voice-coding-talk-to-your-agent-like-a-normal-person-4ce9
- Codex non-interactive mode: https://developers.openai.com/codex/noninteractive
- Codex exec JSONL event reference: https://codex.danielvaughan.com/2026/04/08/codex-exec-jsonl-reference/
- Codex TypeScript SDK: https://codex.danielvaughan.com/2026/04/08/codex-typescript-sdk-streaming-multimodal/
- Cursor Cloud Agents API endpoints (v1): https://techdevnotes.com/releases/cursor-docs/20260626-202020Z-6c7064724f5e/content/pages/cloud-agent/api/endpoints.txt
- Cursor Cloud Agents API overview: https://mcpbundles.com/blog/cursor-cloud-agents-api
- Agent orchestration tools roundup (Conductor, crystl, Claude Squad, Vibe Kanban, Sculptor…): https://crystl.dev/blog/best-ai-agent-orchestration-tools/
- Agent management tools roundup (Nimbalyst, Superset, Paneflow…): https://nimbalyst-website.pages.dev/blog/best-agent-management-tools-2026/
- Vibe Kanban repo: https://github.com/BloopAI/vibe-kanban
- GitHub MCP server Actions tools PR: https://github.com/github/github-mcp-server/pull/491
- `gh` for debugging Actions: https://dev.to/andreagriffiths11/debug-github-actions-from-your-terminal-with-gh-3af5
- GitHub CLI and Actions: https://github.blog/news-insights/product-news/work-with-github-actions-in-your-terminal-with-github-cli/
- Hugging Face MCP server: https://huggingface.co/docs/hub/en/agents-mcp and https://github.com/huggingface/hf-mcp-server
- Hugging Face Jobs guide: https://huggingface.co/docs/huggingface_hub/en/guides/jobs
- W&B MCP server: https://huggingface.co/spaces/wandb/mcp-server/blob/main/README.md
- W&B public API (run history): https://docs.wandb.ai/models/ref/python/public-api/run
- MLflow MCP server: https://mlflow.org/docs/latest/genai/mcp/
- RunPod MCP server: https://github.com/runpod/runpod-mcp
- Modal community MCP: https://pypi.org/project/mcp-modal
- Lambda Cloud instances / API: https://docs.lambda.ai/public-cloud/on-demand/creating-managing-instances/
- Kubernetes MCP server: https://pkg.go.dev/github.com/containers/kubernetes-mcp-server
- AWS API MCP server: https://awslabs.github.io/mcp/servers/aws-api-mcp-server
- Linear MCP announcement: https://linear.app/changelog/2025-05-01-mcp
- Context7 MCP (library docs): https://hub.docker.com/mcp/server/context7/overview
