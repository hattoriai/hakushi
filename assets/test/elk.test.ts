import { test } from "node:test";
import assert from "node:assert/strict";
import { elk, toElk } from "../src/elk";
import { engineOf, registerLayout, resetLayouts, type EngineInput, type EngineNode } from "../src/engines";

const pad = { top: 40, right: 16, bottom: 16, left: 16 };
const node = (id: string, parent: string | null = null, extra: Partial<EngineNode> = {}): EngineNode => ({
  id,
  width: 120,
  height: 48,
  parent,
  group: false,
  padding: { top: 0, right: 0, bottom: 0, left: 0 },
  ports: [],
  ...extra,
});

// A client outside two nested groups (a cluster, a service in it), and the
// two workloads of the service.
const nested: EngineInput = {
  direction: "right",
  nodes: [
    node("client"),
    node("cluster", null, { group: true, padding: pad }),
    node("service", "cluster", { group: true, padding: pad }),
    node("api", "service"),
    node("worker", "service"),
    node("db", "cluster"),
  ],
  edges: [
    { id: "e1", source: "client", target: "api", sourcePort: null, targetPort: null, label: { width: 60, height: 18 } },
    { id: "e2", source: "api", target: "db", sourcePort: null, targetPort: null, label: null },
    { id: "e3", source: "worker", target: "db", sourcePort: null, targetPort: null, label: null },
  ],
};

const inside = (a: { x: number; y: number; width?: number; height?: number }, b: { x: number; y: number; width?: number; height?: number }) =>
  a.x >= b.x && a.y >= b.y && a.x + a.width! <= b.x + b.width! && a.y + a.height! <= b.y + b.height!;

test("nested groups get sizes around their nodes, in the canvas's terms", async () => {
  const result = await elk()(nested);
  const n = result.nodes;
  assert.ok(inside(n.api, n.service), "api in service");
  assert.ok(inside(n.worker, n.service), "worker in service");
  assert.ok(inside(n.service, n.cluster), "service in cluster");
  assert.ok(inside(n.db, n.cluster), "db in cluster");
  assert.ok(!inside(n.client, n.cluster), "client outside");
  // The padding: the title of the group is above its nodes.
  assert.ok(n.api.y - n.service.y >= pad.top);
  // Left to right: the client before the api, the api before the db.
  assert.ok(n.client.x + n.client.width! <= n.api.x);
  assert.ok(n.api.x + n.api.width! <= n.db.x);
});

test("edges are routed along the axes, from one node to the other", async () => {
  const result = await elk()(nested);
  for (const id of ["e1", "e2", "e3"]) {
    const way = result.edges![id];
    assert.ok(way.points.length >= 2, id);
    for (let i = 1; i < way.points.length; i++) {
      const [a, b] = [way.points[i - 1], way.points[i]];
      assert.ok(Math.abs(a.x - b.x) < 0.01 || Math.abs(a.y - b.y) < 0.01, `${id} segment ${i} is not straight`);
    }
  }
  const e1 = result.edges!.e1;
  const client = result.nodes.client;
  const api = result.nodes.api;
  assert.equal(Math.round(e1.points[0].x), Math.round(client.x + client.width!));
  assert.equal(Math.round(e1.points.at(-1)!.x), Math.round(api.x));
  assert.ok(e1.label, "the label has a place");
});

test("a handle is a port: the edge starts where the handle is", async () => {
  const input: EngineInput = {
    direction: "right",
    nodes: [
      node("table", null, { height: 120, ports: [{ id: "p-row3", x: 120, y: 90, side: "right" }] }),
      node("other"),
    ],
    edges: [{ id: "fk", source: "table", target: "other", sourcePort: "p-row3", targetPort: null, label: null }],
  };
  const result = await elk()(input);
  const start = result.edges!.fk.points[0];
  assert.equal(Math.round(start.x), Math.round(result.nodes.table.x + 120));
  assert.equal(Math.round(start.y), Math.round(result.nodes.table.y + 90));
});

test("down lays out from top to bottom, and options go to ELK", async () => {
  const input: EngineInput = { direction: "down", nodes: [node("a"), node("b")], edges: [{ id: "e", source: "a", target: "b", sourcePort: null, targetPort: null, label: null }] };
  const result = await elk()(input);
  assert.ok(result.nodes.a.y + 48 <= result.nodes.b.y);
  const graph = toElk(input, { "elk.spacing.nodeNode": "99" });
  assert.equal(graph.layoutOptions!["elk.direction"], "DOWN");
  assert.equal(graph.layoutOptions!["elk.spacing.nodeNode"], "99");
});

test("an edge from a group to a node in it, and an empty group, do not stop the layout", async () => {
  const input: EngineInput = {
    direction: "right",
    nodes: [node("g", null, { group: true, padding: pad }), node("a", "g"), node("empty", null, { group: true, padding: pad })],
    edges: [{ id: "in", source: "g", target: "a", sourcePort: null, targetPort: null, label: null }],
  };
  const graph = toElk(input);
  assert.equal(graph.edges!.length, 0);
  const result = await elk()(input);
  assert.equal(result.nodes.empty.width, 120);
  assert.ok(result.nodes.a);
});

test("registerLayout names an engine, and checks the name", () => {
  resetLayouts();
  assert.equal(engineOf("elk"), null);
  const engine = elk();
  registerLayout("elk", engine);
  assert.equal(engineOf("elk"), engine);
  assert.throws(() => registerLayout("Not OK", engine), /a-z/);
  resetLayouts();
});
