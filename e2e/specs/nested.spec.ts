import { expect, test, type Page } from "@playwright/test";
import { node, openCanvas } from "./support";

// /nested: groups in groups, laid out by ELK (registerLayout), folded in
// place (Hakushi.Graph.fold/2), edges that jump (jumps) and a mark's class.

async function box(page: Page, id: string) {
  const b = await node(page, id).boundingBox();
  if (!b) throw new Error(`${id} is not shown`);
  return b;
}

const inside = (a: { x: number; y: number; width: number; height: number }, b: { x: number; y: number; width: number; height: number }) =>
  a.x >= b.x - 0.5 && a.y >= b.y - 0.5 && a.x + a.width <= b.x + b.width + 0.5 && a.y + a.height <= b.y + b.height + 0.5;

async function opened(page: Page) {
  await openCanvas(page, "/nested");
  await expect(page.locator("#nested")).toHaveAttribute("data-ui-tidied", "");
}

test("ELK lays out the nodes in their groups, and the groups around them", async ({ page }) => {
  await opened(page);
  expect(inside(await box(page, "orders-api"), await box(page, "orders"))).toBe(true);
  expect(inside(await box(page, "orders"), await box(page, "cluster"))).toBe(true);
  expect(inside(await box(page, "ledger"), await box(page, "data"))).toBe(true);
  expect(inside(await box(page, "browser"), await box(page, "cluster"))).toBe(false);
  // Left to right: the browser, the edge, the cluster, the data.
  expect((await box(page, "browser")).x).toBeLessThan((await box(page, "cdn")).x);
  expect((await box(page, "gateway")).x).toBeLessThan((await box(page, "orders-api")).x);
  expect((await box(page, "orders-api")).x).toBeLessThan((await box(page, "ledger")).x);
  // The edges go along the axes, ELK's way: no curve in their paths.
  const curved = await page.$$eval("#nested .hakushi-edge-line", (lines) => lines.filter((l) => /C/.test(l.getAttribute("d") ?? "")).length);
  expect(curved).toBe(0);
});

test("a group folds and unfolds in place, and the canvas lays out again", async ({ page }) => {
  await opened(page);
  // Search opens folded: its nodes are not there, and its edges go to it.
  await expect(node(page, "search-api")).toHaveCount(0);
  await expect(node(page, "search")).toHaveAttribute("data-folded", "true");
  await expect(page.locator('#nested .hakushi-edge[data-edge="gateway-search-api"]')).toHaveCount(1);

  await page.locator('[data-fold="search"]').click();
  await expect(node(page, "search-api")).toHaveCount(1);
  await expect(page.locator('[data-fold="search"]')).toHaveAttribute("aria-expanded", "true");
  await expect.poll(async () => inside(await box(page, "search-api"), await box(page, "search"))).toBe(true);
  await expect.poll(async () => inside(await box(page, "search"), await box(page, "cluster"))).toBe(true);

  await page.locator('[data-fold="billing"]').click();
  await expect(node(page, "billing-worker")).toHaveCount(0);
  await expect(page.locator('[data-fold="billing"]')).toHaveAttribute("aria-expanded", "false");
  // Folded, it is as small as its title.
  await expect.poll(async () => (await box(page, "billing")).height).toBeLessThan(60);
});

test("a mark's class styles an edge, and the edges jump where they cross", async ({ page }) => {
  await opened(page);
  await expect(page.locator('#nested .hakushi-edge.via-queue[data-edge="orders-api-queue"]')).toHaveCount(1);
  const dash = await page.locator('#nested .hakushi-edge[data-edge="orders-api-queue"] .hakushi-edge-line').evaluate((l) => getComputedStyle(l).strokeDasharray);
  expect(dash).not.toBe("none");
  await expect
    .poll(() => page.$$eval("#nested .hakushi-edge-line", (lines) => lines.some((l) => /A5,5 0 0 [01]/.test(l.getAttribute("d") ?? ""))))
    .toBe(true);
});

test("a patch of a node keeps the page's layout of a read-only canvas", async ({ page }) => {
  await opened(page);
  const before = await box(page, "queue");
  // The trace marks nodes and edges: the server patches them.
  await page.locator("#trace").click();
  await expect(page.locator("#nested")).toHaveAttribute("data-spotlight", "true");
  await expect(page.locator('#nested .hakushi-edge[data-edge="browser-cdn"]')).toHaveAttribute("data-mark-status", "running");
  const after = await box(page, "queue");
  expect(Math.round(after.x)).toBe(Math.round(before.x));
  expect(Math.round(after.y)).toBe(Math.round(before.y));
});
