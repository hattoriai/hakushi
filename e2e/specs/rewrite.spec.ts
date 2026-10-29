import { expect, test, type Page } from "@playwright/test";
import { center, drag, node, openCanvas, place } from "./support";

// on_change gives back another change: the canvas shows that one, not the
// person's (`?grid=app`: the app keeps the tables on squares of 20).

// Where the browser shows a node: its translate, as numbers.
async function shown(page: Page, id: string): Promise<{ x: number; y: number }> {
  const translate = await node(page, id).evaluate((el) => getComputedStyle(el).translate);
  const [x, y = "0px"] = translate.split(" ");
  return { x: parseFloat(x), y: parseFloat(y) };
}

test("a move the app puts on its grid lands there", async ({ page }) => {
  await openCanvas(page, "/?grid=app");
  const before = await place(page, "people");
  const header = node(page, "people").locator("header");
  const from = await center(header);
  await drag(page, from, { x: from.x + 47, y: from.y + 33 });

  await expect.poll(async () => (await place(page, "people")).x).not.toBe(before.x);
  const after = await place(page, "people");
  expect(after.x % 20).toBe(0);
  expect(after.y % 20).toBe(0);
  // The node shows where the server has it, not where it was let go.
  await expect.poll(() => shown(page, "people")).toEqual(after);
});

test("a move the app gives back as it was leaves the node where it was", async ({ page }) => {
  await openCanvas(page, "/?grid=app");
  const before = await place(page, "people");
  const header = node(page, "people").locator("header");
  const from = await center(header);
  // Less than half a square: back on the square it came from.
  await drag(page, from, { x: from.x + 6, y: from.y + 4 });
  await page.waitForTimeout(400);
  expect(await place(page, "people")).toEqual(before);
  await expect.poll(() => shown(page, "people")).toEqual(before);
});
