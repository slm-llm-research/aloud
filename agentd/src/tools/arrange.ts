import { z } from "zod";
import { defineTool } from "./contract.js";
import { runProcess } from "./process.js";

/**
 * Sorting the Desktop's icons ("reorder my desktop icons by kind"): Finder's View ▸ Sort By for the
 * Desktop, through AppleScript. Nothing moves on disk, so it needs no approval, and the reply names
 * the previous arrangement so it can be put back. The first run makes macOS ask whether Aloud may
 * control Finder (Privacy & Security ▸ Automation).
 */

const ORDERS = {
  name: { arrangement: "arranged by name", cleanUp: "name" },
  kind: { arrangement: "arranged by kind", cleanUp: "kind" },
  modified: { arrangement: "arranged by modification date", cleanUp: "modification date" },
  created: { arrangement: "arranged by creation date", cleanUp: "creation date" },
  size: { arrangement: "arranged by size", cleanUp: "size" },
  grid: { arrangement: "snap to grid", cleanUp: "name" },
  none: { arrangement: "not arranged", cleanUp: null },
} as const;

type Order = keyof typeof ORDERS;

const LABELS: Record<Order, string> = {
  name: "by name", kind: "by kind", modified: "by date modified", created: "by date created",
  size: "by size", grid: "to the grid", none: "back to free placement",
};

/** Sort By where Finder supports it on the Desktop; otherwise a one-off Clean Up By. */
export function arrangeScript(order: Order): string {
  const o = ORDERS[order];
  const cleanUp = o.cleanUp ? `clean up window of desktop by ${o.cleanUp}\n        return "cleaned up|" & previous` : `error e1`;
  return `tell application "Finder"
  set previous to "unknown"
  try
    set previous to (arrangement of icon view options of window of desktop) as text
  end try
  try
    set arrangement of icon view options of window of desktop to ${o.arrangement}
    return "sorted|" & previous
  on error e1 number n1
    if n1 is -1743 then error e1 number n1
    try
        ${cleanUp}
    on error e2
      error e1 & " / " & e2
    end try
  end try
end tell`;
}

export const arrangeDesktop = defineTool({
  name: "arrange_desktop",
  description:
    "Sort or reorder the icons on the Desktop (Finder's Sort By): by name, kind, date modified, date created " +
    "or size, snap them to the grid, or 'none' to stop sorting. Only changes how icons are laid out on screen; " +
    "no file moves. Use for \"reorder/arrange/sort/line up my desktop icons\".",
  input: z.object({ by: z.enum(["name", "kind", "modified", "created", "size", "grid", "none"]).default("kind") }),
  effects: () => ["arrange_view"],
  title: (i) => `Sort Desktop icons ${LABELS[i.by]}`,
  preview: (i) => `Set the Desktop's icon arrangement ${LABELS[i.by]} (Finder ▸ View ▸ Sort By)`,
  async run(i, ctx) {
    const r = await runProcess("/usr/bin/osascript", ["-e", arrangeScript(i.by)], { cwd: "/", timeoutMs: 20_000, signal: ctx.signal });
    const out = r.output.trim();
    if (r.code !== 0) {
      if (/-1743|not authori[sz]ed|Not authorised/i.test(out)) {
        return "macOS hasn't allowed Aloud to control Finder. Ask the user to open System Settings ▸ Privacy & " +
          "Security ▸ Automation, turn on Finder under Aloud, and try again.";
      }
      return `Could not arrange the Desktop: ${out}`;
    }
    const [how, previous] = out.split("|");
    const was = previous && previous !== "unknown" ? ` (it was: ${previous})` : "";
    return how === "cleaned up"
      ? `Cleaned up the Desktop icons ${LABELS[i.by]}${was}.`
      : `Desktop icons are now sorted ${LABELS[i.by]}${was}.`;
  },
});
