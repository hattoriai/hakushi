// A path along the axes that goes around the boxes in its way (an edge's
// `path="routed"`): the shortest, with as few corners as it can, on a grid
// made of the lines by the boxes' sides and the edge's ends.

import { normal, route } from "./geometry";
import type { Point, Rect, Side } from "./types";

/** The most boxes a path goes around: the nearest ones, past that. */
export const ROUTE_MAX_BOXES = 48;

// What a corner costs, as a length: a path one corner shorter is taken over
// one up to this much longer.
const BEND = 40;

const DIRS = [
  { x: 1, y: 0 },
  { x: 0, y: 1 },
  { x: -1, y: 0 },
  { x: 0, y: -1 },
];

function dirOf(v: Point): number {
  if (v.x > 0) return 0;
  if (v.y > 0) return 1;
  if (v.x < 0) return 2;
  return 3;
}

/**
 * The corners of a path from `s` (leaving by `sSide`) to `t` (arriving by
 * `tSide`) that keeps `margin` off each box of `boxes`; out of and into the
 * ends' sides by `gap`. Without a box in the way, or with no way around
 * them, route's.
 */
export function routeAround(s: Point, sSide: Side, t: Point, tSide: Side, boxes: Rect[], gap = 20, margin = 12): Point[] {
  const sn = normal(sSide);
  const tn = normal(tSide);
  const a = { x: s.x + sn.x * gap, y: s.y + sn.y * gap };
  const b = { x: t.x + tn.x * gap, y: t.y + tn.y * gap };
  const middle = { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
  // The boxes with room around them, but those the ends are in (an end on
  // a box, or in a box that holds it), the nearest first.
  const walls = boxes
    .map((r) => ({ x: r.x - margin, y: r.y - margin, width: r.width + margin * 2, height: r.height + margin * 2 }))
    .filter((r) => !inside(r, a) && !inside(r, b))
    .sort((p, q) => far(p, middle) - far(q, middle))
    .slice(0, ROUTE_MAX_BOXES);
  const plain = route(s, sSide, t, tSide, gap);
  if (walls.length === 0 || !blocked(plain, boxes)) return plain;

  const xs = lines([a.x, b.x, middle.x, ...walls.flatMap((r) => [r.x, r.x + r.width])]);
  const ys = lines([a.y, b.y, middle.y, ...walls.flatMap((r) => [r.y, r.y + r.height])]);
  const width = xs.length;
  const height = ys.length;
  const start = xs.indexOf(lineOf(a.x)) + ys.indexOf(lineOf(a.y)) * width;
  const goal = xs.indexOf(lineOf(b.x)) + ys.indexOf(lineOf(b.y)) * width;
  // What the boxes cover, on the grid: the points in them, and the steps
  // across them (from a point to the next on its right, or below it).
  // Between two neighbouring lines no box begins or ends.
  const shut = new Uint8Array(width * height);
  const shutRight = new Uint8Array(width * height);
  const shutDown = new Uint8Array(width * height);
  for (const r of walls) {
    const c0 = xs.indexOf(lineOf(r.x));
    const c1 = xs.indexOf(lineOf(r.x + r.width));
    const r0 = ys.indexOf(lineOf(r.y));
    const r1 = ys.indexOf(lineOf(r.y + r.height));
    for (let row = r0; row <= r1; row++) {
      for (let col = c0; col <= c1; col++) {
        const i = col + row * width;
        const inX = col > c0 && col < c1;
        const inY = row > r0 && row < r1;
        if (inX && inY) shut[i] = 1;
        if (inY && col < c1) shutRight[i] = 1;
        if (inX && row < r1) shutDown[i] = 1;
      }
    }
  }
  const open = (i: number, dir: number) => {
    if (dir === 0) return !shutRight[i];
    if (dir === 1) return !shutDown[i];
    if (dir === 2) return !shutRight[i - 1];
    return !shutDown[i - width];
  };

  // A* over (point, direction): a step costs its length, a turn BEND more.
  const first = dirOf(sn);
  const last = dirOf({ x: -tn.x, y: -tn.y });
  const cost = new Float64Array(width * height * 4).fill(Infinity);
  const from = new Int32Array(width * height * 4).fill(-1);
  const heap = new Heap();
  // What is left at the least: the distance, and a corner when both ways
  // are left to go. A little more of it in the order, so that of the many
  // ways of one length the one nearer the end goes first.
  const h = (i: number) => {
    const dx = Math.abs(xs[i % width] - b.x);
    const dy = Math.abs(ys[Math.floor(i / width)] - b.y);
    return (dx + dy + (dx > 0.01 && dy > 0.01 ? BEND : 0)) * 1.001;
  };
  cost[start * 4 + first] = 0;
  heap.push(start * 4 + first, h(start));
  let found = -1;
  while (heap.size > 0) {
    const priority = heap.least;
    const state = heap.pop();
    const here = state >> 2;
    const dir = state & 3;
    const so = cost[state];
    // Already reached for less.
    if (priority > so + h(here) + 1e-6) continue;
    if (here === goal) {
      found = state;
      break;
    }
    const col = here % width;
    const row = (here - col) / width;
    for (let next = 0; next < 4; next++) {
      if (next === (dir + 2) % 4) continue;
      const c = col + DIRS[next].x;
      const r = row + DIRS[next].y;
      if (c < 0 || c >= width || r < 0 || r >= height) continue;
      const there = c + r * width;
      if ((there !== goal && shut[there]) || !open(here, next)) continue;
      let step = Math.abs(xs[c] - xs[col]) + Math.abs(ys[r] - ys[row]) + (next === dir ? 0 : BEND);
      // Into the target square to its side.
      if (there === goal && next !== last) step += next === (last + 2) % 4 ? BEND * 2 : BEND;
      const key = there * 4 + next;
      if (so + step < cost[key]) {
        cost[key] = so + step;
        from[key] = state;
        heap.push(key, so + step + h(there));
      }
    }
  }
  if (found < 0) return plain;

  const corners: Point[] = [];
  for (let state = found; state >= 0; state = from[state]) {
    const i = state >> 2;
    corners.push({ x: xs[i % width], y: ys[Math.floor(i / width)] });
  }
  return straighten([s, ...corners.reverse(), t]);
}

function inside(r: Rect, p: Point): boolean {
  return p.x > r.x + 0.01 && p.x < r.x + r.width - 0.01 && p.y > r.y + 0.01 && p.y < r.y + r.height - 0.01;
}

function far(r: Rect, p: Point): number {
  const dx = Math.max(r.x - p.x, 0, p.x - r.x - r.width);
  const dy = Math.max(r.y - p.y, 0, p.y - r.y - r.height);
  return dx + dy;
}

const lineOf = (v: number) => Math.round(v * 100) / 100;

function lines(values: number[]): number[] {
  return [...new Set(values.map(lineOf))].sort((p, q) => p - q);
}

// Whether a path along the axes passes through the inside of a box.
function blocked(points: Point[], walls: Rect[]): boolean {
  for (let i = 0; i < points.length - 1; i++) {
    const p = points[i];
    const q = points[i + 1];
    const seg = { x: Math.min(p.x, q.x), y: Math.min(p.y, q.y), width: Math.abs(p.x - q.x), height: Math.abs(p.y - q.y) };
    for (const r of walls) {
      const overX = seg.x < r.x + r.width && seg.x + seg.width > r.x;
      const overY = seg.y < r.y + r.height && seg.y + seg.height > r.y;
      const acrossX = seg.width === 0 ? seg.x > r.x && seg.x < r.x + r.width : overX;
      const acrossY = seg.height === 0 ? seg.y > r.y && seg.y < r.y + r.height : overY;
      if (acrossX && acrossY) return true;
    }
  }
  return false;
}

// Without the points in the middle of a straight run.
function straighten(points: Point[]): Point[] {
  const out: Point[] = [];
  for (const p of points) {
    const last = out[out.length - 1];
    if (last && Math.abs(last.x - p.x) < 0.01 && Math.abs(last.y - p.y) < 0.01) continue;
    if (out.length >= 2) {
      const prev = out[out.length - 2];
      if ((Math.abs(prev.x - last.x) < 0.01 && Math.abs(last.x - p.x) < 0.01) || (Math.abs(prev.y - last.y) < 0.01 && Math.abs(last.y - p.y) < 0.01)) out.pop();
    }
    out.push(p);
  }
  return out;
}

// A binary heap of numbers by their priority, the least first.
class Heap {
  private items: number[] = [];
  private priorities: number[] = [];

  get size(): number {
    return this.items.length;
  }

  push(item: number, priority: number): void {
    const items = this.items;
    const ps = this.priorities;
    let i = items.length;
    items.push(item);
    ps.push(priority);
    while (i > 0) {
      const up = (i - 1) >> 1;
      if (ps[up] <= ps[i]) break;
      [items[up], items[i]] = [items[i], items[up]];
      [ps[up], ps[i]] = [ps[i], ps[up]];
      i = up;
    }
  }

  /** The priority of the least. */
  get least(): number {
    return this.priorities[0];
  }

  pop(): number {
    const items = this.items;
    const ps = this.priorities;
    const top = items[0];
    const lastItem = items.pop()!;
    const lastP = ps.pop()!;
    if (items.length > 0) {
      items[0] = lastItem;
      ps[0] = lastP;
      let i = 0;
      for (;;) {
        const l = i * 2 + 1;
        const r = l + 1;
        let least = i;
        if (l < items.length && ps[l] < ps[least]) least = l;
        if (r < items.length && ps[r] < ps[least]) least = r;
        if (least === i) break;
        [items[least], items[i]] = [items[i], items[least]];
        [ps[least], ps[i]] = [ps[i], ps[least]];
        i = least;
      }
    }
    return top;
  }
}
