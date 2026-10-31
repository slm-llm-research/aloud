import { appendFileSync, mkdirSync } from "node:fs";
import path from "node:path";

/** Append-only JSONL record of every task, step, decision and result (PLAN.md §8.3). */
export class AuditLog {
  constructor(private readonly file: string) {
    mkdirSync(path.dirname(file), { recursive: true });
  }

  write(event: string, data: Record<string, unknown>): void {
    const line = JSON.stringify({ at: new Date().toISOString(), event, ...data });
    appendFileSync(this.file, line + "\n", { mode: 0o600 });
  }
}
