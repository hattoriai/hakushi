// Boxes, the points of handles, and the paths of edges. Pure functions.

import type { PathKind, Point, Rect, Side } from "./types";

export function intersects(a: Rect, b: Rect): boolean {
  return a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height;
}

export function contains(a: Rect, p: Point): boolean {
  return p.x >= a.x && p.x <= a.x + a.width && p.y >= a.y && p.y <= a.y + a.height;
}

/** The box around boxes, or null for none. */
export function union(rects: Iterable<Rect>): Rect | null {
  let x0 = Infinity;
  let y0 = Infinity;
  let x1 = -Infinity;
  let y1 = -Infinity;
  for (const r of rects) {
    x0 = Math.min(x0, r.x);
    y0 = Math.min(y0, r.y);
    x1 = Math.max(x1, r.x + r.width);
    y1 = Math.max(y1, r.y + r.height);
  }
  return x0 === Infinity ? null : { x: x0, y: y0, width: x1 - x0, height: y1 - y0 };
}

/** A box made of two corners, in any order. */
export function fromCorners(a: Point, b: Point): Rect {
  return { x: Math.min(a.x, b.x), y: Math.min(a.y, b.y), width: Math.abs(a.x - b.x), height: Math.abs(a.y - b.y) };
}

export function grow(r: Rect, by: number): Rect {
  return { x: r.x - by, y: r.y - by, width: r.width + by * 2, height: r.height + by * 2 };
}

/** The middle of a side of a box. */
export function sidePoint(r: Rect, side: Side): Point {
  switch (side) {
    case "left":
      return { x: r.x, y: r.y + r.height / 2 };
    case "right":
      return { x: r.x + r.width, y: r.y + r.height / 2 };
    case "top":
      return { x: r.x + r.width / 2, y: r.y };
    case "bottom":
      return { x: r.x + r.width / 2, y: r.y + r.height };
  }
}

/** The direction a side faces. */
export function normal(side: Side): Point {
  switch (side) {
    case "left":
      return { x: -1, y: 0 };
    case "right":
      return { x: 1, y: 0 };
    case "top":
      return { x: 0, y: -1 };
    case "bottom":
      return { x: 0, y: 1 };
  }
}

/** The side of a box that faces a point: for an end with no handle. */
export function facing(r: Rect, p: Point): Side {
  const cx = r.x + r.width / 2;
  const cy = r.y + r.height / 2;
  const dx = (p.x - cx) / Math.max(r.width, 1);
  const dy = (p.y - cy) / Math.max(r.height, 1);
  if (Math.abs(dx) >= Math.abs(dy)) return dx >= 0 ? "right" : "left";
  return dy >= 0 ? "bottom" : "top";
}

export interface EdgeGeometry {
  /** The SVG path. */
  d: string;
  /** The middle of the path, for its label. */
  label: Point;
}

const round = (n: number) => Math.round(n * 10) / 10;

/**
 * The path of an edge from `s` (leaving by `sSide`) to `t` (arriving by
 * `tSide`).
 */
export function edgePath(kind: PathKind, s: Point, sSide: Side, t: Point, tSide: Side): EdgeGeometry {
  switch (kind) {
    case "straight":
      return { d: `M${round(s.x)},${round(s.y)}L${round(t.x)},${round(t.y)}`, label: { x: (s.x + t.x) / 2, y: (s.y + t.y) / 2 } };
    case "step":
      return orthogonal(s, sSide, t, tSide, 0);
    case "smooth":
      return orthogonal(s, sSide, t, tSide, 8);
    default:
      return bezier(s, sSide, t, tSide);
  }
}

/**
 * The path of an edge through `points` it was bent to, between its ends: a
 * line through them (straight), lines along the axes by each (step, and
 * smooth with round corners), or a curve through them that leaves and
 * arrives square to its sides (bezier). Without points, edgePath's.
 */
export function edgePathThrough(kind: PathKind, s: Point, sSide: Side, points: Point[], t: Point, tSide: Side): EdgeGeometry {
  if (points.length === 0) return edgePath(kind, s, sSide, t, tSide);
  const all = [s, ...points, t];
  switch (kind) {
    case "straight":
      return { d: all.map((p, i) => `${i === 0 ? "M" : "L"}${round(p.x)},${round(p.y)}`).join(""), label: middleOf(all) };
    case "step":
    case "smooth": {
      const corners = elbows(s, sSide, points, t, tSide, 20);
      return { d: roundedPath(corners, kind === "smooth" ? 8 : 0), label: middleOf(corners) };
    }
    default:
      return spline(all, sSide, tSide);
  }
}

// Out of the source's side, to each point along the axes, and into the
// target's side. Of the two corners between two points, the one that does
// not turn back on the way it came (nor, last, on the way into the target).
function elbows(s: Point, sSide: Side, points: Point[], t: Point, tSide: Side, gap: number): Point[] {
  const sn = normal(sSide);
  const tn = normal(tSide);
  const a = { x: s.x + sn.x * gap, y: s.y + sn.y * gap };
  const b = { x: t.x + tn.x * gap, y: t.y + tn.y * gap };
  const out: Point[] = [s, a];
  const stops = [...points, b];
  stops.forEach((p, i) => {
    const from = out[out.length - 1];
    const before = out[out.length - 2];
    const came = { x: from.x - before.x, y: from.y - before.y };
    const next = i === stops.length - 1 ? { x: t.x - b.x, y: t.y - b.y } : null;
    const score = (corner: Point) => {
      const first = { x: corner.x - from.x, y: corner.y - from.y };
      const second = { x: p.x - corner.x, y: p.y - corner.y };
      let total = Math.sign(first.x * came.x + first.y * came.y);
      if (next) total += Math.sign(second.x * next.x + second.y * next.y);
      return total;
    };
    const across = { x: p.x, y: from.y };
    const along = { x: from.x, y: p.y };
    out.push(score(along) > score(across) ? along : across, p);
  });
  out.push(t);
  return simplify(out);
}

// A curve through the points (Catmull-Rom, as cubic pieces), square to the
// sides at its ends.
function spline(all: Point[], sSide: Side, tSide: Side): EdgeGeometry {
  const sn = normal(sSide);
  const tn = normal(tSide);
  let d = `M${round(all[0].x)},${round(all[0].y)}`;
  for (let i = 0; i < all.length - 1; i++) {
    const p0 = all[i];
    const p1 = all[i + 1];
    const reach = distance(p0, p1) / 3;
    const c1 = i === 0 ? { x: p0.x + sn.x * reach, y: p0.y + sn.y * reach } : { x: p0.x + (p1.x - all[i - 1].x) / 6, y: p0.y + (p1.y - all[i - 1].y) / 6 };
    const c2 = i === all.length - 2 ? { x: p1.x + tn.x * reach, y: p1.y + tn.y * reach } : { x: p1.x - (all[i + 2].x - p0.x) / 6, y: p1.y - (all[i + 2].y - p0.y) / 6 };
    d += `C${round(c1.x)},${round(c1.y)} ${round(c2.x)},${round(c2.y)} ${round(p1.x)},${round(p1.y)}`;
  }
  return { d, label: middleOf(all) };
}

// A cubic curve that leaves and arrives square to its sides, as far out as
// a quarter of the distance (more when the target is behind the source).
function bezier(s: Point, sSide: Side, t: Point, tSide: Side): EdgeGeometry {
  const c1 = control(s, sSide, t);
  const c2 = control(t, tSide, s);
  // The middle of a cubic curve: at t = 0.5.
  const label = {
    x: s.x * 0.125 + c1.x * 0.375 + c2.x * 0.375 + t.x * 0.125,
    y: s.y * 0.125 + c1.y * 0.375 + c2.y * 0.375 + t.y * 0.125,
  };
  return {
    d: `M${round(s.x)},${round(s.y)}C${round(c1.x)},${round(c1.y)} ${round(c2.x)},${round(c2.y)} ${round(t.x)},${round(t.y)}`,
    label,
  };
}

function control(from: Point, side: Side, to: Point): Point {
  const n = normal(side);
  const along = n.x !== 0 ? (to.x - from.x) * n.x : (to.y - from.y) * n.y;
  // Ahead: a quarter of the way. Behind: out by a curve that grows with the distance.
  const distance = along >= 0 ? Math.max(along * 0.5, 20) : 25 * Math.sqrt(-along) + 20;
  return { x: from.x + n.x * distance, y: from.y + n.y * distance };
}

// Lines along the axes from side to side, out by `gap` from each node, with
// corners of `radius` (0 for square ones).
function orthogonal(s: Point, sSide: Side, t: Point, tSide: Side, radius: number): EdgeGeometry {
  const points = route(s, sSide, t, tSide, 20);
  return { d: roundedPath(points, radius), label: middleOf(points) };
}

/** The corners of a path along the axes. */
export function route(s: Point, sSide: Side, t: Point, tSide: Side, gap: number): Point[] {
  const sn = normal(sSide);
  const tn = normal(tSide);
  const a = { x: s.x + sn.x * gap, y: s.y + sn.y * gap };
  const b = { x: t.x + tn.x * gap, y: t.y + tn.y * gap };
  const points: Point[] = [s, a];
  const horizontalOut = sn.x !== 0;
  const horizontalIn = tn.x !== 0;

  if (horizontalOut && horizontalIn) {
    // Out sideways, in sideways: across at the middle, or around when the target is behind.
    const ahead = (b.x - a.x) * sn.x >= 0 && sn.x === -tn.x;
    if (ahead) {
      const mx = (a.x + b.x) / 2;
      points.push({ x: mx, y: a.y }, { x: mx, y: b.y });
    } else {
      const my = (a.y + b.y) / 2;
      points.push({ x: a.x, y: my }, { x: b.x, y: my });
    }
  } else if (!horizontalOut && !horizontalIn) {
    const ahead = (b.y - a.y) * sn.y >= 0 && sn.y === -tn.y;
    if (ahead) {
      const my = (a.y + b.y) / 2;
      points.push({ x: a.x, y: my }, { x: b.x, y: my });
    } else {
      const mx = (a.x + b.x) / 2;
      points.push({ x: mx, y: a.y }, { x: mx, y: b.y });
    }
  } else if (horizontalOut) {
    points.push({ x: b.x, y: a.y });
  } else {
    points.push({ x: a.x, y: b.y });
  }

  points.push(b, t);
  return simplify(points);
}

// Without points that repeat, or that lie on the line of their neighbours.
function simplify(points: Point[]): Point[] {
  const out: Point[] = [];
  for (const p of points) {
    const last = out[out.length - 1];
    if (last && Math.abs(last.x - p.x) < 0.01 && Math.abs(last.y - p.y) < 0.01) continue;
    if (out.length >= 2) {
      const prev = out[out.length - 2];
      const sameX = Math.abs(prev.x - last.x) < 0.01 && Math.abs(last.x - p.x) < 0.01;
      const sameY = Math.abs(prev.y - last.y) < 0.01 && Math.abs(last.y - p.y) < 0.01;
      if (sameX || sameY) out.pop();
    }
    out.push(p);
  }
  return out;
}

function roundedPath(points: Point[], radius: number): string {
  let d = `M${round(points[0].x)},${round(points[0].y)}`;
  for (let i = 1; i < points.length; i++) {
    const p = points[i];
    const next = points[i + 1];
    if (!next || radius === 0) {
      d += `L${round(p.x)},${round(p.y)}`;
      continue;
    }
    const prev = points[i - 1];
    const r = Math.min(radius, distance(prev, p) / 2, distance(p, next) / 2);
    const before = towards(p, prev, r);
    const after = towards(p, next, r);
    d += `L${round(before.x)},${round(before.y)}Q${round(p.x)},${round(p.y)} ${round(after.x)},${round(after.y)}`;
  }
  return d;
}

function distance(a: Point, b: Point): number {
  return Math.hypot(a.x - b.x, a.y - b.y);
}

function towards(from: Point, to: Point, by: number): Point {
  const d = distance(from, to) || 1;
  return { x: from.x + ((to.x - from.x) / d) * by, y: from.y + ((to.y - from.y) / d) * by };
}

/** The point half way along a polyline. */
export function middleOf(points: Point[]): Point {
  let total = 0;
  for (let i = 1; i < points.length; i++) total += distance(points[i - 1], points[i]);
  let left = total / 2;
  for (let i = 1; i < points.length; i++) {
    const length = distance(points[i - 1], points[i]);
    if (length >= left) return towards(points[i - 1], points[i], left);
    left -= length;
  }
  return points[points.length - 1];
}
