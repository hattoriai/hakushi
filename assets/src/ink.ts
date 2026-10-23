// Ink: the geometry of a stroke drawn with a pen (Hakushi.Kits.Ink). A
// stroke is its points ([x, y, pressure], pressure from 0 to 1), smoothed
// as they come, simplified when the pen lifts, and drawn as an outline
// whose width follows the pressure. The server draws a stroke with the
// same outline (Hakushi.Ink): a stroke in progress here, and the stroke
// it becomes there, are the same shape.

import type { Point, Rect } from "./types";

export type InkPoint = [number, number, number];

/** A stroke in progress, as it goes to the others and is drawn: its points are the canvas's. */
export interface InkStroke {
  tool: string;
  color: string;
  size: number;
  points: InkPoint[];
}

// The pressure of a pointer with none (a mouse), and of a highlighter.
export const FLAT = 0.5;

/** A point drawn a little behind the pointer, so that the line is smooth and not the hand's every tremor. */
export function streamline(previous: InkPoint | undefined, raw: InkPoint, amount = 0.5): InkPoint {
  if (!previous) return raw;
  const k = 1 - amount;
  return [previous[0] + (raw[0] - previous[0]) * k, previous[1] + (raw[1] - previous[1]) * k, raw[2]];
}

/**
 * The points that matter (Ramer-Douglas-Peucker): those within `tolerance`
 * of the line the others make are left out, so that a stroke is a few
 * hundred points, not thousands.
 */
export function simplify(points: InkPoint[], tolerance: number): InkPoint[] {
  if (points.length < 3) return points.slice();
  const keep = new Uint8Array(points.length);
  keep[0] = 1;
  keep[points.length - 1] = 1;
  const stack: [number, number][] = [[0, points.length - 1]];
  while (stack.length) {
    const [first, last] = stack.pop()!;
    let far = -1;
    let distance = tolerance;
    for (let i = first + 1; i < last; i++) {
      const d = toSegment(points[i], points[first], points[last]);
      if (d > distance) {
        distance = d;
        far = i;
      }
    }
    if (far !== -1) {
      keep[far] = 1;
      stack.push([first, far], [far, last]);
    }
  }
  return points.filter((_, i) => keep[i] === 1);
}

function toSegment(p: InkPoint, a: InkPoint, b: InkPoint): number {
  const dx = b[0] - a[0];
  const dy = b[1] - a[1];
  const length = dx * dx + dy * dy;
  const t = length === 0 ? 0 : Math.max(0, Math.min(1, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / length));
  return Math.hypot(p[0] - (a[0] + t * dx), p[1] - (a[1] + t * dy));
}

/** A number as a path writes it: to a tenth, halves away from zero. Hakushi.Ink writes the same. */
export function fmt(value: number): string {
  const tenths = Math.sign(value) * Math.round(Math.abs(value) * 10);
  return tenths === 0 ? "0" : String(tenths / 10);
}

/** How far a stroke reaches from its points: the most its outline is wide, halved. */
export function reach(size: number, flat: boolean): number {
  return flat ? size / 2 : size * 0.75;
}

/**
 * The outline of a stroke, as the `d` of an SVG path that is filled: the
 * points on each side of the line, as far from it as the pressure says
 * (thinner with less), joined by curves through their middles, with a
 * round cap at each end. `flat` (a highlighter, or a pen with no pressure)
 * keeps one width.
 */
export function outline(points: InkPoint[], size: number, flat = false): string {
  const pts = distinct(points);
  if (pts.length === 0) return "";
  const radius = (p: InkPoint) => (flat ? size / 2 : (size / 2) * (0.5 + clampPressure(p[2])));
  if (pts.length === 1) {
    const [x, y] = pts[0];
    const r = fmt(radius(pts[0]));
    return `M${fmt(x - radius(pts[0]))} ${fmt(y)}A${r} ${r} 0 1 0 ${fmt(x + radius(pts[0]))} ${fmt(y)}A${r} ${r} 0 1 0 ${fmt(x - radius(pts[0]))} ${fmt(y)}Z`;
  }
  const left: Point[] = [];
  const right: Point[] = [];
  let tangent = { x: 1, y: 0 };
  for (let i = 0; i < pts.length; i++) {
    const a = pts[Math.max(0, i - 1)];
    const b = pts[Math.min(pts.length - 1, i + 1)];
    const dx = b[0] - a[0];
    const dy = b[1] - a[1];
    const length = Math.hypot(dx, dy);
    if (length > 0) tangent = { x: dx / length, y: dy / length };
    const r = radius(pts[i]);
    left.push({ x: pts[i][0] - tangent.y * r, y: pts[i][1] + tangent.x * r });
    right.push({ x: pts[i][0] + tangent.y * r, y: pts[i][1] - tangent.x * r });
  }
  const at = (p: Point) => `${fmt(p.x)} ${fmt(p.y)}`;
  const mid = (a: Point, b: Point) => ({ x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 });
  const n = pts.length;
  const end = fmt(radius(pts[n - 1]));
  const start = fmt(radius(pts[0]));
  let d = `M${at(left[0])}`;
  for (let i = 1; i < n - 1; i++) d += `Q${at(left[i])} ${at(mid(left[i], left[i + 1]))}`;
  d += `L${at(left[n - 1])}A${end} ${end} 0 0 0 ${at(right[n - 1])}`;
  for (let i = n - 2; i > 0; i--) d += `Q${at(right[i])} ${at(mid(right[i], right[i - 1]))}`;
  d += `L${at(right[0])}A${start} ${start} 0 0 0 ${at(left[0])}Z`;
  return d;
}

/** The line through a stroke's points, as an SVG path's `d`: to aim at it, and to sample it. */
export function centerline(points: InkPoint[]): string {
  return points.map((p, i) => `${i === 0 ? "M" : "L"}${fmt(p[0])} ${fmt(p[1])}`).join("");
}

/** The box of a stroke's outline. */
export function inkBox(points: InkPoint[], size: number, flat = false): Rect {
  let x0 = Infinity;
  let y0 = Infinity;
  let x1 = -Infinity;
  let y1 = -Infinity;
  for (const [x, y] of points) {
    x0 = Math.min(x0, x);
    y0 = Math.min(y0, y);
    x1 = Math.max(x1, x);
    y1 = Math.max(y1, y);
  }
  const r = reach(size, flat);
  return { x: x0 - r, y: y0 - r, width: x1 - x0 + r * 2, height: y1 - y0 + r * 2 };
}

/** Whether a point is inside a closed line (a lasso), by the even-odd rule. */
export function inside(polygon: Point[], p: Point): boolean {
  let within = false;
  for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    const a = polygon[i];
    const b = polygon[j];
    if (a.y > p.y !== b.y > p.y && p.x < ((b.x - a.x) * (p.y - a.y)) / (b.y - a.y) + a.x) within = !within;
  }
  return within;
}

function clampPressure(p: number): number {
  return Number.isFinite(p) ? Math.max(0, Math.min(1, p)) : FLAT;
}

// Points that follow one another at the same place are one.
function distinct(points: InkPoint[]): InkPoint[] {
  const out: InkPoint[] = [];
  for (const p of points) {
    const last = out[out.length - 1];
    if (!last || Math.abs(last[0] - p[0]) > 0.01 || Math.abs(last[1] - p[1]) > 0.01) out.push(p);
  }
  return out;
}
