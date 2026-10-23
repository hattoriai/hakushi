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

test("the menu by tidy up lays out another way, and the next tidy up goes that way too", async ({ page }) => {
  await openCanvas(page, "/workflow");
  const menuButton = page.locator('#workflow [data-action="layouts"]');
  await expect(menuButton).toHaveAttribute("aria-haspopup", "menu");
  await menuButton.click();
  const menu = page.locator("#workflow .hakushi-layout-menu");
  await expect(menu.getByRole("menuitemradio")).toHaveText(["Layers, left to right", "Layers, top to bottom", "Spread out", "Grid"]);
  await expect(menu.getByRole("menuitemradio", { name: "Layers, left to right" })).toHaveAttribute("aria-checked", "true");

  await menu.getByRole("menuitemradio", { name: "Grid" }).click();
  await expect(menu).toHaveCount(0);
  await expect(page.locator("#workflow .hakushi-status")).toHaveText(/Tidied up 7 nodes/);
  // A grid: the steps share rows and columns.
  const ids = ["receipt", "paid", "big", "lead", "thanks", "close", "wait"];
  await expect
    .poll(async () => {
      const places = await Promise.all(ids.map((id) => place(page, id)));
      return new Set(places.map((p) => p.y)).size < ids.length && new Set(places.map((p) => p.x)).size < ids.length;
    })
    .toBe(true);
  const grid = await Promise.all(ids.map((id) => place(page, id)));

  // Shift+L lays out as a grid again: nothing moves.
  await page.locator("#workflow").focus();
  await page.keyboard.press("Shift+L");
  await page.waitForTimeout(400);
  expect(await Promise.all(ids.map((id) => place(page, id)))).toEqual(grid);

  await menuButton.click();
  await expect(menu.getByRole("menuitemradio", { name: "Grid" })).toHaveAttribute("aria-checked", "true");
  await page.keyboard.press("Escape");
  await expect(menu).toHaveCount(0);
  await expect(menuButton).toBeFocused();
});

test("spread out places the steps by forces, none on another", async ({ page }) => {
  await openCanvas(page, "/workflow");
  await page.locator('#workflow [data-action="layouts"]').click();
  await page.locator("#workflow .hakushi-layout-menu").getByRole("menuitemradio", { name: "Spread out" }).click();
  await expect(page.locator("#workflow .hakushi-status")).toHaveText(/Tidied up 7 nodes/);
  const boxes = await page.locator("#workflow .hakushi-node").evaluateAll((els) => els.map((el) => el.getBoundingClientRect().toJSON()));
  for (let i = 0; i < boxes.length; i++)
    for (let j = i + 1; j < boxes.length; j++) {
      const a = boxes[i];
      const b = boxes[j];
      expect(a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom).toBe(false);
    }
});
