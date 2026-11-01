import { existsSync, mkdirSync, readFileSync, readdirSync, renameSync, rmdirSync, statSync, unlinkSync, writeFileSync } from "node:fs";
import path from "node:path";
import { z } from "zod";
import type { AgentConfig } from "../config.js";
import { confine, PathOutsideRootsError } from "../paths.js";
import { defineTool, tilde } from "./contract.js";

/**
 * Tidying folders by voice ("organize my desktop"): one approval for the whole batch of moves, shown
 * grouped by destination; never overwrites, never deletes; the last batch can be put back with
 * undo_organize.
 */

const move = z.object({
  from: z.string().describe("File or folder to move"),
  toFolder: z.string().describe("Folder to move it into (created if missing); the name is kept"),
});

type Planned = { from: string; to: string; toFolder: string; newFolder: boolean };

/** Resolves each move and the reason it can't happen, without touching the disk. */
function planMoves(moves: z.infer<typeof move>[], cfg: AgentConfig): { planned: Planned[]; problems: string[] } {
  const planned: Planned[] = [];
  const problems: string[] = [];
  const targets = new Set<string>();
  for (const m of moves) {
    let from: string, toFolder: string;
    try {
      from = confine(m.from, cfg.allowedRoots);
      toFolder = confine(m.toFolder, cfg.allowedRoots);
    } catch (e) {
      problems.push(e instanceof PathOutsideRootsError ? e.message : String(e));
      continue;
    }
    const to = path.join(toFolder, path.basename(from));
    if (!existsSync(from)) problems.push(`${tilde(from)} doesn't exist`);
    else if (cfg.allowedRoots.some((r) => confineQuiet(r, cfg) === from)) problems.push(`${tilde(from)} is an allowed folder itself`);
    else if (toFolder === from || toFolder.startsWith(from + path.sep)) problems.push(`can't move ${path.basename(from)} into itself`);
    else if (path.dirname(from) === toFolder) continue; // already there
    else if (existsSync(to) || targets.has(to)) problems.push(`${tilde(to)} already exists (not overwritten)`);
    else {
      targets.add(to);
      planned.push({ from, to, toFolder, newFolder: !existsSync(toFolder) });
    }
  }
  return { planned, problems };
}

function confineQuiet(p: string, cfg: AgentConfig): string | null {
  try { return confine(p, cfg.allowedRoots); } catch { return null; }
}

/** "Screenshots/ (new): a.png, b.png, +3 more" per destination. */
function describeMoves(planned: { from: string; toFolder: string; newFolder?: boolean }[], perFolder = 6): string[] {
  const groups = new Map<string, { names: string[]; isNew: boolean }>();
  for (const p of planned) {
    const g = groups.get(p.toFolder) ?? { names: [], isNew: !!p.newFolder };
    g.names.push(path.basename(p.from));
    groups.set(p.toFolder, g);
  }
  return [...groups].map(([folder, g]) => {
    const shown = g.names.slice(0, perFolder).join(", ");
    const more = g.names.length > perFolder ? `, +${g.names.length - perFolder} more` : "";
    return `→ ${tilde(folder)}/${g.isNew ? " (new)" : ""}: ${shown}${more}`;
  });
}

/** Where the last batch is remembered for undo: next to the audit log, outside the allowed folders. */
export function undoFile(cfg: AgentConfig): string {
  return path.join(path.dirname(cfg.auditPath), ".last-organize.json");
}

type UndoRecord = { moves: { from: string; to: string }[]; createdFolders: string[] };

export const organizeFiles = defineTool({
  name: "organize_files",
  description:
    "Move files and folders into folders, in one batch the user approves once: tidying the Desktop or " +
    "Downloads, grouping by kind, project or date. Destination folders are created if missing. Never " +
    "overwrites and never deletes; the batch can be reversed with undo_organize. List the folder first, " +
    "then send every move in ONE call.",
  input: z.object({ moves: z.array(move).min(1).max(500) }),
  effects: () => ["write_local"],
  title(i, cfg) {
    const { planned } = planMoves(i.moves, cfg);
    const where = planned[0] ? path.basename(path.dirname(planned[0].from)) : "";
    return `Organize ${planned.length} item${planned.length === 1 ? "" : "s"}${where ? ` in ${where}` : ""}`;
  },
  preview(i, cfg) {
    const { planned, problems } = planMoves(i.moves, cfg);
    const lines = [`Move ${planned.length} item(s), nothing overwritten or deleted (undo with “undo that”):`,
      ...describeMoves(planned)];
    if (problems.length) lines.push(`Skipped: ${problems.slice(0, 5).join("; ")}${problems.length > 5 ? "; …" : ""}`);
    return lines.join("\n");
  },
  check(i, cfg) {
    const { planned, problems } = planMoves(i.moves, cfg);
    return planned.length ? null : `nothing to move: ${problems.join("; ") || "everything is already in place"}`;
  },
  async run(i, ctx) {
    const { planned, problems } = planMoves(i.moves, ctx.cfg);
    const done: UndoRecord = { moves: [], createdFolders: [] };
    const failed: string[] = [];
    for (const p of planned) {
      if (ctx.signal.aborted) break;
      try {
        if (!existsSync(p.toFolder)) {
          mkdirSync(p.toFolder, { recursive: true });
          done.createdFolders.push(p.toFolder);
        }
        if (existsSync(p.to)) { failed.push(`${tilde(p.to)} appeared meanwhile`); continue; }
        renameSync(p.from, p.to);
        done.moves.push({ from: p.from, to: p.to });
      } catch (e) {
        failed.push(`${path.basename(p.from)}: ${e instanceof Error ? e.message : String(e)}`);
      }
    }
    if (done.moves.length) {
      mkdirSync(path.dirname(undoFile(ctx.cfg)), { recursive: true });
      writeFileSync(undoFile(ctx.cfg), JSON.stringify(done), { mode: 0o600 });
    }
    const out = [`Moved ${done.moves.length} item(s).`, ...describeMoves(done.moves.map((m) => ({ from: m.from, toFolder: path.dirname(m.to) })), 3)];
    const skipped = [...problems, ...failed];
    if (skipped.length) out.push(`Not moved: ${skipped.join("; ")}`);
    return out.join("\n");
  },
});

function readUndo(cfg: AgentConfig): UndoRecord | null {
  try { return JSON.parse(readFileSync(undoFile(cfg), "utf8")) as UndoRecord; } catch { return null; }
}

export const undoOrganize = defineTool({
  name: "undo_organize",
  description: "Put back everything the last organize_files call moved, and remove the folders it created if they are empty again.",
  input: z.object({}),
  effects: () => ["write_local"],
  title: () => "Undo the last organize",
  preview(_i, cfg) {
    const rec = readUndo(cfg);
    if (!rec) return "Nothing to undo.";
    const back = rec.moves.map((m) => ({ from: m.to, toFolder: path.dirname(m.from) }));
    const lines = [`Put back ${rec.moves.length} item(s):`, ...describeMoves(back)];
    if (rec.createdFolders.length) lines.push(`Then remove these folders if empty: ${rec.createdFolders.map(tilde).join(", ")}`);
    return lines.join("\n");
  },
  check: (_i, cfg) => (readUndo(cfg) ? null : "there is no organize to undo"),
  async run(_i, ctx) {
    const rec = readUndo(ctx.cfg);
    if (!rec) return "Nothing to undo.";
    let back = 0;
    const problems: string[] = [];
    for (const m of [...rec.moves].reverse()) {
      try {
        confine(m.to, ctx.cfg.allowedRoots);
        confine(m.from, ctx.cfg.allowedRoots);
        if (!existsSync(m.to)) { problems.push(`${path.basename(m.to)} is no longer in ${tilde(path.dirname(m.to))}`); continue; }
        if (existsSync(m.from)) { problems.push(`${tilde(m.from)} exists again (not overwritten)`); continue; }
        renameSync(m.to, m.from);
        back++;
      } catch (e) {
        problems.push(`${path.basename(m.to)}: ${e instanceof Error ? e.message : String(e)}`);
      }
    }
    let removed = 0;
    for (const dir of rec.createdFolders) {
      // Only folders this batch created, and only when empty (ignoring Finder's .DS_Store).
      try {
        const left = readdirSync(dir).filter((n) => n !== ".DS_Store");
        if (left.length === 0 && statSync(dir).isDirectory()) {
          if (existsSync(path.join(dir, ".DS_Store"))) unlinkSync(path.join(dir, ".DS_Store"));
          rmdirSync(dir);
          removed++;
        }
      } catch { /* leave it */ }
    }
    unlinkSync(undoFile(ctx.cfg));
    const out = [`Put back ${back} item(s)${removed ? ` and removed ${removed} empty folder(s)` : ""}.`];
    if (problems.length) out.push(`Not put back: ${problems.join("; ")}`);
    return out.join("\n");
  },
});
