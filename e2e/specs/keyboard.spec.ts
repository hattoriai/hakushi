import { expect, test } from "@playwright/test";
import { edgeCount, node, openCanvas, place } from "./support";

test("Tab goes from node to node, and the arrows move the focused one", async ({ page }) => {
  await openCanvas(page, "/board");
  await page.locator("#board").focus();
  await page.keyboard.press("Tab");
  await expect(node(page, "title")).toBeFocused();
  await page.keyboard.press("Tab");
  await expect(node(page, "tide")).toBeFocused();
  await expect(node(page, "tide")).toHaveAttribute("data-ui-selected", "");
  await expect(node(page, "tide")).toHaveAttribute("aria-description", /1 connection/);

  const before = await place(page, "tide");
  // The moodboard snaps: an arrow moves a square of the grid.
  await page.keyboard.press("ArrowRight");
  await page.keyboard.press("ArrowRight");
  await page.keyboard.press("ArrowDown");
  await expect.poll(async () => await place(page, "tide")).toEqual({ x: before.x + 40, y: before.y + 20 });
  await expect(page.locator("#board .hakushi-status")).toHaveText("Moved tide.".replace("tide", (await node(page, "tide").getAttribute("aria-label"))!));
});

test("Alt and an arrow go to the nearest node that way", async ({ page }) => {
  await openCanvas(page, "/board");
  await page.locator("#board").focus();
  await page.keyboard.press("Tab");
  await page.keyboard.press("Tab");
  await expect(node(page, "tide")).toBeFocused();
  await page.keyboard.press("Alt+ArrowDown");
  await expect(node(page, "rope")).toBeFocused();
  await page.keyboard.press("Alt+ArrowRight");
  await expect(node(page, "type")).toBeFocused();
});

test("C connects the focused node to one chosen with the arrows", async ({ page }) => {
  await openCanvas(page, "/workflow");
  const edges = await edgeCount(page, "workflow");
  await page.locator("#workflow").focus();
  // The first node: the trigger, which connects to any step.
  await page.keyboard.press("Tab");
  await expect(node(page, "paid")).toBeFocused();
  await page.keyboard.press("c");
  await expect(page.locator("#workflow .hakushi-status")).toContainText("Connecting from");
  await page.keyboard.press("ArrowRight");
  await expect(page.locator("#workflow .hakushi-status")).toContainText("Connect to");
  await page.keyboard.press("Enter");
  await expect.poll(() => edgeCount(page, "workflow")).toBe(edges + 1);
});

test("Escape in a connection takes it back", async ({ page }) => {
  await openCanvas(page, "/workflow");
  const edges = await edgeCount(page, "workflow");
  await page.locator("#workflow").focus();
  await page.keyboard.press("Tab");
  await page.keyboard.press("c");
  await page.keyboard.press("Escape");
  await expect(page.locator("#workflow .hakushi-status")).toHaveText("Connection cancelled.");
  expect(await edgeCount(page, "workflow")).toBe(edges);
});
