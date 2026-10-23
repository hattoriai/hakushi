import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { centerline, fmt, inkBox, inside, outline, simplify, streamline, type InkPoint } from "../src/ink";

// The outlines the server draws (Hakushi.Ink): the same, to the character.
const fixture = JSON.parse(readFileSync("../test/fixtures/ink.json", "utf8")) as {
  numbers: [number, string][];
  strokes: { name: string; points: InkPoint[]; size: number; flat: boolean; outline: string; centerline: string }[];
};

test("numbers to a tenth, halves away from zero, as the server writes them", () => {
  for (const [n, text] of fixture.numbers) assert.equal(fmt(n), text, `${n}`);
});

test("the outline of a stroke is the server's", () => {
  for (const stroke of fixture.strokes) {
    assert.equal(outline(stroke.points, stroke.size, stroke.flat), stroke.outline, stroke.name);
    assert.equal(centerline(stroke.points), stroke.centerline, stroke.name);
  }
});

test("an outline is wider with more pressure, and one width for a highlighter", () => {
  const light = outline([[0, 0, 0], [100, 0, 0]], 10);
  const heavy = outline([[0, 0, 1], [100, 0, 1]], 10);
  // The points beside the line: 2.5 away with none, 7.5 with all of it.
  assert.match(light, /^M0 2\.5L100 2\.5A2\.5 2\.5 0 0 0 100 -2\.5L0 -2\.5A2\.5 2\.5 0 0 0 0 2\.5Z$/);
  assert.match(heavy, /^M0 7\.5L100 7\.5/);
  assert.equal(outline([[0, 0, 0], [100, 0, 1]], 10, true), outline([[0, 0, 0.5], [100, 0, 0.5]], 10));
  assert.equal(outline([], 4), "");
});

test("simplifies a line to the points that matter", () => {
  const line: InkPoint[] = [];
  for (let i = 0; i <= 100; i++) line.push([i, i < 50 ? 0 : i - 50, 0.5]);
  const simple = simplify(line, 0.5);
  assert.deepEqual(
    simple.map(([x, y]) => [x, y]),
    [
      [0, 0],
      [50, 0],
      [100, 50],
    ],
  );
  assert.deepEqual(simplify(line.slice(0, 2), 1), line.slice(0, 2));
});

test("smooths a line: each point a little behind the pointer", () => {
  assert.deepEqual(streamline(undefined, [10, 10, 0.3]), [10, 10, 0.3]);
  assert.deepEqual(streamline([0, 0, 0.5], [10, 20, 0.8], 0.5), [5, 10, 0.8]);
});

test("the box of a stroke has room for its width", () => {
  assert.deepEqual(inkBox([[10, 20, 0.5], [30, 25, 0.5]], 4), { x: 7, y: 17, width: 26, height: 11 });
  assert.deepEqual(inkBox([[10, 20, 0.5]], 20, true), { x: 0, y: 10, width: 20, height: 20 });
});

test("a lasso encloses what is inside it", () => {
  const square = [
    { x: 0, y: 0 },
    { x: 10, y: 0 },
    { x: 10, y: 10 },
    { x: 0, y: 10 },
  ];
  assert.equal(inside(square, { x: 5, y: 5 }), true);
  assert.equal(inside(square, { x: 15, y: 5 }), false);
});
