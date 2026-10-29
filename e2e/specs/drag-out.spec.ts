import { expect, test } from "@playwright/test";
import { openCanvas } from "./support";

// Out of the canvas (`drag_out`): a table's or a column's name dragged
// onto the page (a table by its icon, a column by its name), into a field
// as text, or onto a drop target the LiveView hears (`data-hakushi-drop`).
// A click on what drags out still selects the table.

test("a table dragged into a field gives it the table's name as text, and moves nothing", async ({ page }) => {
  await openCanvas(page, "/database?n=6");
  const name = page.locator('#database .hakushi-kit-table-grip[draggable="true"]').first();
  const text = (await name.getAttribute("data-hakushi-out"))!;
  expect(text).not.toBe("");
  const before = await page.locator("#database .hakushi-node").evaluateAll((els) => els.map((el) => (el as HTMLElement).style.translate));
  // What the field is given: the browser puts it in (a headless one's
  // drag does not), as an editor does (CodeMirror reads the drop itself).
  await page.evaluate(() => {
    document.getElementById("query")!.addEventListener("drop", (e) => {
      const transfer = (e as DragEvent).dataTransfer!;
      (window as unknown as { dropped: unknown }).dropped = { text: transfer.getData("text/plain"), taken: !e.defaultPrevented, out: JSON.parse(transfer.getData("application/x-hakushi")) };
    });
  });

  await name.dragTo(page.locator("#query"));
  const dropped = await page.evaluate(() => (window as unknown as { dropped: { text: string; taken: boolean; out: { canvas: string; text: string } } }).dropped);
  expect(dropped).toMatchObject({ text, taken: true, out: { canvas: "database", text } });
  // A drag out moves nothing on the canvas.
  expect(await page.locator("#database .hakushi-node").evaluateAll((els) => els.map((el) => (el as HTMLElement).style.translate))).toEqual(before);
});

test("a column's name dropped on a drop target is an event of the LiveView", async ({ page }) => {
  await openCanvas(page, "/database?n=6");
  const column = page.locator('#database .hakushi-kit-column-name[draggable="true"]').first();
  const text = (await column.getAttribute("data-hakushi-out"))!;
  const node = (await column.evaluate((el) => (el.closest(".hakushi-node") as HTMLElement).dataset.id))!;

  await column.dragTo(page.locator("#describe"));
  await expect(page.locator("#described")).toHaveText(`${text} (${node})`);
});

test("a click on what drags out selects its table", async ({ page }) => {
  await openCanvas(page, "/database?n=6");
  const name = page.locator('#database .hakushi-kit-table-grip[draggable="true"]').first();
  const node = name.locator("xpath=ancestor::div[contains(concat(' ', @class, ' '), ' hakushi-node ')][1]");
  await name.click();
  await expect(node).toHaveAttribute("data-ui-selected", "");
});
