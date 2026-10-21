// Which edges a person may draw: the rules of Hakushi.Rules, the same as
// the server's, and the types of the handles. Pure functions.

import type { EdgeModel, End, Handle, Rules } from "./types";

export type Refusal = "loop" | "duplicate" | "cycle" | "type" | "full" | "kind";

/**
 * Whether an edge from `source` (its handle `sourceHandle`) to `target`
 * (`targetHandle`) may be drawn, among `edges`. Gives null when it may,
 * or the reason.
 */
export function check(
  rules: Rules,
  edges: Iterable<EdgeModel>,
  source: End,
  sourceHandle: Handle | null,
  target: End,
  targetHandle: Handle | null,
): Refusal | null {
  if (sourceHandle && sourceHandle.kind === "target") return "kind";
  if (targetHandle && targetHandle.kind === "source") return "kind";
  if (!rules.loops && source.node === target.node) return "loop";
  if (targetHandle?.accepts && !(sourceHandle?.type && targetHandle.accepts.includes(sourceHandle.type))) return "type";

  const list = [...edges];
  if (
    !rules.duplicates &&
    list.some(
      (e) =>
        e.source === source.node &&
        e.target === target.node &&
        (e.sourceHandle ?? null) === source.handle &&
        (e.targetHandle ?? null) === target.handle,
    )
  )
    return "duplicate";

  if (sourceHandle?.max != null && count(list, source.node, source.handle) >= sourceHandle.max) return "full";
  if (targetHandle?.max != null && count(list, target.node, target.handle) >= targetHandle.max) return "full";
  if (!rules.cycles && path(list, target.node, source.node)) return "cycle";
  return null;
}

// The edges at a handle of a node, at either end.
function count(edges: EdgeModel[], node: string, handle: string | null): number {
  let n = 0;
  for (const e of edges) {
    if (e.source === node && (e.sourceHandle ?? null) === handle) n++;
    if (e.target === node && (e.targetHandle ?? null) === handle) n++;
  }
  return n;
}

/** Whether the edges lead from `from` to `to`. */
export function path(edges: EdgeModel[], from: string, to: string): boolean {
  if (from === to) return true;
  const out = new Map<string, string[]>();
  for (const e of edges) {
    const list = out.get(e.source);
    if (list) list.push(e.target);
    else out.set(e.source, [e.target]);
  }
  const seen = new Set([from]);
  const stack = [from];
  while (stack.length) {
    const node = stack.pop()!;
    for (const next of out.get(node) ?? []) {
      if (next === to) return true;
      if (!seen.has(next)) {
        seen.add(next);
        stack.push(next);
      }
    }
  }
  return false;
}
