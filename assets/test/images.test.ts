import { test } from "node:test";
import assert from "node:assert/strict";
import { aspectResize, cropOf, dragCrop, fitImage, fullOf, imageAddress, rowAt } from "../src/images";

test("a new image fits the view, and is no wider than 480", () => {
  assert.deepEqual(fitImage({ width: 200, height: 100 }, { width: 1000, height: 800 }), { width: 200, height: 100 });
  assert.deepEqual(fitImage({ width: 1600, height: 1000 }, { width: 2000, height: 2000 }), { width: 480, height: 300 });
  // A tall image in a short view: by its height.
  assert.deepEqual(fitImage({ width: 1000, height: 2000 }, { width: 2000, height: 500 }), { width: 150, height: 300 });
});

test("images added together are a row about the point", () => {
  const rects = rowAt([{ width: 100, height: 50 }, { width: 84, height: 80 }], { x: 0, y: 0 });
  assert.deepEqual(rects, [
    { x: -100, y: -25, width: 100, height: 50 },
    { x: 16, y: -40, width: 84, height: 80 },
  ]);
});

test("a resize keeps the aspect ratio: a corner by the side that moved most, a side about its middle", () => {
  const rect = { x: 0, y: 0, width: 300, height: 200 };
  assert.deepEqual(aspectResize(rect, "se", 60, 10, 1.5), { x: 0, y: 0, width: 360, height: 240 });
  assert.deepEqual(aspectResize(rect, "se", 10, 100, 1.5), { x: 0, y: 0, width: 450, height: 300 });
  // The north-west corner: the south-east one stays.
  assert.deepEqual(aspectResize(rect, "nw", -60, 0, 1.5), { x: -60, y: -40, width: 360, height: 240 });
  assert.deepEqual(aspectResize(rect, "e", 60, 0, 1.5), { x: 0, y: -20, width: 360, height: 240 });
  assert.deepEqual(aspectResize(rect, "n", 0, -40, 1.5), { x: -30, y: -40, width: 360, height: 240 });
  // No smaller than the least size.
  const small = aspectResize(rect, "se", -400, -400, 1.5);
  assert.equal(small.height, 24);
  assert.equal(small.width, 36);
});

test("a crop, as fractions of the file and as a box on the canvas", () => {
  const box = { x: 100, y: 50, width: 200, height: 100 };
  const full = fullOf(box, [0.5, 0.25, 0.5, 0.5]);
  assert.deepEqual(full, { x: -100, y: 0, width: 400, height: 200 });
  assert.deepEqual(cropOf(full, box), [0.5, 0.25, 0.5, 0.5]);
  assert.deepEqual(cropOf(full, full), [0, 0, 1, 1]);
});

test("a crop's box is dragged within the file", () => {
  const full = { x: 0, y: 0, width: 400, height: 200 };
  const box = { x: 100, y: 50, width: 200, height: 100 };
  assert.deepEqual(dragCrop(full, box, "move", 500, -500), { x: 200, y: 0, width: 200, height: 100 });
  assert.deepEqual(dragCrop(full, box, "w", -300, 0), { x: 0, y: 50, width: 300, height: 100 });
  assert.deepEqual(dragCrop(full, box, "se", 20, 500), { x: 100, y: 50, width: 220, height: 150 });
  // Never smaller than the least size.
  assert.deepEqual(dragCrop(full, box, "e", -400, 0), { x: 100, y: 50, width: 16, height: 100 });
});

test("an image's address is one http(s) URL", () => {
  assert.equal(imageAddress(" https://images.example.com/a.png\n"), "https://images.example.com/a.png");
  assert.equal(imageAddress("http://127.0.0.1:4099/a.png"), "http://127.0.0.1:4099/a.png");
  assert.equal(imageAddress("javascript:alert(1)"), null);
  assert.equal(imageAddress("see https://example.com/a.png"), null);
  assert.equal(imageAddress("Rope, brass"), null);
});
