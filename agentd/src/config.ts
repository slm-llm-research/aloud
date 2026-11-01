import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";
import { expandHome } from "./paths.js";
import { DEFAULT_SHELL_ALLOWLIST } from "./shellPolicy.js";

export interface AgentConfig {
  /** Folders the agent may read/write and run commands in. */
  allowedRoots: string[];
  /** Programs run_shell may start. */
  shellAllowlist: string[];
  model: string;
  effort: "low" | "medium" | "high";
  maxIterations: number;
  /** Unanswered approvals are denied after this long. */
  approvalTimeoutMs: number;
  socketPath: string;
  auditPath: string;
  claudePath: string;
}

export const SUPPORT_DIR = path.join(homedir(), "Library/Application Support/Aloud");

export function defaultConfig(home = homedir()): AgentConfig {
  return {
    // None until the user adds folders (menu: Agent Settings…), so the agent can't touch anything by default.
    allowedRoots: [],
    shellAllowlist: [...DEFAULT_SHELL_ALLOWLIST],
    model: "claude-opus-5-5",
    effort: "low",
    maxIterations: 12,
    approvalTimeoutMs: 120_000,
    socketPath: path.join(home, "Library/Application Support/Aloud/agentd.sock"),
    auditPath: path.join(home, "Library/Logs/Aloud/agent-audit.jsonl"),
    claudePath: path.join(home, ".local/bin/claude"),
  };
}

/** Defaults overlaid with ~/Library/Application Support/Aloud/agent.json (if present). */
export function loadConfig(file = path.join(SUPPORT_DIR, "agent.json"), home = homedir()): AgentConfig {
  const cfg = defaultConfig(home);
  let user: Partial<AgentConfig> = {};
  try {
    user = JSON.parse(readFileSync(file, "utf8")) as Partial<AgentConfig>;
  } catch {
    // no file or unreadable: defaults
  }
  const merged = { ...cfg, ...user };
  merged.allowedRoots = merged.allowedRoots.map((r) => path.resolve(expandHome(r, home)));
  merged.socketPath = expandHome(merged.socketPath, home);
  merged.auditPath = expandHome(merged.auditPath, home);
  merged.claudePath = expandHome(merged.claudePath, home);
  return merged;
}

/** Reads ANTHROPIC_API_KEY from the environment or Aloud's keys file. */
export function loadAnthropicKey(file = path.join(SUPPORT_DIR, "keys.env")): string | undefined {
  if (process.env.ANTHROPIC_API_KEY) return process.env.ANTHROPIC_API_KEY;
  try {
    for (const line of readFileSync(file, "utf8").split(/\r?\n/)) {
      const m = /^\s*ANTHROPIC_API_KEY\s*=\s*(.+?)\s*$/.exec(line);
      if (m) return m[1]!.replace(/^["']|["']$/g, "");
    }
  } catch {
    // no keys file
  }
  return undefined;
}
