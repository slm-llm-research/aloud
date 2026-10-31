import { spawn } from "node:child_process";

export interface ProcessResult {
  code: number | null;
  output: string;
  timedOut: boolean;
  cancelled: boolean;
}

/**
 * Runs a program in its own process group so cancel/timeout kills it *and* its children
 * (SIGTERM, then SIGKILL after 2 s). Combined stdout+stderr, capped.
 */
export function runProcess(
  file: string,
  args: string[],
  opts: { cwd: string; timeoutMs: number; signal: AbortSignal; maxBytes?: number; env?: NodeJS.ProcessEnv },
): Promise<ProcessResult> {
  const maxBytes = opts.maxBytes ?? 200_000;
  return new Promise((resolve) => {
    const child = spawn(file, args, {
      cwd: opts.cwd,
      env: opts.env ?? process.env,
      detached: true,
      stdio: ["ignore", "pipe", "pipe"],
    });
    let output = "";
    let timedOut = false;
    let cancelled = false;
    const append = (b: Buffer) => {
      if (output.length < maxBytes) output += b.toString("utf8");
    };
    child.stdout.on("data", append);
    child.stderr.on("data", append);

    const killGroup = () => {
      if (child.pid === undefined) return;
      try { process.kill(-child.pid, "SIGTERM"); } catch { /* already gone */ }
      setTimeout(() => {
        try { process.kill(-child.pid!, "SIGKILL"); } catch { /* already gone */ }
      }, 2_000).unref();
    };
    const timer = setTimeout(() => { timedOut = true; killGroup(); }, opts.timeoutMs);
    const onAbort = () => { cancelled = true; killGroup(); };
    if (opts.signal.aborted) onAbort();
    else opts.signal.addEventListener("abort", onAbort, { once: true });

    const done = (code: number | null) => {
      clearTimeout(timer);
      opts.signal.removeEventListener("abort", onAbort);
      resolve({ code, output, timedOut, cancelled });
    };
    child.on("error", (err) => { output += String(err); done(null); });
    child.on("close", (code) => done(code));
  });
}
