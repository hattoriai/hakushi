import { expect, test } from "@playwright/test";
import { center, drag, mod, node, openCanvas, place } from "./support";

// A node that opens (its slot `opens`): the moodboard's frames open as a
// canvas of their own, their inside (Hakushi.Graph.subgraph/2), and ⌘↑
// goes back to the board, with what changed inside.

test("a frame opens by its title, its inside changes, and ⌘↑ goes back", async ({ page }) => {
  const room = await openCanvas(page, "/board");
  const before = await place(page, "wayfinding");
  await node(page, "signage").locator("[data-hakushi-drag]").dblclick();

  await expect(page).toHaveURL(/frame=signage/);
  const inside = page.locator("#frame-signage");
  await expect(inside).toBeVisible();
  await expect(inside.locator('.hakushi-node[data-id="wayfinding"]')).toBeVisible();
  await expect(inside.locator('.hakushi-node[data-id="signage"]')).toHaveCount(0);
  await expect(page.locator(".hakushi-path [aria-current=page]")).toHaveText("Signage");
  // Its places are the frame's: its corner is the canvas's 0, 0.
  const at = Number(await inside.locator('.hakushi-node[data-id="wayfinding"]').getAttribute("data-x"));
  expect(at).toBe(before.x - 800);

  const from = await center(inside.locator('.hakushi-node[data-id="wayfinding"]'));
  await drag(page, from, { x: from.x + 40, y: from.y + 40 });
  await expect.poll(async () => Number(await inside.locator('.hakushi-node[data-id="wayfinding"]').getAttribute("data-x"))).toBeGreaterThan(at);

  await inside.focus();
  await page.keyboard.press(`${await mod(page)}+ArrowUp`);
  await expect(page).not.toHaveURL(/frame=/);
  await expect(page.locator("#board")).toBeVisible();
  await expect.poll(async () => (await place(page, "wayfinding")).x).toBeGreaterThan(before.x);
  expect(room).toBeTruthy();
});

test("the opener of a frame opens it, and the path goes back", async ({ page }) => {
  await openCanvas(page, "/board");
  await node(page, "signage").locator(".hakushi-opener").click();
  await expect(page.locator("#frame-signage")).toBeVisible();
  await page.locator(".hakushi-path a", { hasText: "Moodboard" }).click();
  await expect(page.locator("#board")).toBeVisible();
});

test("a double click inside a frame still makes a note", async ({ page }) => {
  await openCanvas(page, "/board");
  const count = await page.locator("#board .hakushi-node").count();
  const box = (await node(page, "signage").boundingBox())!;
  await page.mouse.dblclick(box.x + box.width / 2, box.y + box.height - 12);
  await expect(page.locator("#board .hakushi-node")).toHaveCount(count + 1);
  await expect(page).not.toHaveURL(/frame=/);
});
