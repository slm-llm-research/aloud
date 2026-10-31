import { existsSync, readdirSync, readFileSync, statSync, writeFileSync, mkdirSync } from "node:fs";
import path from "node:path";
import { z } from "zod";
import type { AgentConfig } from "../config.js";
import { confine, PathOutsideRootsError } from "../paths.js";
import { checkCommand } from "../shellPolicy.js";
import { clip, defineTool, type ToolContract } from "./contract.js";
import { runProcess } from "./process.js";

function confined(p: string, cfg: AgentConfig): string | null {
  try {
    confine(p, cfg.allowedRoots);
    return null;
  } catch (e) {
    return e instanceof PathOutsideRootsError ? e.message : String(e);
  }
}

/** Absolute or ~ paths in a shell command must also stay inside the allowed folders. */
function shellPathsConfined(command: string, cfg: AgentConfig): string | null {
  for (const word of command.split(/\s+/)) {
    const w = word.replace(/^["']|["']$/g, "");
    if (w.startsWith("/") || w.startsWith("~")) {
      const reason = confined(w, cfg);
      if (reason) return reason;
    }
  }
  return null;
}

export const openApp = defineTool({
  name: "open_app",
  description: "Open (or bring to front) a macOS application by name, e.g. \"Cursor\", \"Slack\", \"Notes\".",
  input: z.object({ name: z.string().min(1).max(80).describe("Application name as shown in /Applications") }),
  effects: () => ["launch_app"],
  preview: (i) => `Open the app “${i.name}”`,
  check: (i) => (/[/\\]|\.\./.test(i.name) ? "give the app name, not a path" : null),
  async run(i, ctx) {
    const r = await runProcess("/usr/bin/open", ["-a", i.name], { cwd: "/", timeoutMs: 15_000, signal: ctx.signal });
    return r.code === 0 ? `Opened ${i.name}.` : `Could not open ${i.name}: ${r.output.trim()}`;
  },
});

export const openUrl = defineTool({
  name: "open_url",
  description: "Open an http(s) URL in the default browser.",
  input: z.object({ url: z.string().url() }),
  effects: () => ["open_url"],
  preview: (i) => `Open ${i.url}`,
  check: (i) => (/^https?:\/\//i.test(i.url) ? null : "only http(s) URLs can be opened"),
  async run(i, ctx) {
    const r = await runProcess("/usr/bin/open", [i.url], { cwd: "/", timeoutMs: 15_000, signal: ctx.signal });
    return r.code === 0 ? `Opened ${i.url}.` : `Could not open the URL: ${r.output.trim()}`;
  },
});

export const listDir = defineTool({
  name: "list_dir",
  description: "List the entries of a folder (inside the allowed folders).",
  input: z.object({ path: z.string().describe("Folder path; ~ and paths relative to the first allowed folder work") }),
  effects: () => ["read_local"],
  preview: (i) => `List ${i.path}`,
  check: (i, cfg) => confined(i.path, cfg),
  async run(i, ctx) {
    const dir = confine(i.path, ctx.cfg.allowedRoots);
    const entries = readdirSync(dir, { withFileTypes: true })
      .filter((e) => !e.name.startsWith("."))
      .map((e) => (e.isDirectory() ? `${e.name}/` : e.name))
      .sort();
    return clip(`${dir}:\n${entries.join("\n")}`);
  },
});

/** "*.md" / "test_*.py" -> RegExp on the file name (only * and ? wildcards). */
export function globToRegExp(glob: string): RegExp {
  const escaped = glob.replace(/[.+^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*").replace(/\?/g, ".");
  return new RegExp(`^${escaped}$`, "i");
}

const SKIP_DIRS = new Set(["node_modules", ".git", ".build", "dist", "build", ".venv", "__pycache__", ".next"]);

export const findFiles = defineTool({
  name: "find_files",
  description:
    "Find files by name pattern (e.g. \"*.md\", \"test_*.py\", \"*\") in a folder and its subfolders, without " +
    "running any command. Skips node_modules, .git and build folders. Use this (not run_shell) to count or locate files.",
  input: z.object({
    folder: z.string(),
    pattern: z.string().min(1).max(100).default("*"),
    recursive: z.boolean().default(true),
    kind: z.enum(["files", "folders", "both"]).default("files"),
  }),
  effects: () => ["read_local"],
  preview: (i) => `Find ${i.pattern} (${i.kind}) in ${i.folder}`,
  check: (i, cfg) => confined(i.folder, cfg),
  async run(i, ctx) {
    const base = confine(i.folder, ctx.cfg.allowedRoots);
    const re = globToRegExp(i.pattern);
    const found: string[] = [];
    let truncated = false;
    const walk = (dir: string) => {
      for (const e of readdirSync(dir, { withFileTypes: true })) {
        if (ctx.signal.aborted) return;
        if (e.name.startsWith(".") && e.name !== ".env.example") continue;
        const full = path.join(dir, e.name);
        const isDir = e.isDirectory();
        const wanted = i.kind === "both" || (i.kind === "folders") === isDir;
        if (wanted && re.test(e.name) && !(isDir && SKIP_DIRS.has(e.name))) {
          if (found.length >= 2_000) { truncated = true; return; }
          found.push(path.relative(base, full) + (isDir ? "/" : ""));
        }
        if (isDir && i.recursive && !SKIP_DIRS.has(e.name)) walk(full);
      }
    };
    walk(base);
    found.sort();
    const head = `${found.length}${truncated ? "+" : ""} ${i.kind === "files" ? "file(s)" : "match(es)"} for ${i.pattern} in ${base}:`;
    return clip([head, ...found].join("\n"));
  },
});

/** "Agent D", "agent-d", "AgentD" -> "agentd": spoken names often split or join words. */
export function squash(name: string): string {
  return name.toLowerCase().replace(/[^a-z0-9]/g, "");
}

export const findFolders = defineTool({
  name: "find_folders",
  description:
    "Find folders (projects, repos) by name, tolerant of how speech recognition splits words: \"agent D\", " +
    "\"agent-d\" and \"AgentD\" all match a folder named agentd. Searches the allowed folders up to 6 levels " +
    "deep. Use this first whenever the user names a project or folder.",
  input: z.object({ name: z.string().min(1).max(100) }),
  effects: () => ["read_local"],
  preview: (i) => `Find folders named like “${i.name}”`,
  async run(i, ctx) {
    const target = squash(i.name);
    if (!target) return "Give a folder name.";
    const exact: string[] = [];
    const partial: string[] = [];
    const walk = (dir: string, depth: number) => {
      if (depth > 6 || ctx.signal.aborted) return;
      let entries;
      try { entries = readdirSync(dir, { withFileTypes: true }); } catch { return; }
      for (const e of entries) {
        if (!e.isDirectory() || e.name.startsWith(".") || SKIP_DIRS.has(e.name)) continue;
        const full = path.join(dir, e.name);
        const s = squash(e.name);
        if (s === target) exact.push(full);
        else if (s.includes(target) || (s.length >= 4 && target.includes(s))) partial.push(full);
        walk(full, depth + 1);
      }
    };
    for (const root of ctx.cfg.allowedRoots) walk(confine(root, ctx.cfg.allowedRoots), 0);
    if (!exact.length && !partial.length) return `No folder named like "${i.name}" in the allowed folders.`;
    const lines = [...exact.map((p) => `exact: ${p}`), ...partial.slice(0, 20).map((p) => `similar: ${p}`)];
    return clip(lines.join("\n"));
  },
});

export const searchFiles = defineTool({
  name: "search_files",
  description: "Find files by name or content with Spotlight, inside the allowed folders.",
  input: z.object({
    query: z.string().min(1).max(200),
    folder: z.string().optional().describe("Limit to this folder (defaults to all allowed folders)"),
  }),
  effects: () => ["read_local"],
  preview: (i) => `Search for “${i.query}”${i.folder ? ` in ${i.folder}` : ""}`,
  check: (i, cfg) => (i.folder ? confined(i.folder, cfg) : null),
  async run(i, ctx) {
    const folders = i.folder ? [confine(i.folder, ctx.cfg.allowedRoots)] : ctx.cfg.allowedRoots;
    const args = [...folders.flatMap((f) => ["-onlyin", f]), i.query];
    const r = await runProcess("/usr/bin/mdfind", args, { cwd: "/", timeoutMs: 20_000, signal: ctx.signal });
    const lines = r.output.split("\n").filter(Boolean).filter((p) => !p.includes("/node_modules/") && !p.includes("/."));
    return lines.length ? clip(lines.slice(0, 50).join("\n")) : "No matches.";
  },
});

export const readFile = defineTool({
  name: "read_file",
  description: "Read a text file (inside the allowed folders). Large files are truncated.",
  input: z.object({ path: z.string() }),
  effects: () => ["read_local"],
  preview: (i) => `Read ${i.path}`,
  check: (i, cfg) => confined(i.path, cfg),
  async run(i, ctx) {
    const file = confine(i.path, ctx.cfg.allowedRoots);
    if (statSync(file).size > 2_000_000) return "File is larger than 2 MB; not read.";
    return clip(readFileSync(file, "utf8"));
  },
});

/** Compact line diff for the approval card: what changes, not the whole file. */
export function lineDiff(before: string, after: string, context = 2, maxLines = 60): string {
  const a = before.split("\n");
  const b = after.split("\n");
  let start = 0;
  while (start < a.length && start < b.length && a[start] === b[start]) start++;
  let endA = a.length - 1;
  let endB = b.length - 1;
  while (endA >= start && endB >= start && a[endA] === b[endB]) { endA--; endB--; }
  const out: string[] = [];
  for (let k = Math.max(0, start - context); k < start; k++) out.push(`  ${a[k]}`);
  for (let k = start; k <= endA; k++) out.push(`- ${a[k]}`);
  for (let k = start; k <= endB; k++) out.push(`+ ${b[k]}`);
  for (let k = endA + 1; k <= Math.min(a.length - 1, endA + context); k++) out.push(`  ${a[k]}`);
  if (out.length > maxLines) return [...out.slice(0, maxLines), `… ${out.length - maxLines} more lines`].join("\n");
  return out.join("\n");
}

export const writeFile = defineTool({
  name: "write_file",
  description: "Create or overwrite a text file (inside the allowed folders). The user sees the diff and must approve.",
  input: z.object({ path: z.string(), content: z.string().max(500_000) }),
  effects: () => ["write_local"],
  preview(i, cfg) {
    let file = i.path;
    try { file = confine(i.path, cfg.allowedRoots); } catch { /* check() reports it */ }
    if (!existsSync(file)) return `Create ${file}:\n${lineDiff("", i.content)}`;
    return `Change ${file}:\n${lineDiff(readFileSync(file, "utf8"), i.content)}`;
  },
  check: (i, cfg) => confined(i.path, cfg),
  async run(i, ctx) {
    const file = confine(i.path, ctx.cfg.allowedRoots);
    mkdirSync(path.dirname(file), { recursive: true });
    writeFileSync(file, i.content, "utf8");
    return `Wrote ${file} (${i.content.length} characters).`;
  },
});

export const runShell = defineTool({
  name: "run_shell",
  description:
    "Run a shell command in a folder (inside the allowed folders). Only allowlisted programs; no redirection, " +
    "substitution or sudo. The user sees the exact command and must approve. Output is truncated.",
  input: z.object({
    command: z.string().min(1).max(2_000),
    cwd: z.string().describe("Working folder"),
  }),
  effects(i) {
    const fx: ("execute_process" | "network_write")[] = ["execute_process"];
    if (/\bgit\s+push\b/.test(i.command)) fx.push("network_write");
    return fx;
  },
  preview: (i) => `In ${i.cwd}, run:\n$ ${i.command}`,
  check(i, cfg) {
    const v = checkCommand(i.command, cfg.shellAllowlist);
    if (!v.ok) return v.reason;
    return confined(i.cwd, cfg) ?? shellPathsConfined(i.command, cfg);
  },
  async run(i, ctx) {
    const cwd = confine(i.cwd, ctx.cfg.allowedRoots);
    const r = await runProcess("/bin/bash", ["-c", i.command], { cwd, timeoutMs: 120_000, signal: ctx.signal });
    const status = r.cancelled ? "cancelled" : r.timedOut ? "timed out after 120 s" : `exit code ${r.code}`;
    return clip(`(${status})\n${r.output}`);
  },
});

export const claudeCodeTask = defineTool({
  name: "claude_code_task",
  description:
    "Delegate a coding task to Claude Code (headless) in a repository inside the allowed folders. It may edit " +
    "files in that repo but cannot run shell commands. Use for multi-file code changes; give a complete, " +
    "self-contained instruction. The user must approve.",
  input: z.object({
    repo: z.string().describe("Repository folder"),
    instruction: z.string().min(10).max(8_000),
  }),
  effects: () => ["execute_process", "write_local"],
  preview: (i) => `Claude Code in ${i.repo} (may edit files there, no shell):\n${i.instruction}`,
  check: (i, cfg) => confined(i.repo, cfg) ?? (existsSync(cfg.claudePath) ? null : `Claude Code not found at ${cfg.claudePath}`),
  async run(i, ctx) {
    const repo = confine(i.repo, ctx.cfg.allowedRoots);
    // acceptEdits: file edits in the repo need no further prompts. Shell and web tools are explicitly
    // disallowed, regardless of what your Claude Code settings would otherwise permit.
    const r = await runProcess(
      ctx.cfg.claudePath,
      ["-p", i.instruction, "--permission-mode", "acceptEdits", "--output-format", "text",
       "--disallowedTools", "Bash", "WebFetch", "WebSearch"],
      { cwd: repo, timeoutMs: 20 * 60_000, signal: ctx.signal },
    );
    const status = r.cancelled ? "cancelled" : r.timedOut ? "timed out after 20 min" : `exit code ${r.code}`;
    return clip(`Claude Code finished (${status}):\n${r.output}`, 8_000);
  },
});

export const ALL_TOOLS: ToolContract[] = [
  openApp, openUrl, listDir, findFolders, findFiles, searchFiles, readFile, writeFile, runShell, claudeCodeTask,
] as ToolContract[];
