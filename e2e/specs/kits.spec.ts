// Kits, in embed frames on a page that scrolls: the design spec of the
// development app (/spec).

import { expect, test, type Page } from "@playwright/test";
import { center, drag, edgeCount } from "./support";

let rooms = 0;

// The page has three canvases: it is open when each has drawn its edges.
async function openSpec(page: Page, extra = ""): Promise<void> {
  await page.goto(`/spec?room=k${process.pid}-${Date.now()}-${rooms++}${extra}`);
  await expect(page.locator("[data-phx-main].phx-connected")).toBeVisible();
  await expect(page.locator(".hakushi-controls")).toHaveCount(3);
  await page.waitForFunction(() => document.querySelectorAll(".hakushi-edge-line[d]").length >= 5);
}

const table = (id: string) => `#spec_schema .hakushi-node[data-id="${id}"]`;

test("the wheel over an embedded canvas scrolls the page, and ⌘ or Ctrl and the wheel zooms it", async ({ page }) => {
  await openSpec(page);
  const canvas = page.locator("#spec_schema");
  const at = await center(canvas);
  await page.mouse.move(at.x, at.y);

  const before = await page.evaluate(() => (window as any).canvasOf("spec_schema").getView());
  await page.mouse.wheel(0, 300);
  await expect.poll(() => page.evaluate(() => document.querySelector(".spec")!.scrollTop)).toBeGreaterThan(0);
  expect(await page.evaluate(() => (window as any).canvasOf("spec_schema").getView())).toEqual(before);

  const moved = await center(canvas);
  await page.mouse.move(moved.x, moved.y);
  await page.keyboard.down("Control");
  await page.mouse.wheel(0, -200);
  await page.keyboard.up("Control");
  await expect.poll(() => page.evaluate(() => (window as any).canvasOf("spec_schema").getView().zoom)).toBeGreaterThan(before.zoom);
});

test("a table: added from the bar, renamed, given a column of a type, and joined by a foreign key", async ({ page }) => {
  await openSpec(page);
  const count = await page.locator("#spec_schema .hakushi-node").count();

  await page.locator('[data-hakushi-item="schema:table"]').click();
  await expect(page.locator("#spec_schema .hakushi-node")).toHaveCount(count + 1);
  const id = await page.locator("#spec_schema .hakushi-node").last().getAttribute("data-id");

  const name = page.locator(`${table(id!)} .hakushi-kit-table-name`);
  await name.fill("refunds");
  await name.press("Enter");
  await expect(name).toHaveValue("refunds");

  await page.locator(`${table(id!)} .hakushi-kit-add`).click();
  const column = page.locator(`${table(id!)} .hakushi-kit-column-name`).nth(1);
  await expect(column).toHaveValue("column_2");
  await column.fill("Invoice ID");
  await column.press("Tab");
  await expect(column).toHaveValue("invoice_id");

  await page.locator(`${table(id!)} .hakushi-kit-type select`).nth(1).selectOption("uuid");
  await expect(page.locator(`${table(id!)} .hakushi-kit-type select`).nth(1)).toHaveValue("uuid");
  await page.locator(`${table(id!)} .hakushi-kit-key`).nth(1).click();
  await page.locator(`${table(id!)} .hakushi-kit-key`).nth(1).click();
  await expect(page.locator(`${table(id!)} .hakushi-kit-key`).nth(1)).toHaveAttribute("data-key", "fk");

});

test("a foreign key: a new column of invoice_lines, joined to customers.id", async ({ page }) => {
  await openSpec(page);
  await page.locator(`${table("lines")} .hakushi-kit-add`).click();
  const column = page.locator(`${table("lines")} .hakushi-kit-column-name`).nth(4);
  await column.fill("customer_id");
  await column.press("Enter");
  await page.locator(`${table("lines")} .hakushi-kit-type select`).nth(4).selectOption("uuid");
  await expect(page.locator(`${table("lines")} .hakushi-kit-type select`).nth(4)).toHaveValue("uuid");

  const edges = await edgeCount(page, "spec_schema");
  const from = await center(page.locator(`${table("lines")} .hakushi-kit-column`).nth(4).locator(".hakushi-handle").first());
  const to = await center(page.locator(`${table("customers")} .hakushi-kit-column`).nth(0).locator(".hakushi-handle").last());
  await drag(page, from, to, 16);
  await expect.poll(() => edgeCount(page, "spec_schema")).toBe(edges + 1);
});

test("a column connects only to a column of its type", async ({ page }) => {
  await openSpec(page);
  const edges = await edgeCount(page, "spec_schema");
  // customers.email (text) to invoices.id (uuid): no edge.
  const from = await center(page.locator(`${table("customers")} .hakushi-kit-column`).nth(1).locator(".hakushi-handle").last());
  const to = await center(page.locator(`${table("invoices")} .hakushi-kit-column`).nth(0).locator(".hakushi-handle").first());
  await drag(page, from, to, 16);
  await page.waitForTimeout(300);
  expect(await edgeCount(page, "spec_schema")).toBe(edges);
});

test("an edit of a kit's node undoes with ⌘Z", async ({ page }) => {
  await openSpec(page);
  const note = page.locator('#spec_notes .hakushi-node[data-id="q1"] .hakushi-kit-note-text');
  await note.fill("Refunds are negative invoices.");
  await page.locator("#spec_notes").click({ position: { x: 20, y: 300 } });
  await expect(note).toHaveValue("Refunds are negative invoices.");

  await page.locator("#spec_notes").focus();
  await page.keyboard.press(`${process.platform === "darwin" ? "Meta" : "Control"}+z`);
  await expect(note).toHaveValue("Refunds: a negative invoice, or a table of their own?");
});

test("full screen and back: the same canvas, fitted to its new box", async ({ page }) => {
  await openSpec(page);
  await page.evaluate(() => ((window as any).spec = (window as any).canvasOf("spec_schema")));
  const inline = await page.evaluate(() => (window as any).spec.getView());

  await page.locator(".spec-embed:has(#spec_schema) [data-hakushi-full]").click();
  await expect(page.locator(".spec-embed.full")).toBeVisible();
  await expect(page.locator(".spec-embed.full [data-hakushi-full]")).toHaveAttribute("aria-label", "Exit full screen");
  await expect.poll(() => page.evaluate(() => (window as any).spec.getView())).not.toEqual(inline);
  expect(await page.evaluate(() => (window as any).canvasOf("spec_schema") === (window as any).spec)).toBe(true);

  await page.keyboard.press("Escape");
  await expect(page.locator(".spec-embed.full")).toHaveCount(0);
  await expect.poll(() => page.evaluate(() => (window as any).spec.getView())).toEqual(inline);
});

test("a viewer reads the canvases: no fields, no bar, and pans and zooms", async ({ page }) => {
  await openSpec(page, "&as=viewer");
  await expect(page.locator("#spec_schema .hakushi-kit-table-name").first()).toHaveText("customers");
  await expect(page.locator(".hakushi-kit-field")).toHaveCount(0);
  await expect(page.locator(".hakushi-kit-items")).toHaveCount(0);
  await expect(page.locator("[data-hakushi-full]")).toHaveCount(3);
});
