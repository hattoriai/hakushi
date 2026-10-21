import { test } from "node:test";
import assert from "node:assert/strict";
import { breakCycles, components, layered, layers } from "../src/layout";

const box = (id: string, width = 100, height = 40) => ({ id, width, height });

test("a chain goes left to right, one layer each, level", () => {
  const places = layered([box("a"), box("b"), box("c")], [{ source: "a", target: "b" }, { source: "b", target: "c" }]);
  const a = places.get("a")!;
  const b = places.get("b")!;
  const c = places.get("c")!;
  assert.ok(a.x < b.x && b.x < c.x);
  assert.equal(a.y, b.y);
  assert.equal(b.y, c.y);
  assert.equal(b.x - a.x, 100 + 96);
});

test("down goes top to bottom", () => {
  const places = layered([box("a"), box("b")], [{ source: "a", target: "b" }], { direction: "down" });
  assert.ok(places.get("a")!.y < places.get("b")!.y);
  assert.equal(places.get("a")!.x, places.get("b")!.x);
});

test("a fork: the two branches in one layer, apart, and their source between them", () => {
  const places = layered([box("a"), box("b"), box("c")], [{ source: "a", target: "b" }, { source: "a", target: "c" }]);
  const [a, b, c] = ["a", "b", "c"].map((id) => places.get(id)!);
  assert.equal(b.x, c.x);
  assert.ok(Math.abs(b.y - c.y) >= 40 + 32);
  const middle = (Math.min(b.y, c.y) + Math.max(b.y, c.y)) / 2;
  assert.ok(Math.abs(a.y - middle) < 1);
});

test("no two nodes of a layer overlap", () => {
  const nodes = ["r", "a", "b", "c", "d", "e"].map((id) => box(id, 120, 60));
  const edges = ["a", "b", "c", "d", "e"].map((t) => ({ source: "r", target: t }));
  const places = layered(nodes, edges);
  const ys = ["a", "b", "c", "d", "e"].map((id) => places.get(id)!.y).sort((p, q) => p - q);
  for (let i = 1; i < ys.length; i++) assert.ok(ys[i] - ys[i - 1] >= 60 + 32 - 0.001);
});

test("cycles are broken, and every node gets a layer", () => {
  const nodes = [box("a"), box("b"), box("c")];
  const edges = [{ source: "a", target: "b" }, { source: "b", target: "c" }, { source: "c", target: "a" }];
  const acyclic = breakCycles(nodes, edges);
  assert.deepEqual(acyclic[2], { source: "a", target: "c" });
  const l = layers(nodes, acyclic);
  assert.deepEqual([l.get("a"), l.get("b"), l.get("c")], [0, 1, 2]);
  assert.equal(layered(nodes, edges).size, 3);
});

test("parts that no edge joins are laid out apart", () => {
  const nodes = [box("a"), box("b"), box("x"), box("y")];
  const edges = [{ source: "a", target: "b" }, { source: "x", target: "y" }];
  assert.equal(components(nodes, edges).length, 2);
  const places = layered(nodes, edges);
  assert.ok(places.get("x")!.y >= places.get("a")!.y + 40);
});

test("the order in a layer crosses fewer edges", () => {
  // a→d and b→c would cross in the order of the nodes.
  const nodes = ["a", "b", "c", "d"].map((id) => box(id));
  const places = layered(nodes, [{ source: "a", target: "d" }, { source: "b", target: "c" }]);
  const [a, b, c, d] = ["a", "b", "c", "d"].map((id) => places.get(id)!);
  assert.equal(Math.sign(a.y - b.y), Math.sign(d.y - c.y));
});
