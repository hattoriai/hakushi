import { test } from "node:test";
import assert from "node:assert/strict";
import { check } from "../src/rules";
import type { EdgeModel, Handle } from "../src/types";

const edge = (source: string, target: string, sourceHandle: string | null = null, targetHandle: string | null = null): EdgeModel => ({
  id: `${source}->${target}`,
  source,
  sourceHandle,
  target,
  targetHandle,
  path: "bezier",
  label: null,
  marker: "arrow",
  animated: false,
  points: [],
  mark: { status: null, highlight: false, color: null, dim: false, title: null, lit: false, diff: null },
});

const handle = (fields: Partial<Handle>): Handle =>
  ({ id: null, kind: "both", side: "right", type: null, accepts: null, max: null, x: 0, y: 0, el: null as unknown as HTMLElement, ...fields }) as Handle;

const rules = { loops: false, duplicates: false, cycles: true };
const edges = [edge("a", "b", "out"), edge("b", "c")];

test("the rules of the server", () => {
  assert.equal(check(rules, edges, { node: "a", handle: null }, null, { node: "a", handle: null }, null), "loop");
  assert.equal(check(rules, edges, { node: "a", handle: "out" }, null, { node: "b", handle: null }, null), "duplicate");
  assert.equal(check(rules, edges, { node: "c", handle: null }, null, { node: "a", handle: null }, null), null);
  assert.equal(check({ ...rules, cycles: false }, edges, { node: "c", handle: null }, null, { node: "a", handle: null }, null), "cycle");
});

test("the handles' kinds, types and maximums", () => {
  const out = handle({ id: "out", kind: "source", type: "int" });
  assert.equal(check(rules, [], { node: "a", handle: "x" }, handle({ kind: "target" }), { node: "b", handle: null }, null), "kind");
  assert.equal(check(rules, [], { node: "a", handle: "out" }, out, { node: "b", handle: "in" }, handle({ accepts: ["text"] })), "type");
  assert.equal(check(rules, [], { node: "a", handle: "out" }, out, { node: "b", handle: "in" }, handle({ accepts: ["int", "text"] })), null);
  assert.equal(check(rules, edges, { node: "a", handle: "out" }, handle({ max: 1 }), { node: "c", handle: null }, null), "full");
});
