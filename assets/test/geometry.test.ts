import { test } from "node:test";
import assert from "node:assert/strict";
import { edgePath, facing, intersects, middleOf, route, union } from "../src/geometry";

test("boxes", () => {
  assert.ok(intersects({ x: 0, y: 0, width: 10, height: 10 }, { x: 5, y: 5, width: 10, height: 10 }));
  assert.ok(!intersects({ x: 0, y: 0, width: 10, height: 10 }, { x: 10, y: 0, width: 10, height: 10 }));
  assert.deepEqual(union([{ x: 0, y: 0, width: 1, height: 1 }, { x: -5, y: 3, width: 1, height: 1 }]), { x: -5, y: 0, width: 6, height: 4 });
  assert.equal(union([]), null);
  assert.equal(facing({ x: 0, y: 0, width: 100, height: 40 }, { x: 300, y: 30 }), "right");
  assert.equal(facing({ x: 0, y: 0, width: 100, height: 40 }, { x: 50, y: -300 }), "top");
});

test("a bezier leaves and arrives square to its sides", () => {
  const { d, label } = edgePath("bezier", { x: 0, y: 0 }, "right", { x: 200, y: 100 }, "left");
  assert.match(d, /^M0,0C100,0 100,100 200,100$/);
  assert.deepEqual(label, { x: 100, y: 50 });
});

test("a step path goes along the axes", () => {
  const points = route({ x: 0, y: 0 }, "right", { x: 200, y: 100 }, "left", 20);
  for (let i = 1; i < points.length; i++) {
    const a = points[i - 1];
    const b = points[i];
    assert.ok(a.x === b.x || a.y === b.y, `segment ${i} is not straight`);
  }
  assert.deepEqual(points[0], { x: 0, y: 0 });
  assert.deepEqual(points[points.length - 1], { x: 200, y: 100 });
  assert.deepEqual(middleOf([{ x: 0, y: 0 }, { x: 10, y: 0 }, { x: 10, y: 10 }]), { x: 10, y: 0 });
});

test("a step path goes around when the target is behind", () => {
  const points = route({ x: 200, y: 0 }, "right", { x: 0, y: 100 }, "left", 20);
  assert.ok(points.some((p) => p.x === 220));
  assert.ok(points.some((p) => p.x === -20));
  const smooth = edgePath("smooth", { x: 200, y: 0 }, "right", { x: 0, y: 100 }, "left");
  assert.match(smooth.d, /Q/);
});
