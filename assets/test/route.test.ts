import { test } from "node:test";
import assert from "node:assert/strict";
import { route } from "../src/geometry";
import { routeAround } from "../src/route";
import type { Point, Rect } from "../src/types";

// Whether a path along the axes passes through the inside of a box.
function crosses(points: Point[], box: Rect): boolean {
  for (let i = 0; i < points.length - 1; i++) {
    const p = points[i];
    const q = points[i + 1];
    const steps = 50;
    for (let k = 0; k <= steps; k++) {
      const x = p.x + ((q.x - p.x) * k) / steps;
      const y = p.y + ((q.y - p.y) * k) / steps;
      if (x > box.x && x < box.x + box.width && y > box.y && y < box.y + box.height) return true;
    }
  }
  return false;
}

const alongAxes = (points: Point[]) => points.every((p, i) => i === 0 || p.x === points[i - 1].x || p.y === points[i - 1].y);

test("with nothing in the way, the path of a step edge", () => {
  const s = { x: 0, y: 0 };
  const t = { x: 300, y: 80 };
  assert.deepEqual(routeAround(s, "right", t, "left", []), route(s, "right", t, "left", 20));
  // A box off to the side is not in the way.
  assert.deepEqual(routeAround(s, "right", t, "left", [{ x: 100, y: 300, width: 50, height: 50 }]), route(s, "right", t, "left", 20));
});

test("goes around a node between its ends, along the axes, from side to side", () => {
  const s = { x: 0, y: 0 };
  const t = { x: 400, y: 0 };
  const box = { x: 150, y: -40, width: 100, height: 80 };
  const points = routeAround(s, "right", t, "left", [box]);
  assert.ok(!crosses(points, box), JSON.stringify(points));
  assert.ok(alongAxes(points), JSON.stringify(points));
  assert.deepEqual(points[0], s);
  assert.deepEqual(points[points.length - 1], t);
  // Out of the source to the right, into the target from its left.
  assert.equal(points[1].y, 0);
  assert.ok(points[1].x > 0);
  assert.equal(points[points.length - 2].y, 0);
  assert.ok(points[points.length - 2].x < 400);
  // Around it: four corners, no more.
  assert.equal(points.length, 6, JSON.stringify(points));
});

test("goes around a wall of nodes, and through the gap in it", () => {
  const s = { x: 0, y: 0 };
  const t = { x: 600, y: 0 };
  const wall = [
    { x: 250, y: -400, width: 100, height: 370 },
    { x: 250, y: 30, width: 100, height: 370 },
  ];
  // A gap of 60 between them, at y -30 to 30: room for the line, 12 off each.
  const points = routeAround(s, "right", t, "left", wall);
  for (const box of wall) assert.ok(!crosses(points, box));
  assert.equal(points.length, 2, "straight through the gap");

  const closed = [{ x: 250, y: -400, width: 100, height: 800 }];
  const around = routeAround(s, "right", t, "left", closed);
  assert.ok(!crosses(around, closed[0]));
  assert.ok(alongAxes(around));
});

test("keeps clear of its own nodes when the target is behind the source", () => {
  const source = { x: 200, y: -30, width: 100, height: 60 };
  const target = { x: -100, y: -30, width: 100, height: 60 };
  const s = { x: 300, y: 0 };
  const t = { x: -100, y: 0 };
  const points = routeAround(s, "right", t, "left", [source, target]);
  assert.ok(!crosses(points, source), JSON.stringify(points));
  assert.ok(!crosses(points, target), JSON.stringify(points));
  assert.ok(alongAxes(points));
});

test("finds its way among many nodes, quickly", () => {
  let seed = 11;
  const random = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
  const boxes: Rect[] = [];
  for (let i = 0; i < 40; i++) boxes.push({ x: 100 + random() * 1600, y: -600 + random() * 1200, width: 60 + random() * 100, height: 40 + random() * 60 });
  const s = { x: 0, y: 0 };
  const t = { x: 1900, y: 100 };
  const points = routeAround(s, "right", t, "left", boxes);
  for (const box of boxes) assert.ok(!crosses(points, box), JSON.stringify({ box, points }));
  assert.ok(alongAxes(points));
  // Forty nodes in the way: a few milliseconds, once warm. Far above it,
  // so that a slow machine passes and a search gone wild does not.
  const started = performance.now();
  for (let i = 0; i < 10; i++) routeAround(s, "right", t, "left", boxes);
  const took = (performance.now() - started) / 10;
  assert.ok(took < 60, `took ${took}ms`);
});
