import { existsSync, mkdirSync, readFileSync, readdirSync, renameSync, rmdirSync, statSync, unlinkSync, writeFileSync } from "node:fs";
import path from "node:path";
import { z } from "zod";
import type { AgentConfig } from "../config.js";
import { confine, existingPath, PathOutsideRootsError } from "../paths.js";
import { defineTool, tilde } from "./contract.js";

/**
 * Tidying folders by voice ("organize my desktop"): one approval for the whole batch of moves, shown
 * grouped by destination; never overwrites and never deletes anything with content (it can remove
 * folders that are empty); the last batch can be put back with undo_organize.
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
    const found = existingPath(from);
    if (!found) { problems.push(`${tilde(from)} doesn't exist`); continue; }
    from = found;
    const to = path.join(toFolder, path.basename(from));
    if (cfg.allowedRoots.some((r) => confineQuiet(r, cfg) === from)) problems.push(`${tilde(from)} is an allowed folder itself`);
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

/** Folders that are empty (Finder's .DS_Store aside) and not an allowed folder itself. */
function planRemovals(folders: string[], cfg: AgentConfig): { remove: string[]; problems: string[] } {
  const remove: string[] = [];
  const problems: string[] = [];
  for (const f of folders) {
    let dir: string | null;
    try { dir = existingPath(confine(f, cfg.allowedRoots)); } catch (e) {
      problems.push(e instanceof PathOutsideRootsError ? e.message : String(e));
      continue;
    }
    if (!dir) { problems.push(`${tilde(f)} doesn't exist`); continue; }
    if (cfg.allowedRoots.some((r) => confineQuiet(r, cfg) === dir)) { problems.push(`${tilde(dir)} is an allowed folder itself`); continue; }
    let entries: string[];
    try {
      if (!statSync(dir).isDirectory()) { problems.push(`${tilde(dir)} is not a folder`); continue; }
      entries = readdirSync(dir).filter((n) => n !== ".DS_Store");
    } catch (e) { problems.push(String(e)); continue; }
    if (entries.length) problems.push(`${path.basename(dir)} is not empty (kept)`);
    else if (!remove.includes(dir)) remove.push(dir);
  }
  return { remove, problems };
}

function removeEmpty(dir: string): void {
  if (existsSync(path.join(dir, ".DS_Store"))) unlinkSync(path.join(dir, ".DS_Store"));
  rmdirSync(dir);
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

type UndoRecord = { moves: { from: string; to: string }[]; createdFolders: string[]; removedFolders?: string[] };

export const organizeFiles = defineTool({
  name: "organize_files",
  description:
    "Move files and folders into folders, in one batch the user approves once: tidying the Desktop or " +
    "Downloads, grouping by kind, project or date. Destination folders are created if missing. Never " +
    "overwrites and never deletes anything with content; it can also remove EMPTY folders (e.g. leftover " +
    "\"untitled folder\"s). The batch can be reversed with undo_organize. List the folder first, then send " +
    "every move and removal in ONE call.",
  input: z.object({
    moves: z.array(move).max(500).default([]),
    removeEmptyFolders: z.array(z.string()).max(100).default([]).describe("Empty folders to remove; non-empty ones are kept"),
  }),
  effects: () => ["write_local"],
  title(i, cfg) {
    const { planned } = planMoves(i.moves, cfg);
    const { remove } = planRemovals(i.removeEmptyFolders, cfg);
    const first = planned[0]?.from ?? remove[0];
    const where = first ? ` in ${path.basename(path.dirname(first))}` : "";
    const parts: string[] = [];
    if (planned.length || !remove.length) parts.push(`${planned.length} item${planned.length === 1 ? "" : "s"}`);
    if (remove.length) parts.push(`${remove.length} empty folder${remove.length === 1 ? "" : "s"}`);
    return `Organize ${parts.join(" and ")}${where}`;
  },
  preview(i, cfg) {
    const { planned, problems: moveProblems } = planMoves(i.moves, cfg);
    const { remove, problems: removeProblems } = planRemovals(i.removeEmptyFolders, cfg);
    const problems = [...moveProblems, ...removeProblems];
    const lines: string[] = [];
    if (planned.length) lines.push(`Move ${planned.length} item(s), nothing overwritten (undo with “undo that”):`, ...describeMoves(planned));
    if (remove.length) lines.push(`Remove ${remove.length} empty folder(s): ${remove.map((d) => path.basename(d)).join(", ")}`);
    if (problems.length) lines.push(`Skipped: ${problems.slice(0, 5).join("; ")}${problems.length > 5 ? "; …" : ""}`);
    return lines.join("\n");
  },
  check(i, cfg) {
    const { planned, problems } = planMoves(i.moves, cfg);
    const { remove, problems: rp } = planRemovals(i.removeEmptyFolders, cfg);
    if (planned.length || remove.length) return null;
    return `nothing to do: ${[...problems, ...rp].join("; ") || "everything is already in place"}`;
  },
  async run(i, ctx) {
    const { planned, problems } = planMoves(i.moves, ctx.cfg);
    const { remove, problems: removeProblems } = planRemovals(i.removeEmptyFolders, ctx.cfg);
    problems.push(...removeProblems);
    const done: UndoRecord = { moves: [], createdFolders: [], removedFolders: [] };
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
    for (const dir of remove) {
      // Re-checked at the last moment: something may have landed in it since the preview.
      try {
        if (readdirSync(dir).some((n) => n !== ".DS_Store")) { failed.push(`${path.basename(dir)} is no longer empty`); continue; }
        removeEmpty(dir);
        done.removedFolders!.push(dir);
      } catch (e) {
        failed.push(`${path.basename(dir)}: ${e instanceof Error ? e.message : String(e)}`);
      }
    }
    if (done.moves.length || done.removedFolders!.length) {
      mkdirSync(path.dirname(undoFile(ctx.cfg)), { recursive: true });
      writeFileSync(undoFile(ctx.cfg), JSON.stringify(done), { mode: 0o600 });
    }
    const removed = done.removedFolders!.length ? ` Removed ${done.removedFolders!.length} empty folder(s).` : "";
    const out = [`Moved ${done.moves.length} item(s).${removed}`, ...describeMoves(done.moves.map((m) => ({ from: m.from, toFolder: path.dirname(m.to) })), 3)];
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
    if (rec.removedFolders?.length) lines.push(`Recreate: ${rec.removedFolders.map((d) => path.basename(d)).join(", ")}`);
    return lines.join("\n");
  },
  check: (_i, cfg) => (readUndo(cfg) ? null : "there is no organize to undo"),
  async run(_i, ctx) {
    const rec = readUndo(ctx.cfg);
    if (!rec) return "Nothing to undo.";
    let back = 0;
    const problems: string[] = [];
    let recreated = 0;
    for (const dir of rec.removedFolders ?? []) {
      try {
        confine(dir, ctx.cfg.allowedRoots);
        if (!existsSync(dir)) { mkdirSync(dir, { recursive: true }); recreated++; }
      } catch (e) {
        problems.push(`${path.basename(dir)}: ${e instanceof Error ? e.message : String(e)}`);
      }
    }
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
          removeEmpty(dir);
          removed++;
        }
      } catch { /* leave it */ }
    }
    unlinkSync(undoFile(ctx.cfg));
    const out = [`Put back ${back} item(s)${removed ? ` and removed ${removed} empty folder(s)` : ""}${recreated ? `; recreated ${recreated} folder(s)` : ""}.`];
    if (problems.length) out.push(`Not put back: ${problems.join("; ")}`);
    return out.join("\n");
  },
});
