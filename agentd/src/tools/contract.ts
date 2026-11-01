import type { z } from "zod";
import type { AgentConfig } from "../config.js";
import type { Effect } from "../effects.js";

export interface ToolContext {
  cfg: AgentConfig;
  signal: AbortSignal;
}

/**
 * One tool = one typed contract (rea's pattern): input schema, the effects of a given input, a
 * human-readable preview for the approval card, an optional hard check, and the implementation.
 */
export interface ToolContract<S extends z.ZodType = z.ZodType> {
  name: string;
  description: string;
  input: S;
  effects(input: z.infer<S>, cfg: AgentConfig): Effect[];
  /** Exactly what will happen, shown on the approval card. */
  preview(input: z.infer<S>, cfg: AgentConfig): string;
  /** Verb + object in plain words for the timeline and card title: "Run swift test in app/". */
  title?(input: z.infer<S>, cfg: AgentConfig): string;
  /** Returns a reason to refuse outright (outside allowed folders, dangerous command...). */
  check?(input: z.infer<S>, cfg: AgentConfig): string | null;
  run(input: z.infer<S>, ctx: ToolContext): Promise<string>;
}

export function defineTool<S extends z.ZodType>(t: ToolContract<S>): ToolContract<S> {
  return t;
}

/** Caps tool output so a huge file or log can't flood the model's context. */
export function clip(text: string, max = 20_000): string {
  return text.length <= max ? text : `${text.slice(0, max)}\n… [${text.length - max} more characters truncated]`;
}

/** "/Users/me/Documents/x/y" -> "~/Documents/x/y": paths read better shortened on a small card. */
export function tilde(p: string): string {
  const home = process.env.HOME ?? "";
  return home && p.startsWith(home) ? `~${p.slice(home.length)}` : p;
}

/** First line, at most `max` characters. */
export function oneLine(s: string, max = 80): string {
  const line = s.split("\n")[0]!.trim();
  return line.length <= max ? line : `${line.slice(0, max - 1)}…`;
}
