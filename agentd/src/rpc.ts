import { chmodSync, existsSync, mkdirSync, unlinkSync } from "node:fs";
import net from "node:net";
import path from "node:path";
import { randomUUID } from "node:crypto";
import { runTask, type AgentDeps, type TaskContext } from "./agent.js";
import type { ApprovalBroker, ApprovalDecision } from "./approvals.js";

/**
 * JSON-RPC 2.0 over a Unix socket, one JSON object per line (PLAN.md §8.2). The socket is
 * owner-only (0600), so only your user's processes can submit tasks or approve steps.
 *
 * Requests (app -> agentd): ping, task.submit {utterance, context?}, task.cancel {taskId},
 *   task.cancelAll, approval.respond {stepId, decision}
 * Notifications (agentd -> app): task.started, task.progress, approval.request, task.result, task.error,
 *   and for the timeline: task.plan {steps}, task.step {stepId, title, risk, status, ...},
 *   task.note {text}, task.metrics {inputTokens, outputTokens, turns}
 */
export class AgentServer {
  private server?: net.Server;
  private clients = new Set<net.Socket>();
  private running = new Map<string, AbortController>();

  constructor(
    private readonly socketPath: string,
    private readonly makeDeps: (notify: (method: string, params: unknown) => void) => { deps: AgentDeps; broker: ApprovalBroker },
  ) {}

  private deps?: AgentDeps;
  private broker?: ApprovalBroker;

  async start(): Promise<void> {
    // macOS limits Unix socket paths to 104 bytes (incl. NUL); fail clearly instead of with EINVAL.
    if (Buffer.byteLength(this.socketPath) > 103) throw new Error(`socket path too long (max 103 bytes): ${this.socketPath}`);
    const { deps, broker } = this.makeDeps((m, p) => this.broadcast(m, p));
    this.deps = deps;
    this.broker = broker;
    mkdirSync(path.dirname(this.socketPath), { recursive: true });
    if (existsSync(this.socketPath)) unlinkSync(this.socketPath);  // stale socket from a crash
    this.server = net.createServer((sock) => this.accept(sock));
    await new Promise<void>((resolve, reject) => {
      this.server!.once("error", reject);
      this.server!.listen(this.socketPath, () => resolve());
    });
    chmodSync(this.socketPath, 0o600);
  }

  async stop(): Promise<void> {
    this.cancelAll();
    for (const c of this.clients) c.destroy();
    await new Promise<void>((r) => (this.server ? this.server.close(() => r()) : r()));
    if (existsSync(this.socketPath)) unlinkSync(this.socketPath);
  }

  get activeTasks(): number {
    return this.running.size;
  }

  private accept(sock: net.Socket): void {
    this.clients.add(sock);
    let buffer = "";
    sock.setEncoding("utf8");
    sock.on("data", (chunk: string) => {
      buffer += chunk;
      let nl: number;
      while ((nl = buffer.indexOf("\n")) >= 0) {
        const line = buffer.slice(0, nl).trim();
        buffer = buffer.slice(nl + 1);
        if (line) this.handleLine(sock, line);
      }
    });
    sock.on("close", () => this.clients.delete(sock));
    sock.on("error", () => this.clients.delete(sock));
  }

  private send(sock: net.Socket, msg: object): void {
    if (!sock.destroyed) sock.write(JSON.stringify({ jsonrpc: "2.0", ...msg }) + "\n");
  }

  private broadcast(method: string, params: unknown): void {
    for (const c of this.clients) this.send(c, { method, params });
  }

  private handleLine(sock: net.Socket, line: string): void {
    let msg: { id?: string | number; method?: string; params?: Record<string, unknown> };
    try {
      msg = JSON.parse(line);
    } catch {
      return this.send(sock, { id: null, error: { code: -32700, message: "parse error" } });
    }
    const reply = (result: unknown) => msg.id !== undefined && this.send(sock, { id: msg.id, result });
    const fail = (code: number, message: string) => msg.id !== undefined && this.send(sock, { id: msg.id, error: { code, message } });
    const p = msg.params ?? {};

    switch (msg.method) {
      case "ping":
        return void reply({ ok: true, activeTasks: this.running.size });
      case "task.submit": {
        const utterance = typeof p.utterance === "string" ? p.utterance.trim() : "";
        if (!utterance) return void fail(-32602, "utterance is required");
        const taskId = randomUUID();
        reply({ taskId });
        void this.execute(taskId, utterance, (p.context as TaskContext | undefined) ?? undefined);
        return;
      }
      case "task.cancel": {
        const ok = this.cancel(String(p.taskId ?? ""));
        return void reply({ cancelled: ok });
      }
      case "task.cancelAll":
        return void reply({ cancelled: this.cancelAll() });
      case "approval.respond": {
        const decision = p.decision === "approve" ? "approve" : "deny";
        const ok = this.broker!.respond(String(p.stepId ?? ""), decision as ApprovalDecision);
        return void reply({ accepted: ok });
      }
      default:
        return void fail(-32601, `unknown method ${msg.method}`);
    }
  }

  private async execute(taskId: string, utterance: string, context?: TaskContext): Promise<void> {
    const controller = new AbortController();
    this.running.set(taskId, controller);
    this.broadcast("task.started", { taskId, utterance, startedAt: Date.now() });
    try {
      const summary = await runTask({ taskId, utterance, ...(context ? { context } : {}) }, this.deps!, controller.signal);
      this.broadcast("task.result", { taskId, summary });
    } catch (e) {
      this.broadcast("task.error", { taskId, message: e instanceof Error ? e.message : String(e) });
    } finally {
      this.running.delete(taskId);
    }
  }

  private cancel(taskId: string): boolean {
    const c = this.running.get(taskId);
    if (!c) return false;
    this.broker!.denyAllFor(taskId);
    c.abort();
    return true;
  }

  /** The kill switch: stops every task and kills their process groups. */
  cancelAll(): number {
    const ids = [...this.running.keys()];
    for (const id of ids) this.cancel(id);
    return ids.length;
  }
}
