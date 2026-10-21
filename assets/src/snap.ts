// Where a moved box lands: on the grid, or lined up with the boxes near it
// (the helper lines). Pure functions.

import type { Rect } from "./types";

export function snapToGrid(value: number, grid: number): number {
  return grid > 0 ? Math.round(value / grid) * grid : value;
}

/** A helper line: a vertical line at `x` (from `from` to `to` in y), or a horizontal one at `y`. */
export interface Guide {
  axis: "x" | "y";
  at: number;
  from: number;
  to: number;
}

export interface Alignment {
  /** How far to move the box to line it up. */
  dx: number;
  dy: number;
  guides: Guide[];
}

/**
 * Lines up `box` with the `others`: its left, middle or right with
 * theirs, and its top, middle or bottom with theirs, when one is within
 * `threshold` (in canvas units). The nearest wins on each axis.
 */
export function align(box: Rect, others: Rect[], threshold: number): Alignment {
  const xs = [box.x, box.x + box.width / 2, box.x + box.width];
  const ys = [box.y, box.y + box.height / 2, box.y + box.height];
  let bestX: { d: number; at: number } | null = null;
  let bestY: { d: number; at: number } | null = null;

  for (const o of others) {
    const oxs = [o.x, o.x + o.width / 2, o.x + o.width];
    const oys = [o.y, o.y + o.height / 2, o.y + o.height];
    for (const x of xs) {
      for (const ox of oxs) {
        const d = ox - x;
        if (Math.abs(d) <= threshold && (!bestX || Math.abs(d) < Math.abs(bestX.d))) bestX = { d, at: ox };
      }
    }
    for (const y of ys) {
      for (const oy of oys) {
        const d = oy - y;
        if (Math.abs(d) <= threshold && (!bestY || Math.abs(d) < Math.abs(bestY.d))) bestY = { d, at: oy };
      }
    }
  }

  const dx = bestX ? bestX.d : 0;
  const dy = bestY ? bestY.d : 0;
  const moved = { x: box.x + dx, y: box.y + dy, width: box.width, height: box.height };
  const guides: Guide[] = [];

  // Each line runs from the moved box to the farthest box it lines up with.
  if (bestX) {
    const at = bestX.at;
    let from = moved.y;
    let to = moved.y + moved.height;
    for (const o of others) {
      if ([o.x, o.x + o.width / 2, o.x + o.width].some((v) => Math.abs(v - at) < 0.5)) {
        from = Math.min(from, o.y);
        to = Math.max(to, o.y + o.height);
      }
    }
    guides.push({ axis: "x", at, from, to });
  }
  if (bestY) {
    const at = bestY.at;
    let from = moved.x;
    let to = moved.x + moved.width;
    for (const o of others) {
      if ([o.y, o.y + o.height / 2, o.y + o.height].some((v) => Math.abs(v - at) < 0.5)) {
        from = Math.min(from, o.x);
        to = Math.max(to, o.x + o.width);
      }
    }
    guides.push({ axis: "y", at, from, to });
  }
  return { dx, dy, guides };
}
