/**
 * What a tool step can do to your machine or the world (PLAN.md §8.3). Every tool declares its
 * effects for a given input; the policy decides from effects alone, so a new tool can't silently
 * skip confirmation. Same idea as rea's `toolEffects.ts`.
 */
export type Effect =
  | "read_local" // read files / list folders / search
  | "launch_app" // open an app
  | "open_url" // open a web page in the browser
  | "write_local" // create or change files
  | "execute_process" // run a command or program
  | "network_write" // push, publish, post
  | "send_message" // email, chat, etc.
  | "delete_local"
  | "spend_money"
  | "system_settings";

export type Decision =
  | { kind: "auto" }
  | { kind: "confirm" }
  | { kind: "block"; reason: string };

/** Never allowed from a spoken task, approval or not. */
const BLOCKED: ReadonlySet<Effect> = new Set(["delete_local", "spend_money", "system_settings"]);
/** Allowed only after you click Approve for this exact step. */
const CONFIRM: ReadonlySet<Effect> = new Set(["write_local", "execute_process", "network_write", "send_message"]);
/** Click-only: these can't be approved by voice (when voice approval exists). */
export const CLICK_ONLY: ReadonlySet<Effect> = new Set(["send_message", "spend_money", "delete_local", "network_write"]);

export function decide(effects: readonly Effect[]): Decision {
  const blocked = effects.find((e) => BLOCKED.has(e));
  if (blocked) return { kind: "block", reason: `${blocked} is never allowed from a spoken task` };
  if (effects.some((e) => CONFIRM.has(e))) return { kind: "confirm" };
  return { kind: "auto" };
}

/** How the approval card should look: "read" steps need no card at all. */
export type Risk = "read" | "low" | "medium" | "high" | "blocked";

export function riskOf(effects: readonly Effect[]): Risk {
  if (effects.some((e) => BLOCKED.has(e))) return "blocked";
  if (effects.some((e) => e === "network_write" || e === "send_message")) return "high";
  if (effects.includes("execute_process")) return "medium";
  if (effects.includes("write_local")) return "low";
  return "read";
}
