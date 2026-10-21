import { expect, test } from "@playwright/test";
import { center, drag, mod, node, openCanvas, place } from "./support";

test("a frame moves with what is in it", async ({ page }) => {
  await openCanvas(page, "/board");
  const frame = await place(page, "signage");
  const note = await place(page, "wayfinding");
  const grip = await center(node(page, "signage").locator("[data-hakushi-drag]"));
  await drag(page, grip, { x: grip.x - 200, y: grip.y + 100 });
  await expect.poll(async () => (await place(page, "signage")).x).not.toBe(frame.x);
  const moved = await place(page, "signage");
  await expect.poll(() => place(page, "wayfinding")).toEqual({ x: note.x + moved.x - frame.x, y: note.y + moved.y - frame.y });

  // One undo takes the frame and its notes back.
  await page.keyboard.press(`${await mod(page)}+z`);
  await expect.poll(() => place(page, "wayfinding")).toEqual(note);
});

test("a note dropped on a frame goes in it, and dragged out comes out", async ({ page }) => {
  await openCanvas(page, "/board");
  await expect(node(page, "rope")).not.toHaveAttribute("data-parent", /./);
  const from = await center(node(page, "rope").locator(".note"));
  const frame = (await node(page, "signage").boundingBox())!;
  await page.mouse.move(from.x, from.y);
  await page.mouse.down();
  await page.mouse.move(from.x + 50, from.y, { steps: 3 });
  await page.mouse.move(frame.x + frame.width / 2, frame.y + frame.height - 40, { steps: 12 });
  await expect(node(page, "signage")).toHaveAttribute("data-ui-drop-target", "");
  await page.mouse.up();
  await expect(node(page, "rope")).toHaveAttribute("data-parent", "signage");
  await expect(node(page, "signage")).not.toHaveAttribute("data-ui-drop-target", "");

  // Out again.
  const inside = await center(node(page, "rope").locator(".note"));
  await drag(page, inside, { x: inside.x - 700, y: inside.y + 50 }, 15);
  await expect(node(page, "rope")).not.toHaveAttribute("data-parent", /./);
});

test("a deleted frame takes what is in it, and comes back with it", async ({ page }) => {
  await openCanvas(page, "/board");
  await node(page, "signage").locator("[data-hakushi-drag]").click();
  await page.keyboard.press("Delete");
  await expect(node(page, "signage")).toHaveCount(0);
  await expect(node(page, "wayfinding")).toHaveCount(0);
  await page.keyboard.press(`${await mod(page)}+z`);
  await expect(node(page, "wayfinding")).toHaveAttribute("data-parent", "signage");
});

test("a double click inside a frame makes a note in it, and a drag inside selects its notes", async ({ page }) => {
  await openCanvas(page, "/board");
  const frame = (await node(page, "signage").boundingBox())!;
  const count = await page.locator("#board .hakushi-node").count();
  await page.mouse.dblclick(frame.x + frame.width / 2, frame.y + frame.height - 12);
  await expect(page.locator("#board .hakushi-node")).toHaveCount(count + 1);
  await expect(page.locator('#board .hakushi-node[data-ui-selected]')).toHaveAttribute("data-parent", "signage");

  await page.keyboard.press("Escape");
  await drag(page, { x: frame.x + 8, y: frame.y + 8 }, { x: frame.x + frame.width - 8, y: frame.y + frame.height / 2 });
  await expect(node(page, "wayfinding")).toHaveAttribute("data-ui-selected", "");
  await expect(node(page, "signage")).not.toHaveAttribute("data-ui-selected", "");
});
