import { expect, test, type Page } from "@playwright/test";
import { center, node, openCanvas, zoom } from "./support";

// The app hears what the person selects and sees (on_select, on_viewport),
// and moves the view and the selection itself (Hakushi.Live.fit/2, focus/3).

const hint = (page: Page) => page.locator(".top .hint");

// A node's middle, as a share of the canvas's box: 0.5 is its middle.
async function placeOnScreen(page: Page, id: string): Promise<{ x: number; y: number }> {
  const box = (await page.locator("#schema").boundingBox())!;
  const c = await center(node(page, id));
  return { x: (c.x - box.x) / box.width, y: (c.y - box.y) / box.height };
}

test("on_select hears a click, Shift and Escape", async ({ page }) => {
  await openCanvas(page, "/");
  await node(page, "tasks").locator("header").click();
  await expect(hint(page)).toHaveAttribute("data-selected", "tasks");
  await expect(hint(page)).toContainText("Selected: tasks");

  await node(page, "clients").locator("header").click({ modifiers: ["Shift"] });
  await expect(hint(page)).toHaveAttribute("data-selected", /tasks/);
  await expect(hint(page)).toHaveAttribute("data-selected", /clients/);

  await page.keyboard.press("Escape");
  await expect(hint(page)).toHaveAttribute("data-selected", "");
});

test("on_viewport hears the view when it comes to rest", async ({ page }) => {
  await openCanvas(page, "/");
  await expect(hint(page)).toHaveAttribute("data-zoom", /\d/);
  await page.locator("#schema").focus();
  await page.locator('[data-action="zoom-reset"]').click();
  await expect(hint(page)).toHaveAttribute("data-zoom", "1");
  await page.locator('[data-action="zoom-in"]').click();
  await expect.poll(async () => Number(await hint(page).getAttribute("data-zoom"))).toBeGreaterThan(1);
});

test("focus/3 brings a table to the middle and selects it, and fit/2 shows them all", async ({ page }) => {
  await openCanvas(page, "/");
  await page.locator('[data-action="zoom-reset"]').click();
  await page.locator('[data-action="zoom-in"]').click();
  await page.locator('[data-action="zoom-in"]').click();
  const before = await zoom(page);

  await page.locator("#find input").fill("time");
  await page.locator("#find input").press("Enter");
  await expect(node(page, "time_entries")).toHaveAttribute("data-ui-selected", "");
  await expect
    .poll(async () => {
      const at = await placeOnScreen(page, "time_entries");
      return Math.abs(at.x - 0.5) < 0.05 && Math.abs(at.y - 0.5) < 0.05;
    })
    .toBe(true);
  // A selection of the app is not news to it.
  await expect(hint(page)).toHaveAttribute("data-selected", "");
  // It kept its zoom, the table fitting at it.
  expect(await zoom(page)).toBeLessThanOrEqual(before);

  await page.getByRole("button", { name: "Show all" }).click();
  await expect.poll(() => zoom(page)).toBeLessThan(before);
  // Every table on the screen, once the view is there.
  await expect
    .poll(async () => {
      for (const id of ["tasks", "clients", "time_entries", "invoices"]) {
        const at = await placeOnScreen(page, id);
        if (at.x <= 0 || at.x >= 1 || at.y <= 0 || at.y >= 1) return false;
      }
      return true;
    })
    .toBe(true);
});
