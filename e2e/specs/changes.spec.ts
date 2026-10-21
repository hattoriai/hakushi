import { expect, test } from "@playwright/test";
import { center, drag, edgeCount, mod, node, openCanvas, place } from "./support";

test("a drag moves a node on the server, and it stays after a reload", async ({ page }) => {
  const room = await openCanvas(page, "/board");
  const before = await place(page, "rope");
  const at = await center(node(page, "rope").locator(".note"));
  await drag(page, at, { x: at.x + 130, y: at.y + 75 });
  // The moodboard snaps to its grid of 20.
  await expect.poll(async () => (await place(page, "rope")).x).not.toBe(before.x);
  const after = await place(page, "rope");
  expect(after.x % 20).toBe(0);
  expect(after.y % 20).toBe(0);

  await openCanvas(page, "/board", room);
  expect(await place(page, "rope")).toEqual(after);
});

test("undo and redo take a move back and do it again", async ({ page }) => {
  await openCanvas(page, "/board");
  const before = await place(page, "rope");
  const at = await center(node(page, "rope").locator(".note"));
  await drag(page, at, { x: at.x + 200, y: at.y });
  await expect.poll(async () => (await place(page, "rope")).x).toBeGreaterThan(before.x + 100);
  const moved = await place(page, "rope");

  await page.keyboard.press(`${await mod(page)}+z`);
  await expect.poll(async () => (await place(page, "rope")).x).toBe(before.x);
  await page.keyboard.press(`${await mod(page)}+Shift+z`);
  await expect.poll(async () => (await place(page, "rope")).x).toBe(moved.x);
});

test("connects a column to a column of its type, and offers no other", async ({ page }) => {
  await openCanvas(page, "/");
  const edges = await edgeCount(page, "schema");
  await node(page, "tasks").hover();
  const from = page.locator('[data-id="tasks"] [data-column="estimate"] .hakushi-handle[data-side="right"]');
  const to = page.locator('[data-id="time_entries"] [data-column="minutes"] .hakushi-handle[data-side="left"]');
  const a = await center(from);
  const b = await center(to);
  await page.mouse.move(a.x, a.y);
  await page.mouse.down();
  await page.mouse.move(a.x + 40, a.y + 40, { steps: 4 });

  // While drawing: the integer columns may be ends, the others not.
  await expect(to).toHaveAttribute("data-ui-valid", "");
  await expect(page.locator('[data-id="time_entries"] [data-column="logged_on"] .hakushi-handle').first()).not.toHaveAttribute("data-ui-valid", "");
  await expect(page.locator('[data-id="people"] [data-column="name"] .hakushi-handle').first()).not.toHaveAttribute("data-ui-valid", "");

  await page.mouse.move(b.x, b.y, { steps: 8 });
  await page.mouse.up();
  await expect.poll(() => edgeCount(page, "schema")).toBe(edges + 1);
  await expect(page.locator('#schema-edge-data > i[data-source="tasks"][data-source-handle="estimate"][data-target="time_entries"]')).toHaveCount(1);
});

test("deletes with the key, and the server takes the edges with the node", async ({ page }) => {
  await openCanvas(page, "/");
  await node(page, "invoices").locator("header").click();
  await page.keyboard.press("Delete");
  await expect(node(page, "invoices")).toHaveCount(0);
  await expect.poll(() => edgeCount(page, "schema")).toBe(5);
  await page.keyboard.press(`${await mod(page)}+z`);
  await expect(node(page, "invoices")).toHaveCount(1);
  await expect.poll(() => edgeCount(page, "schema")).toBe(6);
});

test("duplicates and pastes with new nodes", async ({ page }) => {
  await openCanvas(page, "/board");
  await node(page, "tide").locator(".note").click();
  await page.keyboard.press(`${await mod(page)}+d`);
  await expect(page.locator("#board .hakushi-node")).toHaveCount(10);
  // The copy is the selection.
  await expect(page.locator("#board .hakushi-node[data-ui-selected]")).toHaveCount(1);
  await expect(node(page, "tide")).not.toHaveAttribute("data-ui-selected", "");

  await page.keyboard.press(`${await mod(page)}+c`);
  await page.mouse.move(700, 300);
  await page.keyboard.press(`${await mod(page)}+v`);
  await expect(page.locator("#board .hakushi-node")).toHaveCount(11);
});

test("an item of the palette dragged onto the canvas becomes a node", async ({ page }) => {
  await openCanvas(page, "/workflow");
  const nodes = await page.locator("#workflow .hakushi-node").count();
  const item = await center(page.locator('[data-hakushi-item="webhook"]'));
  const box = (await page.locator("#workflow").boundingBox())!;
  await drag(page, item, { x: box.x + box.width / 2, y: box.y + 80 }, 15);
  await expect(page.locator("#workflow .hakushi-node")).toHaveCount(nodes + 1);
  await expect(page.locator('#workflow .hakushi-node[data-type="webhook"]')).toHaveAttribute("data-ui-selected", "");

  // Enter on an item puts it in the middle.
  await page.locator('[data-hakushi-item="wait"]').focus();
  await page.keyboard.press("Enter");
  await expect(page.locator("#workflow .hakushi-node")).toHaveCount(nodes + 2);
});

test("a viewer pans and selects, and changes nothing", async ({ page }) => {
  await openCanvas(page, "/board", undefined, "&as=viewer");
  const before = await place(page, "rope");
  const at = await center(node(page, "rope").locator(".note"));
  await drag(page, at, { x: at.x + 200, y: at.y });
  await expect(node(page, "rope")).toHaveAttribute("data-ui-selected", "");
  expect(await place(page, "rope")).toEqual(before);
  await expect(page.locator('[data-action="undo"]')).toHaveCount(0);
});
