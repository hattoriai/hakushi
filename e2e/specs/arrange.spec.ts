import { expect, test } from "@playwright/test";
import { mod, node, openCanvas, place } from "./support";

// Lining nodes up and spacing them out: Alt and a letter, the menu, and
// undo, on the schema's tables.

test("Alt+W lines up the tops of the selection, and undo takes it back", async ({ page }) => {
  await openCanvas(page, "/");
  const before = { people: await place(page, "people"), tasks: await place(page, "tasks") };
  expect(before.people.y).not.toBe(before.tasks.y);

  await node(page, "people").locator("header").click();
  await node(page, "tasks").locator("header").click({ modifiers: ["Shift"] });
  await page.keyboard.press("Alt+KeyW");
  const top = Math.min(before.people.y, before.tasks.y);
  await expect.poll(async () => [(await place(page, "people")).y, (await place(page, "tasks")).y]).toEqual([top, top]);
  // Only the tops: their sides stay.
  expect((await place(page, "people")).x).toBe(before.people.x);

  await page.keyboard.press(`${await mod(page)}+z`);
  await expect.poll(() => place(page, "people")).toEqual(before.people);
  await expect.poll(() => place(page, "tasks")).toEqual(before.tasks);
});

test("the menu of three tables lines up their left sides and spaces them out", async ({ page }) => {
  await openCanvas(page, "/");
  for (const [i, id] of ["clients", "projects", "tasks"].entries()) {
    await node(page, id).locator("header").click({ modifiers: i ? ["Shift"] : [] });
  }
  await node(page, "projects").locator("header").click({ button: "right" });
  const menu = page.locator("#schema .hakushi-context-menu");
  await menu.getByRole("menuitem", { name: /Align left/ }).click();
  const left = Math.min(...(await Promise.all(["clients", "projects", "tasks"].map(async (id) => (await place(page, id)).x))));
  await expect.poll(async () => Promise.all(["clients", "projects", "tasks"].map(async (id) => (await place(page, id)).x))).toEqual([left, left, left]);

  await node(page, "projects").locator("header").click({ button: "right" });
  await expect(menu.getByRole("menuitem", { name: /Space out down/ })).toBeVisible();
  await menu.getByRole("menuitem", { name: /Space out down/ }).click();
  // Equal gaps between them, top to bottom.
  await expect
    .poll(async () => {
      const boxes = await Promise.all(
        ["clients", "projects", "tasks"].map(async (id) => ({ y: (await place(page, id)).y, h: (await node(page, id).boundingBox())!.height })),
      );
      boxes.sort((a, b) => a.y - b.y);
      const zoom = Number((await page.locator(".hakushi-zoom").textContent())!.replace("%", "")) / 100;
      const gaps = [boxes[1].y - (boxes[0].y + boxes[0].h / zoom), boxes[2].y - (boxes[1].y + boxes[1].h / zoom)];
      return Math.abs(gaps[0] - gaps[1]) < 2;
    })
    .toBe(true);
});
