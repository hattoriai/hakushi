import { test } from "node:test";
import assert from "node:assert/strict";
import { arrange } from "../src/arrange";

const boxes = [
  { id: "a", x: 0, y: 0, width: 100, height: 40 },
  { id: "b", x: 300, y: 100, width: 60, height: 80 },
  { id: "c", x: 120, y: 50, width: 20, height: 20 },
];

const at = (places: Map<string, { x: number; y: number }>) => Object.fromEntries(places);

test("lines up the sides and the middles of the box around them", () => {
  assert.deepEqual(at(arrange(boxes, "left")), { a: { x: 0, y: 0 }, b: { x: 0, y: 100 }, c: { x: 0, y: 50 } });
  assert.deepEqual(at(arrange(boxes, "right")), { a: { x: 260, y: 0 }, b: { x: 300, y: 100 }, c: { x: 340, y: 50 } });
  assert.deepEqual(at(arrange(boxes, "center")), { a: { x: 130, y: 0 }, b: { x: 150, y: 100 }, c: { x: 170, y: 50 } });
  assert.deepEqual(at(arrange(boxes, "top")), { a: { x: 0, y: 0 }, b: { x: 300, y: 0 }, c: { x: 120, y: 0 } });
  assert.deepEqual(at(arrange(boxes, "bottom")), { a: { x: 0, y: 140 }, b: { x: 300, y: 100 }, c: { x: 120, y: 160 } });
  assert.deepEqual(at(arrange(boxes, "middle")), { a: { x: 0, y: 70 }, b: { x: 300, y: 50 }, c: { x: 120, y: 80 } });
});

test("spaces them out with equal gaps, the first and the last staying", () => {
  // From 0 to 360, 180 of boxes: two gaps of 90.
  assert.deepEqual(at(arrange(boxes, "horizontal")), { a: { x: 0, y: 0 }, c: { x: 190, y: 50 }, b: { x: 300, y: 100 } });
  // From 0 to 180, 140 of boxes: two gaps of 20, in the order of their middles (a, c, b).
  assert.deepEqual(at(arrange(boxes, "vertical")), { a: { x: 0, y: 0 }, c: { x: 120, y: 60 }, b: { x: 300, y: 100 } });
});

test("too few boxes stay where they are", () => {
  assert.equal(arrange(boxes.slice(0, 1), "left").size, 0);
  assert.equal(arrange(boxes.slice(0, 2), "horizontal").size, 0);
  assert.equal(arrange(boxes.slice(0, 2), "left").size, 2);
});
