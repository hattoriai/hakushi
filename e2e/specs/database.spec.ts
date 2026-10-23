import { expect, test } from "@playwright/test";
import { center, drag, mod, node, place } from "./support";

// A database read from a server, as Lotus shows one (/database): tables
// with no places of their own, which the canvas lays out as it opens and
// people only arrange.

async function open(page: import("@playwright/test").Page, query = "") {
  await page.goto(`/database${query}`);
  await expect(page.locator("[data-phx-main].phx-connected")).toBeVisible();
  await expect(page.locator("#database[data-ui-tidied]")).toBeAttached({ timeout: 30_000 });
}

test("opens laid out: no table on another, and none shown before", async ({ page }) => {
  await page.goto("/database?n=60");
  // The server draws the tables hidden, all at one place, until they are laid out.
  await expect(page.locator("#database")).toHaveAttribute("data-tidy", "true");
  await expect(page.locator("#database[data-ui-tidied]")).toBeAttached({ timeout: 30_000 });
  await expect(node(page, "users")).toBeVisible();

  // The places the server keeps are the laid out ones.
  await expect.poll(async () => new Set(await page.locator("#database .hakushi-node").evaluateAll((els) => els.map((el) => el.getAttribute("data-x")))).size).toBeGreaterThan(10);
  const boxes = await page.locator("#database .hakushi-node").evaluateAll((els) =>
    els.map((el) => ({ x: Number(el.getAttribute("data-x")), y: Number(el.getAttribute("data-y")), w: (el as HTMLElement).offsetWidth, h: (el as HTMLElement).offsetHeight })),
  );
  for (let i = 0; i < boxes.length; i++)
    for (let j = i + 1; j < boxes.length; j++) {
      const a = boxes[i];
      const b = boxes[j];
      expect(a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h, `${i} and ${j}`).toBe(false);
    }
});

test("people arrange the tables, and change nothing else", async ({ page }) => {
  await open(page, "?n=12");
  const table = node(page, "users");
  // The tables read, not edited: no fields, no buttons to add a column.
  await expect(table.locator("input")).toHaveCount(0);
  await expect(table.locator(".hakushi-kit-add")).toHaveCount(0);
  await expect(page.locator(".hakushi-kit-bar, .hakushi-tools")).toHaveCount(0);

  // The opening layout is not something to undo.
  const opened = await place(page, "users");
  await page.locator("#database").focus();
  await page.keyboard.press(`${await mod(page)}+z`);
  await page.waitForTimeout(300);
  expect(await place(page, "users")).toEqual(opened);

  // A drag moves a table, and undo puts it back.
  const from = await center(table.locator(".hakushi-kit-table-head"));
  await drag(page, from, { x: from.x + 120, y: from.y + 60 });
  await expect.poll(() => place(page, "users")).not.toEqual(opened);
  await page.keyboard.press(`${await mod(page)}+z`);
  await expect.poll(() => place(page, "users")).toEqual(opened);

  // Delete does nothing.
  await table.locator(".hakushi-kit-table-head").click();
  await page.keyboard.press("Delete");
  await page.waitForTimeout(300);
  await expect(table).toHaveCount(1);
});

test("tidy up lays the tables out another way", async ({ page }) => {
  await open(page, "?n=30");
  await page.locator('#database [data-action="layouts"]').click();
  await page.locator("#database .hakushi-layout-menu").getByRole("menuitemradio", { name: "Grid" }).click();
  await expect(page.locator("#database .hakushi-status")).toHaveText(/Tidied up \d+ nodes/);
});
