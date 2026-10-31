import type { ApprovalBroker } from "./approvals.js";
import type { AuditLog } from "./audit.js";
import type { AgentConfig } from "./config.js";
import { decide } from "./effects.js";
import type { ToolContract } from "./tools/contract.js";

export interface GateDeps {
  cfg: AgentConfig;
  broker: ApprovalBroker;
  audit: AuditLog;
  progress: (message: string) => void;
}

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

  const blockReason = tool.check?.(input as never, cfg) ?? null;
  const decision = blockReason ? { kind: "block" as const, reason: blockReason } : decide(effects);

  if (decision.kind === "block") {
    audit.write("step.blocked", { ...base, reason: decision.reason });
    progress(`Blocked: ${decision.reason}`);
    return `BLOCKED by InstructFlow's safety policy: ${decision.reason}. Do not retry or work around this; tell the user what you could not do.`;
  }

  if (decision.kind === "confirm") {
    progress(`Waiting for your approval: ${tool.name}`);
    const answer = await broker.request(taskId, tool.name, preview, effects);
    audit.write("step.approval", { ...base, decision: answer });
    if (answer !== "approve") {
      return "The user DECLINED this step. Do not retry it or try an alternative that achieves the same effect; stop and report.";
    }
  }

  if (signal.aborted) return "Task was cancelled by the user. Stop.";
  progress(preview.split("\n")[0]!);
  try {
    const result = await tool.run(input as never, { cfg, signal });
    audit.write("step.done", { ...base, auto: decision.kind === "auto", result: result.slice(0, 2_000) });
    return result;
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    audit.write("step.error", { ...base, error: msg });
    return `Error: ${msg}`;
  }
}
