import { test } from "node:test";
import assert from "node:assert/strict";
import { SpatialIndex } from "../src/spatial";

const sorted = (ids: Iterable<string>) => [...ids].sort();

test("finds the boxes that meet a box, and those under a point", () => {
  const index = new SpatialIndex(100);
  index.set("a", { x: 0, y: 0, width: 50, height: 50 });
  index.set("b", { x: 90, y: 90, width: 30, height: 30 });
  index.set("c", { x: 1000, y: -500, width: 10, height: 10 });
  index.set("wide", { x: -300, y: 200, width: 900, height: 20 });

  assert.deepEqual(sorted(index.query({ x: 40, y: 40, width: 60, height: 60 })), ["a", "b"]);
  assert.deepEqual(sorted(index.query({ x: 990, y: -510, width: 30, height: 30 })), ["c"]);
  assert.deepEqual(sorted(index.query({ x: 500, y: 210, width: 1, height: 1 })), ["wide"]);
  assert.deepEqual(index.at({ x: 100, y: 100 }), ["b"]);
  assert.deepEqual(index.at({ x: 60, y: 60 }), []);
  assert.equal(index.size, 4);
});

test("a box moved is found where it is, and not where it was; one taken away, nowhere", () => {
  const index = new SpatialIndex(100);
  index.set("a", { x: 0, y: 0, width: 10, height: 10 });
  index.set("a", { x: 5000, y: 5000, width: 10, height: 10 });
  assert.deepEqual(sorted(index.query({ x: -10, y: -10, width: 50, height: 50 })), []);
  assert.deepEqual(sorted(index.query({ x: 4990, y: 4990, width: 50, height: 50 })), ["a"]);
  // Within its cells: the box moves, its cells stay.
  index.set("a", { x: 5020, y: 5020, width: 10, height: 10 });
  assert.deepEqual(index.get("a"), { x: 5020, y: 5020, width: 10, height: 10 });
  assert.deepEqual(sorted(index.query({ x: 4990, y: 4990, width: 20, height: 20 })), []);
  index.delete("a");
  assert.deepEqual(sorted(index.query({ x: 4990, y: 4990, width: 100, height: 100 })), []);
  assert.equal(index.size, 0);
});

test("finds the same boxes as a look at each of them", () => {
  const index = new SpatialIndex(64);
  const boxes = new Map<string, { x: number; y: number; width: number; height: number }>();
  let seed = 7;
  const random = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
  for (let i = 0; i < 500; i++) {
    const box = { x: random() * 4000 - 2000, y: random() * 4000 - 2000, width: random() * 300, height: random() * 300 };
    boxes.set(`n${i}`, box);
    index.set(`n${i}`, box);
  }
  for (let q = 0; q < 50; q++) {
    const area = { x: random() * 4000 - 2000, y: random() * 4000 - 2000, width: random() * 800, height: random() * 800 };
    const expected = [...boxes].filter(([, b]) => b.x <= area.x + area.width && area.x <= b.x + b.width && b.y <= area.y + area.height && area.y <= b.y + b.height).map(([id]) => id);
    assert.deepEqual(sorted(index.query(area)), sorted(expected));
  }
});
