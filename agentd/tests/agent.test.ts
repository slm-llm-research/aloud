import { existsSync, mkdtempSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import net from "node:net";
import { tmpdir } from "node:os";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { runTask, type GatedTool, type Planner, type TaskRequest } from "../src/agent.js";
import { ApprovalBroker, type ApprovalRequest } from "../src/approvals.js";
import { AuditLog } from "../src/audit.js";
import { defaultConfig, type AgentConfig } from "../src/config.js";
import { AgentServer } from "../src/rpc.js";
import { ALL_TOOLS, lineDiff } from "../src/tools/index.js";

function setup(answer: (r: ApprovalRequest) => "approve" | "deny" | "ignore" = () => "approve", timeoutMs = 2_000) {
  const root = realpathSync(mkdtempSync(path.join(tmpdir(), "instructflow-agent-")));
  const cfg: AgentConfig = { ...defaultConfig(), allowedRoots: [root], auditPath: path.join(root, ".audit.jsonl") };
  const requests: ApprovalRequest[] = [];
  const progress: string[] = [];
  const broker: ApprovalBroker = new ApprovalBroker((req) => {
    requests.push(req);
    const a = answer(req);
    if (a !== "ignore") setTimeout(() => broker.respond(req.stepId, a), 5);
  }, timeoutMs);
  const audit = new AuditLog(cfg.auditPath);
  return { root, cfg, broker, audit, requests, progress };
}

/** Calls tools in a fixed order, like a model would, and reports their results. */
class ScriptedPlanner implements Planner {
  results: string[] = [];
  constructor(private readonly steps: [string, unknown][]) {}
  async run(_req: TaskRequest, tools: GatedTool[], signal: AbortSignal): Promise<string> {
    for (const [name, input] of this.steps) {
      if (signal.aborted) throw new Error("aborted");
      const tool = tools.find((t) => t.contract.name === name)!;
      this.results.push(await tool.call(tool.contract.input.parse(input)));
    }
    return "done";
  }
}

async function run(env: ReturnType<typeof setup>, steps: [string, unknown][], signal = new AbortController().signal) {
  const planner = new ScriptedPlanner(steps);
  await runTask({ taskId: "t1", utterance: "test" }, {
    cfg: env.cfg, broker: env.broker, audit: env.audit, planner, tools: ALL_TOOLS,
    progress: (_id, m) => env.progress.push(m),
  }, signal);
  return planner.results;
}

describe("gated tools", () => {
  it("reads run without asking", async () => {
    const env = setup();
    writeFileSync(path.join(env.root, "notes.md"), "hello");
    const [listing, content] = await run(env, [["list_dir", { path: env.root }], ["read_file", { path: "notes.md" }]]);
    expect(listing).toContain("notes.md");
    expect(content).toBe("hello");
    expect(env.requests).toHaveLength(0);
  });

  it("find_files counts by pattern recursively, skipping node_modules, without asking", async () => {
    const env = setup();
    const { mkdirSync } = await import("node:fs");
    mkdirSync(path.join(env.root, "docs/deep"), { recursive: true });
    mkdirSync(path.join(env.root, "node_modules/pkg"), { recursive: true });
    for (const f of ["README.md", "docs/a.md", "docs/deep/b.MD", "docs/c.txt", "node_modules/pkg/x.md"])
      writeFileSync(path.join(env.root, f), "x");
    const [result] = await run(env, [["find_files", { folder: env.root, pattern: "*.md" }]]);
    expect(result).toMatch(/^3 file\(s\)/);
    expect(result).not.toContain("node_modules");
    expect(env.requests).toHaveLength(0);
  });

  it("find_folders matches spoken spellings of a folder name", async () => {
    const env = setup();
    const { mkdirSync } = await import("node:fs");
    mkdirSync(path.join(env.root, "Agentic_2026/voice-flow/agentd/src"), { recursive: true });
    mkdirSync(path.join(env.root, "Agentic_2026/voice-flow/agentd-old"), { recursive: true });
    mkdirSync(path.join(env.root, "Agentic_2026/node_modules/agentd"), { recursive: true });
    for (const spoken of ["Agent D", "agent-d", "AgentD", "agentd"]) {
      const [r] = await run(env, [["find_folders", { name: spoken }]]);
      expect(r, spoken).toContain(`exact: ${path.join(env.root, "Agentic_2026/voice-flow/agentd")}`);
      expect(r, spoken).toContain("similar:");  // agentd-old
      expect(r, spoken).not.toContain("node_modules");
    }
    const [none] = await run(env, [["find_folders", { name: "zebra" }]]);
    expect(none).toMatch(/^No folder/);
    expect(env.requests).toHaveLength(0);
  });

  it("find_files can list folders too", async () => {
    const env = setup();
    const { mkdirSync } = await import("node:fs");
    mkdirSync(path.join(env.root, "a/agentd"), { recursive: true });
    writeFileSync(path.join(env.root, "a/agentd.txt"), "x");
    const [folders] = await run(env, [["find_files", { folder: env.root, pattern: "agentd*", kind: "folders" }]]);
    expect(folders).toContain("a/agentd/");
    expect(folders).not.toContain("agentd.txt");
    const [both] = await run(env, [["find_files", { folder: env.root, pattern: "agentd*", kind: "both" }]]);
    expect(both).toContain("a/agentd/");
    expect(both).toContain("a/agentd.txt");
  });

  it("writes ask first and show the diff", async () => {
    const env = setup();
    writeFileSync(path.join(env.root, "a.txt"), "one\ntwo\nthree");
    await run(env, [["write_file", { path: "a.txt", content: "one\n2\nthree" }]]);
    expect(env.requests).toHaveLength(1);
    expect(env.requests[0]!.preview).toContain("- two");
    expect(env.requests[0]!.preview).toContain("+ 2");
    expect(readFileSync(path.join(env.root, "a.txt"), "utf8")).toBe("one\n2\nthree");
  });

  it("a declined write changes nothing and tells the model to stop", async () => {
    const env = setup(() => "deny");
    const [result] = await run(env, [["write_file", { path: "new.txt", content: "x" }]]);
    expect(result).toMatch(/DECLINED/);
    expect(existsSync(path.join(env.root, "new.txt"))).toBe(false);
  });

  it("no answer means no: approvals time out to deny", async () => {
    const env = setup(() => "ignore", 50);
    const [result] = await run(env, [["run_shell", { command: "echo hi", cwd: env.root }]]);
    expect(result).toMatch(/DECLINED/);
  });

  it("shell commands run after approval, in the allowed folder", async () => {
    const env = setup();
    const [result] = await run(env, [["run_shell", { command: "pwd && echo ok", cwd: env.root }]]);
    expect(env.requests[0]!.preview).toContain("$ pwd && echo ok");
    expect(result).toContain(env.root);
    expect(result).toContain("ok");
  });

  it("dangerous commands are blocked without even asking", async () => {
    const env = setup();
    const results = await run(env, [
      ["run_shell", { command: "rm -rf .", cwd: env.root }],
      ["run_shell", { command: "git push --force", cwd: env.root }],
      ["run_shell", { command: "cat /etc/passwd", cwd: env.root }],
      ["run_shell", { command: "ls", cwd: "/" }],
    ]);
    for (const r of results) expect(r).toMatch(/^BLOCKED/);
    expect(env.requests).toHaveLength(0);
  });

  it("files outside the allowed folders are blocked", async () => {
    const env = setup();
    const results = await run(env, [
      ["read_file", { path: "/etc/hosts" }],
      ["write_file", { path: "~/.zshrc", content: "x" }],
      ["list_dir", { path: "../" }],
    ]);
    for (const r of results) expect(r).toMatch(/^BLOCKED/);
  });

  it("everything is audited", async () => {
    const env = setup(() => "deny");
    await run(env, [["read_file", { path: "missing.txt" }], ["write_file", { path: "x.txt", content: "y" }],
                    ["run_shell", { command: "sudo ls", cwd: env.root }]]);
    const events = readFileSync(env.cfg.auditPath, "utf8").trim().split("\n").map((l) => JSON.parse(l).event);
    expect(events).toEqual(["task.start", "step.error", "step.approval", "step.blocked", "task.done"]);
  });

  it("cancelling kills a running command", async () => {
    const env = setup();
    const controller = new AbortController();
    setTimeout(() => controller.abort(), 300);
    const started = Date.now();
    const [result] = await run(env, [["run_shell", { command: "node -e \"setTimeout(()=>{},60000)\"", cwd: env.root }]],
                               controller.signal);
    expect(result).toContain("cancelled");
    expect(Date.now() - started).toBeLessThan(5_000);
  });
});

describe("lineDiff", () => {
  it("shows only the changed region with context", () => {
    const d = lineDiff("a\nb\nc\nd\ne\nf", "a\nb\nc\nX\ne\nf", 1);
    expect(d).toBe("  c\n- d\n+ X\n  e");
  });
});

describe("socket protocol", () => {
  function client(socketPath: string) {
    const sock = net.createConnection(socketPath);
    const messages: any[] = [];
    let buf = "";
    sock.setEncoding("utf8");
    sock.on("data", (d: string) => {
      buf += d;
      let i: number;
      while ((i = buf.indexOf("\n")) >= 0) {
        messages.push(JSON.parse(buf.slice(0, i)));
        buf = buf.slice(i + 1);
      }
    });
    const send = (m: object) => sock.write(JSON.stringify({ jsonrpc: "2.0", ...m }) + "\n");
    const waitFor = async (pred: (m: any) => boolean, ms = 3_000) => {
      const t0 = Date.now();
      for (;;) {
        const m = messages.find(pred);
        if (m) return m;
        if (Date.now() - t0 > ms) throw new Error(`timeout; got ${JSON.stringify(messages)}`);
        await new Promise((r) => setTimeout(r, 10));
      }
    };
    return { sock, send, waitFor, messages, ready: new Promise((r) => sock.once("connect", r)) };
  }

  function server(env: ReturnType<typeof setup>, planner: Planner) {
    const socketPath = path.join(env.root, "agentd.sock");
    const srv = new AgentServer(socketPath, (notify) => {
      const broker = new ApprovalBroker((req) => notify("approval.request", req), 2_000);
      return { broker, deps: { cfg: env.cfg, broker, audit: env.audit, planner, tools: ALL_TOOLS,
                               progress: (taskId, message) => notify("task.progress", { taskId, message }) } };
    });
    return { srv, socketPath };
  }

  it("submit -> approval request -> approve -> result, over the socket", async () => {
    const env = setup();
    const { srv, socketPath } = server(env, new ScriptedPlanner([["write_file", { path: "hello.txt", content: "hi" }]]));
    await srv.start();
    const c = client(socketPath);
    await c.ready;
    c.send({ id: 1, method: "task.submit", params: { utterance: "write hello", context: { app: "Terminal" } } });
    const ack = await c.waitFor((m) => m.id === 1);
    const approval = await c.waitFor((m) => m.method === "approval.request");
    expect(approval.params.tool).toBe("write_file");
    expect(approval.params.taskId).toBe(ack.result.taskId);
    c.send({ id: 2, method: "approval.respond", params: { stepId: approval.params.stepId, decision: "approve" } });
    const result = await c.waitFor((m) => m.method === "task.result");
    expect(result.params.summary).toBe("done");
    expect(readFileSync(path.join(env.root, "hello.txt"), "utf8")).toBe("hi");
    c.sock.destroy();
    await srv.stop();
  });

  it("socket is private to the user", async () => {
    const env = setup();
    const { srv, socketPath } = server(env, new ScriptedPlanner([]));
    await srv.start();
    const { statSync } = await import("node:fs");
    expect(statSync(socketPath).mode & 0o777).toBe(0o600);
    await srv.stop();
  });

  it("kill switch cancels pending approvals and running tasks", async () => {
    const env = setup();
    const { srv, socketPath } = server(env, new ScriptedPlanner([["run_shell", { command: "echo never", cwd: env.root }]]));
    await srv.start();
    const c = client(socketPath);
    await c.ready;
    c.send({ id: 1, method: "task.submit", params: { utterance: "x" } });
    await c.waitFor((m) => m.method === "approval.request");
    c.send({ id: 2, method: "task.cancelAll" });
    expect((await c.waitFor((m) => m.id === 2)).result.cancelled).toBe(1);
    await c.waitFor((m) => m.method === "task.error" || m.method === "task.result");
    expect(srv.activeTasks).toBe(0);
    c.sock.destroy();
    await srv.stop();
  });

  it("refuses a socket path macOS can't bind, with a clear error", async () => {
    const env = setup();
    const srv = new AgentServer("/tmp/" + "x".repeat(120) + ".sock", () => { throw new Error("unreachable"); });
    await expect(srv.start()).rejects.toThrow(/too long/);
  });

  it("rejects bad requests", async () => {
    const env = setup();
    const { srv, socketPath } = server(env, new ScriptedPlanner([]));
    await srv.start();
    const c = client(socketPath);
    await c.ready;
    c.send({ id: 1, method: "task.submit", params: { utterance: "  " } });
    c.send({ id: 2, method: "rm.everything" });
    c.sock.write("not json\n");
    expect((await c.waitFor((m) => m.id === 1)).error.code).toBe(-32602);
    expect((await c.waitFor((m) => m.id === 2)).error.code).toBe(-32601);
    expect((await c.waitFor((m) => m.id === null)).error.code).toBe(-32700);
    c.sock.destroy();
    await srv.stop();
  });
});

describe("timeline events (agent UI)", () => {
  async function runWithEvents(env: ReturnType<typeof setup>, steps: [string, unknown][]) {
    const events: [string, Record<string, unknown>][] = [];
    const planner = new ScriptedPlanner(steps);
    await runTask({ taskId: "t1", utterance: "test" }, {
      cfg: env.cfg, broker: env.broker, audit: env.audit, planner, tools: ALL_TOOLS,
      progress: () => {}, emit: (m, p) => events.push([m, p]),
    }, new AbortController().signal);
    return { events, results: planner.results };
  }

  it("a read step reports running then done, with a plain title and no approval", async () => {
    const env = setup();
    const { events } = await runWithEvents(env, [["list_dir", { path: env.root }]]);
    const steps = events.filter(([m]) => m === "task.step").map(([, p]) => p);
    expect(steps.map((s) => s.status)).toEqual(["running", "done"]);
    expect(steps[0]!.risk).toBe("read");
    expect(String(steps[0]!.title)).toMatch(/^List /);
    expect(steps[0]!.stepId).toBe(steps[1]!.stepId);
    expect(env.requests).toHaveLength(0);
  });

  it("an approval card carries title, risk, expiry and the same step id as the timeline", async () => {
    const env = setup();
    const { events } = await runWithEvents(env, [["run_shell", { command: "echo hi", cwd: env.root }]]);
    const steps = events.filter(([m]) => m === "task.step").map(([, p]) => p);
    expect(steps.map((s) => s.status)).toEqual(["waiting", "running", "done"]);
    const req = env.requests[0]!;
    expect(req.title).toMatch(/^Run echo hi in /);
    expect(req.risk).toBe("medium");
    expect(req.expiresAt).toBeGreaterThan(Date.now());
    expect(req.stepId).toBe(steps[0]!.stepId);
  });

  it("declined and blocked steps say so", async () => {
    const env = setup(() => "deny");
    const { events } = await runWithEvents(env, [
      ["write_file", { path: "x.txt", content: "y" }],
      ["run_shell", { command: "sudo ls", cwd: env.root }],
    ]);
    const statuses = events.filter(([m]) => m === "task.step").map(([, p]) => p.status);
    expect(statuses).toEqual(["waiting", "denied", "blocked"]);
  });

  it("update_plan needs no approval and sends the whole checklist", async () => {
    const env = setup();
    const plan = { steps: [{ content: "List the folder", status: "completed" }, { content: "Summarise", status: "inProgress" }] };
    const { events, results } = await runWithEvents(env, [["update_plan", plan]]);
    expect(results[0]).toMatch(/Plan shown/);
    expect(events).toContainEqual(["task.plan", { taskId: "t1", steps: plan.steps }]);
    expect(env.requests).toHaveLength(0);
  });
});
