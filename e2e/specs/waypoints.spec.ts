import { expect, test, type Page } from "@playwright/test";
import { alongEdge, center, drag, mod, openCanvas } from "./support";

// The points an edge goes through: dragged out of the line of a selected
// edge, moved, and taken away with a double click.

async function selectEdge(page: Page, canvas: string): Promise<string> {
  const edge = page.locator(`#${canvas} .hakushi-edge`).first();
  const id = (await edge.getAttribute("data-edge"))!;
  const [point] = await alongEdge(page, canvas, id);
  await page.mouse.click(point.x, point.y);
  await expect(page.locator(`#${canvas} .hakushi-edge[data-edge="${id}"]`)).toHaveAttribute("data-ui-selected", "");
  return id;
}

const points = (page: Page, canvas: string, id: string) => page.locator(`#${canvas}-edge-data > i[data-id="${id}"]`).getAttribute("data-points");

test("a point dragged out of a selected edge's line bends it, and a double click takes it away", async ({ page }) => {
  await openCanvas(page, "/");
  const id = await selectEdge(page, "schema");
  const handle = page.locator(`#schema .hakushi-waypoint-new[data-edge="${id}"]`).first();
  await expect(handle).toBeAttached();
  const from = await center(handle);
  await drag(page, from, { x: from.x + 30, y: from.y + 90 });

  await expect.poll(() => points(page, "schema", id)).not.toBeNull();
  const waypoint = page.locator(`#schema .hakushi-waypoint[data-edge="${id}"]`);
  await expect(waypoint).toHaveCount(1);
  // The line goes through it.
  const at = await center(waypoint);
  const line = await alongEdge(page, "schema", id, Array.from({ length: 201 }, (_, i) => i / 200));
  const through = Math.min(...line.map((p) => Math.hypot(p.x - at.x, p.y - at.y)));
  expect(through).toBeLessThan(4);

  // Moved, it stays one point.
  await drag(page, at, { x: at.x - 40, y: at.y + 10 });
  await expect(waypoint).toHaveCount(1);
  const moved = await points(page, "schema", id);

  await page.mouse.dblclick((await center(waypoint)).x, (await center(waypoint)).y);
  await expect.poll(() => points(page, "schema", id)).toBeNull();
  await expect(waypoint).toHaveCount(0);

  // Undo brings the point back where it was moved to.
  await page.keyboard.press(`${await mod(page)}+z`);
  await expect.poll(() => points(page, "schema", id)).toBe(moved);
});
