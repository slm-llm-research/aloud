import type { ApprovalBroker } from "./approvals.js";
import type { AuditLog } from "./audit.js";
import type { AgentConfig } from "./config.js";
import { randomUUID } from "node:crypto";
import { decide, riskOf } from "./effects.js";
import { oneLine, type ToolContract } from "./tools/contract.js";

export interface GateDeps {
  cfg: AgentConfig;
  broker: ApprovalBroker;
  audit: AuditLog;
  progress: (message: string) => void;
  /** Structured timeline events for the app (task.step); optional so older callers keep working. */
  emit?: (method: string, params: Record<string, unknown>) => void;
}

export type StepStatus = "waiting" | "running" | "done" | "error" | "blocked" | "denied";

/**
 * The only way a tool runs (PLAN.md §8.3): hard check -> effects policy -> (if needed) your
 * approval of this exact step -> run -> audit. What comes back is the tool result the model sees,
 * including refusals, so it stops instead of trying to work around them.
 */
export async function gatedRun(
  tool: ToolContract,
  input: unknown,
  taskId: string,
  signal: AbortSignal,
  deps: GateDeps,
): Promise<string> {
  const { cfg, broker, audit, progress } = deps;
  if (signal.aborted) return "Task was cancelled by the user. Stop.";

  const effects = tool.effects(input as never, cfg);
  const preview = tool.preview(input as never, cfg);
  const base = { taskId, tool: tool.name, input, effects };
  const stepId = randomUUID();
  const title = tool.title?.(input as never, cfg) ?? oneLine(preview);
  const risk = riskOf(effects);
  const startedAt = Date.now();
  const step = (status: StepStatus, extra: Record<string, unknown> = {}) =>
    deps.emit?.("task.step", { taskId, stepId, tool: tool.name, title, effects, risk, status, startedAt, ...extra });

  const blockReason = tool.check?.(input as never, cfg) ?? null;
  const decision = blockReason ? { kind: "block" as const, reason: blockReason } : decide(effects);

  if (decision.kind === "block") {
    audit.write("step.blocked", { ...base, reason: decision.reason });
    progress(`Blocked: ${decision.reason}`);
    step("blocked", { endedAt: Date.now(), result: decision.reason });
    return `BLOCKED by InstructFlow's safety policy: ${decision.reason}. Do not retry or work around this; tell the user what you could not do.`;
  }

  if (decision.kind === "confirm") {
    progress(`Waiting for your approval: ${tool.name}`);
    step("waiting");
    const answer = await broker.request(taskId, tool.name, preview, effects, { stepId, title, risk });
    audit.write("step.approval", { ...base, decision: answer });
    if (answer !== "approve") {
      step("denied", { endedAt: Date.now() });
      return "The user DECLINED this step. Do not retry it or try an alternative that achieves the same effect; stop and report.";
    }
  }

  if (signal.aborted) return "Task was cancelled by the user. Stop.";
  progress(preview.split("\n")[0]!);
  step("running");
  try {
    const result = await tool.run(input as never, { cfg, signal });
    audit.write("step.done", { ...base, auto: decision.kind === "auto", result: result.slice(0, 2_000) });
    step("done", { endedAt: Date.now(), result: oneLine(result, 120) });
    return result;
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    audit.write("step.error", { ...base, error: msg });
    step("error", { endedAt: Date.now(), result: oneLine(msg, 120) });
    return `Error: ${msg}`;
  }
}
