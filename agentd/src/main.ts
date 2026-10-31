import Anthropic from "@anthropic-ai/sdk";
import { ClaudePlanner } from "./agent.js";
import { ApprovalBroker } from "./approvals.js";
import { AuditLog } from "./audit.js";
import { loadAnthropicKey, loadConfig } from "./config.js";
import { AgentServer } from "./rpc.js";
import { ALL_TOOLS } from "./tools/index.js";

// MURMUR_AGENT_CONFIG is the pre-rename name, still honoured.
const configPath = process.env.INSTRUCTFLOW_AGENT_CONFIG ?? process.env.MURMUR_AGENT_CONFIG;
const cfg = configPath ? loadConfig(configPath) : loadConfig();
const apiKey = loadAnthropicKey();
if (!apiKey) {
  console.error("agentd: no ANTHROPIC_API_KEY (environment or ~/Library/Application Support/InstructFlow/keys.env)");
  process.exit(2);
}

const audit = new AuditLog(cfg.auditPath);
const planner = new ClaudePlanner(new Anthropic({ apiKey }), cfg);

const server = new AgentServer(cfg.socketPath, (notify) => {
  const broker = new ApprovalBroker((req) => notify("approval.request", req), cfg.approvalTimeoutMs);
  return {
    broker,
    deps: {
      cfg, broker, audit, planner, tools: ALL_TOOLS,
      progress: (taskId, message) => notify("task.progress", { taskId, message }),
    },
  };
});

await server.start();
audit.write("agentd.start", { pid: process.pid, model: cfg.model, roots: cfg.allowedRoots });
console.log(`agentd: listening on ${cfg.socketPath} (model ${cfg.model}, roots ${cfg.allowedRoots.join(", ")})`);

const shutdown = async () => {
  await server.stop();
  process.exit(0);
};
process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);
// The InstructFlow app owns us: if it goes away (stdin closes), exit too.
process.stdin.on("end", shutdown);
process.stdin.resume();
