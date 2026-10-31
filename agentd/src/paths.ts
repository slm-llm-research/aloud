import { realpathSync } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";

export function expandHome(p: string, home = homedir()): string {
  if (p === "~") return home;
  if (p.startsWith("~/")) return path.join(home, p.slice(2));
  return p;
}

/** realpath of the deepest existing ancestor, plus the not-yet-existing remainder. */
function realpathLenient(p: string): string {
  let current = p;
  const rest: string[] = [];
  for (;;) {
    try {
      return path.join(realpathSync(current), ...rest);
    } catch {
      const parent = path.dirname(current);
      if (parent === current) return p;
      rest.unshift(path.basename(current));
      current = parent;
    }
  }
}

export class PathOutsideRootsError extends Error {}

/**
 * Resolves a model-supplied path and requires it to be inside one of the allowed folders.
 * Symlinks are resolved first, so a link inside a root that points outside it is rejected.
 * Relative paths are taken relative to the first root.
 */
export function confine(input: string, roots: readonly string[], home = homedir()): string {
  if (roots.length === 0) throw new PathOutsideRootsError("no allowed folders are configured");
  const realRoots = roots.map((r) => realpathLenient(path.resolve(expandHome(r, home))));
  const expanded = expandHome(input.trim(), home);
  const absolute = path.isAbsolute(expanded) ? expanded : path.join(realRoots[0]!, expanded);
  const resolved = realpathLenient(path.resolve(absolute));
  const inside = realRoots.some((root) => resolved === root || resolved.startsWith(root + path.sep));
  if (!inside) {
    throw new PathOutsideRootsError(`${input} is outside the allowed folders (${roots.join(", ")})`);
  }
  return resolved;
}
