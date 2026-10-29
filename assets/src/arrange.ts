// Nodes lined up or spaced out: by their left sides, their middles or
// their right sides (and top, middle, bottom), or with equal gaps between
// them. Pure functions.

import type { Point } from "./types";

/** How boxes are lined up (align) or spaced out (horizontal, vertical: distribute). */
export type Arrangement = "left" | "center" | "right" | "top" | "middle" | "bottom" | "horizontal" | "vertical";

export const arrangements: Arrangement[] = ["left", "center", "right", "top", "middle", "bottom", "horizontal", "vertical"];

export interface Box {
  id: string;
  x: number;
  y: number;
  width: number;
  height: number;
}

/**
 * Where each box goes. Aligned, the boxes meet the side (or the middle)
 * of the box around them all; distributed, the first and the last stay,
 * and the others go between them with equal gaps, in the order they are
 * on that axis. Lining up takes two boxes, spacing out three; with fewer,
 * nothing moves.
 */
export function arrange(boxes: Box[], how: Arrangement): Map<string, Point> {
  const places = new Map<string, Point>();
  if (how === "horizontal" || how === "vertical") return distribute(boxes, how);
  if (boxes.length < 2) return places;
  const left = Math.min(...boxes.map((b) => b.x));
  const right = Math.max(...boxes.map((b) => b.x + b.width));
  const top = Math.min(...boxes.map((b) => b.y));
  const bottom = Math.max(...boxes.map((b) => b.y + b.height));
  for (const b of boxes) {
    let { x, y } = b;
    if (how === "left") x = left;
    else if (how === "right") x = right - b.width;
    else if (how === "center") x = (left + right) / 2 - b.width / 2;
    else if (how === "top") y = top;
    else if (how === "bottom") y = bottom - b.height;
    else if (how === "middle") y = (top + bottom) / 2 - b.height / 2;
    places.set(b.id, { x, y });
  }
  return places;
}

function distribute(boxes: Box[], how: "horizontal" | "vertical"): Map<string, Point> {
  const places = new Map<string, Point>();
  if (boxes.length < 3) return places;
  const along = how === "horizontal" ? ("x" as const) : ("y" as const);
  const size = how === "horizontal" ? ("width" as const) : ("height" as const);
  // In the order they are along the axis: by their middles, then their ids.
  const sorted = [...boxes].sort((a, b) => a[along] + a[size] / 2 - (b[along] + b[size] / 2) || (a.id < b.id ? -1 : 1));
  const first = sorted[0];
  const last = sorted[sorted.length - 1];
  const span = last[along] + last[size] - first[along];
  const filled = sorted.reduce((sum, b) => sum + b[size], 0);
  const gap = (span - filled) / (sorted.length - 1);
  let at = first[along];
  for (const b of sorted) {
    places.set(b.id, along === "x" ? { x: at, y: b.y } : { x: b.x, y: at });
    at += b[size] + gap;
  }
  return places;
}
