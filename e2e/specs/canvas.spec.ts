import { expect, test } from "@playwright/test";
import { center, drag, edgeCount, node, openCanvas, zoom } from "./support";

test("draws the nodes of the server and their edges", async ({ page }) => {
  await openCanvas(page, "/");
  await expect(page.locator("#schema .hakushi-node")).toHaveCount(6);
  expect(await edgeCount(page, "schema")).toBe(6);
  await expect(page.locator("#schema .hakushi-edge-line[d]")).toHaveCount(6);
  await expect(page.locator("#schema")).toHaveAttribute("role", "application");
  await expect(node(page, "tasks")).toHaveAttribute("aria-label", "tasks");
});

test("zooms with the controls, the keys and the wheel with Ctrl, and fits", async ({ page }) => {
  await openCanvas(page, "/board");
  const start = await zoom(page);
  await page.locator('[data-action="zoom-in"]').click();
  await expect.poll(() => zoom(page)).toBeGreaterThan(start);
  await page.locator('[data-action="zoom-reset"]').click();
  await expect.poll(() => zoom(page)).toBe(100);

  const box = (await page.locator("#board").boundingBox())!;
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await page.keyboard.down("Control");
  await page.mouse.wheel(0, 300);
  await page.keyboard.up("Control");
  await expect.poll(() => zoom(page)).toBeLessThan(100);

  await page.locator("#board").focus();
  await page.keyboard.press("+");
  await page.locator('[data-action="fit"]').click();
  await expect.poll(() => zoom(page)).toBeLessThanOrEqual(100);
});

test("pans with the wheel, and with Space and a drag", async ({ page }) => {
  await openCanvas(page, "/board");
  const before = (await node(page, "tide").boundingBox())!;
  const box = (await page.locator("#board").boundingBox())!;
  await page.mouse.move(box.x + 40, box.y + box.height - 60);
  await page.mouse.wheel(0, 200);
  await expect.poll(async () => (await node(page, "tide").boundingBox())!.y).toBeLessThan(before.y - 100);

  await page.locator("#board").focus();
  await page.keyboard.down(" ");
  const y = (await node(page, "tide").boundingBox())!.y;
  await drag(page, { x: box.x + 60, y: box.y + box.height - 80 }, { x: box.x + 160, y: box.y + box.height - 20 });
  await page.keyboard.up(" ");
  await expect.poll(async () => (await node(page, "tide").boundingBox())!.y).toBeGreaterThan(y + 40);
});

test("selects with a click, Shift, and a box", async ({ page }) => {
  await openCanvas(page, "/board");
  await node(page, "rope").locator(".note").click();
  await expect(node(page, "rope")).toHaveAttribute("data-ui-selected", "");
  await node(page, "tide").locator(".note").click({ modifiers: ["Shift"] });
  await expect(page.locator("#board .hakushi-node[data-ui-selected]")).toHaveCount(2);

  // A box from the empty paper over three nodes.
  const a = (await node(page, "tide").boundingBox())!;
  const b = (await node(page, "type").boundingBox())!;
  await drag(page, { x: a.x - 20, y: a.y - 20 }, { x: b.x + 20, y: b.y + 20 });
  await expect(node(page, "palette")).toHaveAttribute("data-ui-selected", "");
  await expect(node(page, "wayfinding")).not.toHaveAttribute("data-ui-selected", "");

  await page.keyboard.press("Escape");
  await expect(page.locator("#board .hakushi-node[data-ui-selected]")).toHaveCount(0);
});

test("the minimap moves the view", async ({ page }) => {
  await openCanvas(page, "/scale");
  const before = (await node(page, "n0").boundingBox())!;
  const map = await center(page.locator(".hakushi-minimap"));
  await page.mouse.click(map.x + 60, map.y + 40);
  await expect.poll(async () => (await node(page, "n0").boundingBox())?.x ?? -1e9).not.toBe(before.x);
});
