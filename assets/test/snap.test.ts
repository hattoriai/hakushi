import { test } from "node:test";
import assert from "node:assert/strict";
import { align, snapToGrid } from "../src/snap";

test("the grid", () => {
  assert.equal(snapToGrid(29, 20), 20);
  assert.equal(snapToGrid(31, 20), 40);
  assert.equal(snapToGrid(31, 0), 31);
});

test("lines up edges and middles with the nearest box", () => {
  const box = { x: 103, y: 300, width: 50, height: 20 };
  const others = [
    { x: 100, y: 0, width: 80, height: 40 },
    { x: 400, y: 298, width: 30, height: 30 },
  ];
  const { dx, dy, guides } = align(box, others, 5);
  assert.equal(dx, -3);
  assert.equal(dy, -2);
  assert.deepEqual(guides.find((g) => g.axis === "x"), { axis: "x", at: 100, from: 0, to: 318 });
  assert.equal(guides.find((g) => g.axis === "y")?.at, 298);
});

test("nothing near, nothing moves", () => {
  assert.deepEqual(align({ x: 0, y: 0, width: 10, height: 10 }, [{ x: 500, y: 500, width: 10, height: 10 }], 5), { dx: 0, dy: 0, guides: [] });
});
