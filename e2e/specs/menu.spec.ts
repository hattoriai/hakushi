import { expect, test } from "@playwright/test";
import { alongEdge, edgeCount, node, openCanvas } from "./support";

// The canvas's menu (Hakushi.Menu): the schema's own item for a table, and
// the canvas's own actions.

const menu = (page: import("@playwright/test").Page) => page.locator("#schema .hakushi-context-menu");

test("a right click on a table: the app's item, and the canvas's", async ({ page }) => {
  await openCanvas(page, "/");
  const columns = await node(page, "people").locator(".column").count();
  await node(page, "people").locator("header").click({ button: "right" });
  await expect(menu(page)).toBeVisible();
  await expect(node(page, "people")).toHaveAttribute("data-ui-selected", "");
  await expect(menu(page).getByRole("menuitem")).toHaveText([/Add a column/, /Copy/, /Duplicate/, /Delete/]);
  // The first item has the focus, for the keyboard.
  await expect(menu(page).getByRole("menuitem").first()).toBeFocused();

  await menu(page).getByRole("menuitem", { name: /Add a column/ }).click();
  await expect(menu(page)).toHaveCount(0);
  await expect(node(page, "people").locator(".column")).toHaveCount(columns + 1);
});

test("the menu of an edge deletes it, and the paper's selects all", async ({ page }) => {
  await openCanvas(page, "/");
  const before = await edgeCount(page, "schema");
  const edge = page.locator("#schema .hakushi-edge").first();
  const id = await edge.getAttribute("data-edge");
  // The middle of its line, where a click is the edge's.
  const [point] = await alongEdge(page, "schema", id!);
  await page.mouse.click(point.x, point.y, { button: "right" });
  await expect(menu(page).getByRole("menuitem")).toHaveText([/Edit label/, /Delete/]);
  await menu(page).getByRole("menuitem", { name: /Delete/ }).click();
  await expect.poll(() => edgeCount(page, "schema")).toBe(before - 1);

  const box = (await page.locator("#schema").boundingBox())!;
  await page.mouse.click(box.x + 30, box.y + 30, { button: "right" });
  await menu(page).getByRole("menuitem", { name: /Select all/ }).click();
  await expect(page.locator("#schema .hakushi-node[data-ui-selected]")).toHaveCount(await page.locator("#schema .hakushi-node").count());
});

test("Shift+F10 opens the menu of the focused node, and Escape closes it", async ({ page }) => {
  await openCanvas(page, "/");
  await page.locator("#schema").focus();
  await page.keyboard.press("Tab");
  await page.keyboard.press("Shift+F10");
  await expect(menu(page)).toBeVisible();
  await page.keyboard.press("ArrowDown");
  await expect(menu(page).getByRole("menuitem").nth(1)).toBeFocused();
  await page.keyboard.press("Escape");
  await expect(menu(page)).toHaveCount(0);
  await expect(page.locator("#schema")).toBeFocused();
});

test("a click away closes it", async ({ page }) => {
  await openCanvas(page, "/");
  await node(page, "people").locator("header").click({ button: "right" });
  await expect(menu(page)).toBeVisible();
  const box = (await page.locator("#schema").boundingBox())!;
  await page.mouse.click(box.x + 20, box.y + box.height - 20);
  await expect(menu(page)).toHaveCount(0);
});
