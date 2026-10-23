import { test } from "node:test";
import assert from "node:assert/strict";
import { breakCycles, components, force, grid, layered, layers, layout, separate } from "../src/layout";

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

type Places = Map<string, { x: number; y: number }>;
type Box = { id: string; width: number; height: number };

// The pairs of nodes nearer than `gap`.
function overlaps(nodes: Box[], places: Places, gap = 0): number {
  let count = 0;
  for (let i = 0; i < nodes.length; i++)
    for (let j = i + 1; j < nodes.length; j++) {
      const a = places.get(nodes[i].id)!;
      const b = places.get(nodes[j].id)!;
      if (a.x < b.x + nodes[j].width + gap && b.x < a.x + nodes[i].width + gap && a.y < b.y + nodes[j].height + gap && b.y < a.y + nodes[i].height + gap) count++;
    }
  return count;
}

function bounds(nodes: Box[], places: Places) {
  let w = 0;
  let h = 0;
  for (const n of nodes) {
    const p = places.get(n.id)!;
    assert.ok(p.x >= 0 && p.y >= 0, `${n.id} at ${p.x}, ${p.y}`);
    w = Math.max(w, p.x + n.width);
    h = Math.max(h, p.y + n.height);
  }
  return { w, h, aspect: w / h };
}

// A schema: a few tables that many refer to, chains, and tables of nothing.
function schema(n: number) {
  let seed = 7;
  const random = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648;
  const nodes = Array.from({ length: n }, (_, i) => box(`t${i}`, 200 + Math.floor(random() * 80), 60 + 22 * Math.floor(2 + random() * 8)));
  const edges: { source: string; target: string }[] = [];
  const hubs = Math.max(1, Math.floor(n / 40));
  for (let i = hubs; i < n; i++) {
    if (random() < 0.15) continue;
    const t = random() < 0.4 ? Math.floor(random() * hubs) : Math.max(0, i - 1 - Math.floor(random() * 12));
    if (t !== i) edges.push({ source: `t${i}`, target: `t${t}` });
  }
  return { nodes, edges };
}

test("many parts are packed in rows, near the aspect asked for, not in one line", () => {
  const nodes: Box[] = [];
  const edges = [];
  for (let i = 0; i < 30; i++) {
    nodes.push(box(`a${i}`), box(`b${i}`));
    edges.push({ source: `a${i}`, target: `b${i}` });
  }
  for (const direction of ["right", "down"] as const) {
    const places = layered(nodes, edges, { direction, aspect: 1.6 });
    assert.equal(overlaps(nodes, places), 0);
    const { aspect } = bounds(nodes, places);
    assert.ok(aspect > 0.8 && aspect < 3.2, `${direction}: ${aspect}`);
  }
});

test("the nodes that no edge joins go together in a grid", () => {
  const nodes = [box("a"), box("b"), ...Array.from({ length: 12 }, (_, i) => box(`x${i}`))];
  const places = layered(nodes, [{ source: "a", target: "b" }]);
  assert.equal(overlaps(nodes, places), 0);
  const xs = new Set(Array.from({ length: 12 }, (_, i) => places.get(`x${i}`)!.x));
  const ys = new Set(Array.from({ length: 12 }, (_, i) => places.get(`x${i}`)!.y));
  assert.ok(xs.size > 1 && ys.size > 1, "in rows and columns");
});

test("a layer of hundreds (a table everyone refers to) wraps in columns", () => {
  const nodes = [box("users", 200, 120), ...Array.from({ length: 300 }, (_, i) => box(`t${i}`, 200, 120))];
  const edges = Array.from({ length: 300 }, (_, i) => ({ source: `t${i}`, target: "users" }));
  const places = layered(nodes, edges, { aspect: 1.6 });
  assert.equal(overlaps(nodes, places), 0);
  const { aspect } = bounds(nodes, places);
  assert.ok(aspect > 0.5 && aspect < 4, `aspect ${aspect}`);
  // Those who refer to it still come before it.
  for (let i = 0; i < 300; i++) assert.ok(places.get(`t${i}`)!.x < places.get("users")!.x);
});

test("a small fork stays in one layer", () => {
  const nodes = ["r", "a", "b", "c", "d", "e"].map((id) => box(id, 120, 60));
  const edges = ["a", "b", "c", "d", "e"].map((t) => ({ source: "r", target: t }));
  const places = layered(nodes, edges);
  assert.equal(new Set(["a", "b", "c", "d", "e"].map((id) => places.get(id)!.x)).size, 1);
});

test("force: no overlaps, neighbours nearer than the others, from (0, 0)", () => {
  const { nodes, edges } = schema(120);
  const places = force(nodes, edges, { gap: 32 });
  assert.equal(places.size, nodes.length);
  assert.equal(overlaps(nodes, places, 31.9), 0);
  bounds(nodes, places);
  const middle = (id: string) => {
    const p = places.get(id)!;
    const n = nodes.find((x) => x.id === id)!;
    return { x: p.x + n.width / 2, y: p.y + n.height / 2 };
  };
  const distance = (a: string, b: string) => Math.hypot(middle(a).x - middle(b).x, middle(a).y - middle(b).y);
  const joined = edges.reduce((sum, e) => sum + distance(e.source, e.target), 0) / edges.length;
  let all = 0;
  let pairs = 0;
  for (let i = 0; i < nodes.length; i += 7)
    for (let j = i + 3; j < nodes.length; j += 11) {
      all += distance(nodes[i].id, nodes[j].id);
      pairs++;
    }
  assert.ok(joined < (all / pairs) * 0.6, `joined ${joined}, any ${all / pairs}`);
});

test("force: the same graph, the same places", () => {
  const { nodes, edges } = schema(60);
  assert.deepEqual([...force(nodes, edges)], [...force(nodes, edges)]);
});

test("force: two thousand tables in a few seconds, none overlapping", () => {
  const { nodes, edges } = schema(2000);
  const start = performance.now();
  const places = force(nodes, edges);
  assert.ok(performance.now() - start < 8000);
  assert.equal(overlaps(nodes, places), 0);
  const { aspect } = bounds(nodes, places);
  assert.ok(aspect > 0.5 && aspect < 3, `aspect ${aspect}`);
});

test("grid: rows and columns in the nodes' order, near the aspect asked for", () => {
  const nodes = Array.from({ length: 40 }, (_, i) => box(`n${i}`, 100 + (i % 3) * 40, 40 + (i % 5) * 20));
  const places = grid(nodes, { aspect: 1.6, gap: 10 });
  assert.equal(overlaps(nodes, places, 9.9), 0);
  const { aspect } = bounds(nodes, places);
  assert.ok(aspect > 1.1 && aspect < 2.4, `aspect ${aspect}`);
  assert.deepEqual(places.get("n0"), { x: 0, y: 0 });
  assert.equal(places.get("n1")!.y, 0);
  assert.ok(places.get("n1")!.x > 0);
});

test("layout picks the algorithm", () => {
  const nodes = [box("a"), box("b"), box("c")];
  const edges = [{ source: "a", target: "b" }];
  assert.deepEqual([...layout(nodes, edges)], [...layered(nodes, edges)]);
  assert.deepEqual([...layout(nodes, edges, { algorithm: "force" })], [...force(nodes, edges)]);
  assert.deepEqual([...layout(nodes, edges, { algorithm: "grid" })], [...grid(nodes)]);
});

test("separate: boxes on one another end apart", () => {
  const boxes = Array.from({ length: 200 }, (_, i) => ({ id: `b${i}`, x: (i % 3) * 5, y: (i % 4) * 5, width: 80, height: 40 }));
  separate(boxes, 8);
  const places = new Map(boxes.map((b) => [b.id, { x: b.x, y: b.y }]));
  assert.equal(overlaps(boxes, places, 7.9), 0);
});
