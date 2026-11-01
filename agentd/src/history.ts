import { closeSync, existsSync, openSync, readSync, statSync } from "node:fs";

/** One finished or interrupted task, rebuilt from the audit log for the Task Center. */
export interface HistoryTask {
  taskId: string;
  utterance: string;
  startedAt: number;
  endedAt?: number;
  state: "done" | "failed" | "stopped" | "interrupted";
  summary: string;
  plan: { content: string; status: string }[];
  steps: { stepId: string; tool: string; title: string; risk: string; status: string; result: string; startedAt?: number; endedAt?: number }[];
  inputTokens: number;
  outputTokens: number;
}

type Entry = Record<string, unknown> & { at: string; event: string; taskId?: string };

/** Only the end of a large log is read; old tasks fall off. */
const MAX_BYTES = 4 * 1024 * 1024;

function readTail(file: string): string {
  if (!existsSync(file)) return "";
  const size = statSync(file).size;
  const start = Math.max(0, size - MAX_BYTES);
  const buf = Buffer.alloc(size - start);
  const fd = openSync(file, "r");
  try {
    readSync(fd, buf, 0, buf.length, start);
  } finally {
    closeSync(fd);
  }
  const text = buf.toString("utf8");
  return start > 0 ? text.slice(text.indexOf("\n") + 1) : text;  // drop the partial first line
}

function oneLine(s: unknown, max = 120): string {
  const line = String(s ?? "").split("\n")[0]!.trim();
  return line.length <= max ? line : `${line.slice(0, max - 1)}…`;
}

/** Older audit lines have no title: describe the step from its input. */
function fallbackTitle(e: Entry): string {
  const input = (e.input ?? {}) as Record<string, unknown>;
  const detail = input.command ?? input.path ?? input.name ?? input.repo ?? input.folder ?? input.url ?? "";
  return detail ? `${e.tool}: ${oneLine(detail, 60)}` : String(e.tool ?? "step");
}

/**
 * Newest first, at most `limit`. Tasks with no end line (agentd stopped mid-task) are "interrupted".
 * Running tasks are skipped: the app already has them live.
 */
export function readHistory(file: string, limit = 50, running: ReadonlySet<string> = new Set()): HistoryTask[] {
  const tasks = new Map<string, HistoryTask>();
  for (const line of readTail(file).split("\n")) {
    if (!line.trim()) continue;
    let e: Entry;
    try {
      e = JSON.parse(line) as Entry;
    } catch {
      continue;
    }
    const id = e.taskId;
    if (!id) continue;
    const at = Date.parse(e.at);
    if (e.event === "task.start") {
      tasks.set(id, {
        taskId: id, utterance: String(e.utterance ?? ""), startedAt: at, state: "interrupted", summary: "",
        plan: [], steps: [], inputTokens: 0, outputTokens: 0,
      });
      continue;
    }
    const t = tasks.get(id);
    if (!t) continue;
    switch (e.event) {
      case "task.plan":
        t.plan = (e.steps as HistoryTask["plan"]) ?? [];
        break;
      case "step.done":
      case "step.error":
      case "step.blocked": {
        const status = e.event === "step.done" ? "done" : e.event === "step.error" ? "error" : "blocked";
        const result = oneLine(e.event === "step.done" ? e.result : e.event === "step.error" ? e.error : e.reason);
        const stepId = String(e.stepId ?? `${id}-${t.steps.length}`);
        const step = {
          stepId, tool: String(e.tool ?? ""), title: String(e.title ?? fallbackTitle(e)), risk: String(e.risk ?? "read"),
          status, result,
          ...(typeof e.startedAt === "number" ? { startedAt: e.startedAt } : {}),
          endedAt: typeof e.endedAt === "number" ? e.endedAt : at,
        };
        const i = t.steps.findIndex((s) => s.stepId === stepId);
        if (i >= 0) t.steps[i] = step; else t.steps.push(step);
        break;
      }
      case "step.approval":
        if (e.decision !== "approve") {
          t.steps.push({
            stepId: String(e.stepId ?? `${id}-${t.steps.length}`), tool: String(e.tool ?? ""),
            title: String(e.title ?? fallbackTitle(e)), risk: String(e.risk ?? "medium"), status: "denied", result: "",
            endedAt: at,
          });
        }
        break;
      case "task.done":
      case "task.error":
        t.endedAt = at;
        t.summary = String(e.event === "task.done" ? e.summary ?? "" : e.error ?? "");
        t.state = e.event === "task.done" ? "done" : e.error === "cancelled" ? "stopped" : "failed";
        if (t.state === "stopped") t.summary = "Stopped.";
        t.inputTokens = Number(e.inputTokens ?? 0);
        t.outputTokens = Number(e.outputTokens ?? 0);
        break;
    }
  }
  // Later in the log = newer, also when two tasks start in the same millisecond.
  return [...tasks.values()]
    .map((t, order) => ({ t, order }))
    .filter(({ t }) => !running.has(t.taskId))
    .sort((a, b) => b.t.startedAt - a.t.startedAt || b.order - a.order)
    .slice(0, limit)
    .map(({ t }) => t);
}
