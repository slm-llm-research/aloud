import { randomUUID } from "node:crypto";
import type { Effect } from "./effects.js";

export type ApprovalDecision = "approve" | "deny";

export interface ApprovalRequest {
  taskId: string;
  stepId: string;
  tool: string;
  preview: string;
  effects: Effect[];
}

/**
 * Pending "may I do this?" questions. A request resolves when the app answers, when it times out
 * (deny), or when its task is cancelled (deny). Silence is never consent.
 */
export class ApprovalBroker {
  private pending = new Map<string, { req: ApprovalRequest; resolve: (d: ApprovalDecision) => void; timer: NodeJS.Timeout }>();

  constructor(
    private readonly notify: (req: ApprovalRequest) => void,
    private readonly timeoutMs: number,
  ) {}

  request(taskId: string, tool: string, preview: string, effects: Effect[]): Promise<ApprovalDecision> {
    const req: ApprovalRequest = { taskId, stepId: randomUUID(), tool, preview, effects };
    return new Promise((resolve) => {
      const timer = setTimeout(() => this.settle(req.stepId, "deny"), this.timeoutMs);
      this.pending.set(req.stepId, { req, resolve, timer });
      this.notify(req);
    });
  }

  /** Returns false if the step is unknown (already answered, timed out, or cancelled). */
  respond(stepId: string, decision: ApprovalDecision): boolean {
    return this.settle(stepId, decision);
  }

  denyAllFor(taskId: string): void {
    for (const [id, p] of this.pending) if (p.req.taskId === taskId) this.settle(id, "deny");
  }

  get size(): number {
    return this.pending.size;
  }

  private settle(stepId: string, decision: ApprovalDecision): boolean {
    const p = this.pending.get(stepId);
    if (!p) return false;
    clearTimeout(p.timer);
    this.pending.delete(stepId);
    p.resolve(decision);
    return true;
  }
}
