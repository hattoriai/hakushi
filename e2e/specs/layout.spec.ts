import { expect, test } from "@playwright/test";
import { mod, node, openCanvas, place } from "./support";

test("tidy up lays the steps out in layers, as one change that undoes", async ({ page }) => {
  await openCanvas(page, "/workflow");
  const before = await place(page, "receipt");
  await page.locator('[data-action="layout"]').click();
  await expect(page.locator("#workflow .hakushi-status")).toHaveText(/Tidied up 7 nodes/);
  // Each step right of the step before it.
  const order = ["paid", "big", "lead", "thanks", "close", "wait"];
  await expect
    .poll(async () => {
      const xs = await Promise.all(order.map(async (id) => (await place(page, id)).x));
      return xs.every((x, i) => i === 0 || x > xs[i - 1]);
    })
    .toBe(true);
  // The two ways of the condition in one layer.
  expect((await place(page, "lead")).x).toBe((await place(page, "receipt")).x);

  await page.keyboard.press(`${await mod(page)}+z`);
  await expect.poll(() => place(page, "receipt")).toEqual(before);
});

test("Shift+L tidies the selection only", async ({ page }) => {
  await openCanvas(page, "/workflow");
  const wait = await place(page, "wait");
  await node(page, "paid").locator("strong").click();
  await node(page, "big").locator("strong").click({ modifiers: ["Shift"] });
  await page.keyboard.press("Shift+L");
  await expect(page.locator("#workflow .hakushi-status")).toHaveText(/Tidied up 2 nodes/);
  expect(await place(page, "wait")).toEqual(wait);
});

test("downloads the canvas as a PNG of every node", async ({ page }) => {
  await openCanvas(page, "/workflow");
  const [download] = await Promise.all([page.waitForEvent("download"), page.locator('[data-action="export"]').click()]);
  expect(download.suggestedFilename()).toBe("workflow.png");
  const path = await download.path();
  await download.saveAs("test-results/workflow-export.png");
  const { readFileSync } = await import("node:fs");
  const png = readFileSync(path);
  expect(png.subarray(1, 4).toString()).toBe("PNG");
  const width = png.readUInt32BE(16);
  const height = png.readUInt32BE(20);
  // The seven steps span about 1,800 by 400 pixels; the PNG is at twice that.
  expect(width).toBeGreaterThan(3000);
  expect(height).toBeGreaterThan(600);
});

test("exports an SVG with the nodes' own HTML", async ({ page }) => {
  await openCanvas(page, "/board");
  const svg = await page.evaluate(async () => {
    const canvas = (window as unknown as { canvasOf(id: string): { exportImage(o: object): Promise<Blob> } }).canvasOf("board");
    return (await canvas.exportImage({ format: "svg" })).text();
  });
  expect(svg).toContain("<foreignObject");
  expect(svg).toContain("Harbour Museum");
  expect(svg).toContain("hakushi-edge-line");
  expect(svg).not.toContain(`data-ui-selected=""`);
});
