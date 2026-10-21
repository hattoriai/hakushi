import { test } from "node:test";
import assert from "node:assert/strict";
import { fit, reveal, toCanvas, toScreen, visible, zoomAt } from "../src/view";

test("screen and canvas points go back and forth", () => {
  const view = { x: 100, y: -50, zoom: 2 };
  const p = toCanvas(view, 300, 150);
  assert.deepEqual(p, { x: 100, y: 100 });
  assert.deepEqual(toScreen(view, p.x, p.y), { x: 300, y: 150 });
});

test("zoom keeps the point under the pointer in place", () => {
  const view = { x: 10, y: 20, zoom: 1 };
  const before = toCanvas(view, 200, 100);
  const zoomed = zoomAt(view, 2, 200, 100, 0.1, 4);
  assert.equal(zoomed.zoom, 2);
  assert.deepEqual(toCanvas(zoomed, 200, 100), before);
  assert.equal(zoomAt(view, 100, 0, 0, 0.1, 4).zoom, 4);
});

test("fit shows a box in the middle, never above 100%", () => {
  const view = fit({ x: 0, y: 0, width: 100, height: 50 }, 1000, 500, 20, 0.1, 4);
  assert.equal(view.zoom, 1);
  assert.deepEqual(toCanvas(view, 500, 250), { x: 50, y: 25 });

  const big = fit({ x: -1000, y: 0, width: 4000, height: 1000 }, 1000, 500, 0, 0.1, 4);
  assert.equal(big.zoom, 0.25);
  const shown = visible(big, 1000, 500);
  assert.ok(shown.x <= -1000 && shown.x + shown.width >= 3000);
});

test("reveal moves only as far as it must", () => {
  const view = { x: 0, y: 0, zoom: 1 };
  assert.equal(reveal(view, { x: 10, y: 10, width: 20, height: 20 }, 500, 500, 8), view);
  const moved = reveal(view, { x: 600, y: 10, width: 50, height: 20 }, 500, 500, 10);
  assert.equal(moved.x, -160);
  assert.equal(moved.y, 0);
});
