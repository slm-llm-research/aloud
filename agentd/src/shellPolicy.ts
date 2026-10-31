/**
 * Which shell commands a spoken task may run (PLAN.md §8.3). Every command is also shown to you
 * for approval; this is the layer that refuses dangerous ones outright, whatever you click.
 *
 * Deliberately conservative: no command substitution, no redirection (use write_file), and every
 * program in a pipeline/chain must be on the allowlist.
 */

export type ShellVerdict = { ok: true; programs: string[] } | { ok: false; reason: string };

export const DEFAULT_SHELL_ALLOWLIST = [
  "git", "ls", "cat", "head", "tail", "wc", "grep", "rg", "find", "pwd", "echo", "which", "date",
  "npm", "npx", "pnpm", "yarn", "node", "python3", "python", "uv", "pytest", "swift", "make", "open",
  "tree", "du", "diff", "sort", "uniq",
];

type Token = { kind: "word"; text: string } | { kind: "op"; text: string };

function tokenize(cmd: string): Token[] | string {
  const tokens: Token[] = [];
  let word = "";
  let quote: '"' | "'" | null = null;
  let hasWord = false;
  const flush = () => {
    if (hasWord) tokens.push({ kind: "word", text: word });
    word = "";
    hasWord = false;
  };
  for (let i = 0; i < cmd.length; i++) {
    const c = cmd[i]!;
    if (quote) {
      if (c === quote) quote = null;
      else word += c;
      continue;
    }
    if (c === '"' || c === "'") {
      quote = c;
      hasWord = true;
      continue;
    }
    if (c === "\\") {
      word += cmd[++i] ?? "";
      hasWord = true;
      continue;
    }
    if (c === " " || c === "\t") {
      flush();
      continue;
    }
    if (c === "&" && cmd[i + 1] === "&") { flush(); tokens.push({ kind: "op", text: "&&" }); i++; continue; }
    if (c === "|" && cmd[i + 1] === "|") { flush(); tokens.push({ kind: "op", text: "||" }); i++; continue; }
    if (c === "|" || c === ";") { flush(); tokens.push({ kind: "op", text: c }); continue; }
    if (c === "&") return "background jobs (&) are not allowed";
    if (c === ">" || c === "<") return "redirection (> <) is not allowed; use write_file / read_file";
    word += c;
    hasWord = true;
  }
  if (quote) return "unbalanced quotes";
  flush();
  return tokens;
}

/** Specific dangerous forms of otherwise-allowed programs. */
function dangerous(program: string, args: string[]): string | null {
  const has = (...flags: string[]) => args.some((a) => flags.includes(a));
  if (program === "git") {
    const sub = args.find((a) => !a.startsWith("-"));
    if (sub === "push" && (has("--force", "-f", "--force-with-lease", "--mirror", "--delete") || args.some((a) => a.startsWith("+"))))
      return "force-pushing or deleting remote branches is not allowed";
    if (sub === "reset" && has("--hard")) return "git reset --hard discards work and is not allowed";
    if (sub === "clean") return "git clean deletes files and is not allowed";
    if (sub === "checkout" && has("--", ".")) return "discarding changes with git checkout is not allowed";
    if (sub === "branch" && has("-D", "--delete", "-d")) return "deleting branches is not allowed";
    if (sub === "config" && has("--global", "--system")) return "changing global git config is not allowed";
  }
  if (program === "find" && has("-delete", "-exec", "-execdir", "-ok", "-okdir"))
    return "find with -delete/-exec is not allowed";
  if (["npm", "pnpm", "yarn"].includes(program) && args.some((a) => ["publish", "unpublish", "deprecate", "owner", "token", "adduser", "login"].includes(a)))
    return `${program} ${args.join(" ")} is not allowed`;
  if ((program === "npm" || program === "pnpm" || program === "yarn") && has("-g", "--global"))
    return "global installs are not allowed";
  if (program === "open" && args.some((a) => /\.(command|sh|tool|app|pkg|dmg)\/?$/i.test(a)))
    return "opening scripts, installers or apps by path is not allowed; use open_app";
  return null;
}

export function checkCommand(command: string, allowlist: readonly string[] = DEFAULT_SHELL_ALLOWLIST): ShellVerdict {
  const cmd = command.trim();
  if (!cmd) return { ok: false, reason: "empty command" };
  if (/[\n\r]/.test(cmd)) return { ok: false, reason: "multi-line commands are not allowed" };
  if (cmd.includes("`") || cmd.includes("$(") || cmd.includes("<(") || cmd.includes(">("))
    return { ok: false, reason: "command substitution is not allowed" };
  if (/\$\{?[A-Za-z_]/.test(cmd)) return { ok: false, reason: "shell variables are not allowed" };

  const tokens = tokenize(cmd);
  if (typeof tokens === "string") return { ok: false, reason: tokens };

  // Split into simple commands at && || ; |
  const segments: string[][] = [[]];
  for (const t of tokens) {
    if (t.kind === "op") segments.push([]);
    else segments[segments.length - 1]!.push(t.text);
  }
  const programs: string[] = [];
  for (const seg of segments) {
    // Leading VAR=value assignments are not allowed either (they can redirect tools, e.g. GIT_SSH).
    if (seg.length === 0) return { ok: false, reason: "empty command in chain" };
    const [first, ...args] = seg;
    if (first!.includes("=")) return { ok: false, reason: "environment assignments are not allowed" };
    if (first === "sudo" || args.includes("sudo")) return { ok: false, reason: "sudo is never allowed" };
    const program = first!.split("/").pop()!;
    if (first!.includes("/")) return { ok: false, reason: `run programs by name, not path (${first})` };
    if (!allowlist.includes(program)) return { ok: false, reason: `${program} is not on the allowed command list` };
    const danger = dangerous(program, args);
    if (danger) return { ok: false, reason: danger };
    programs.push(program);
  }
  return { ok: true, programs };
}
