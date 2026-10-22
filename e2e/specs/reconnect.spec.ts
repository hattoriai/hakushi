import { expect, test } from "@playwright/test";
import { center, mod, node, openCanvas } from "./support";

test("the end of a selected edge goes to another handle", async ({ page }) => {
  await openCanvas(page, "/");
  const edge = page.locator('#schema-edge-data > i[data-source="tasks"][data-source-handle="assignee_id"]');
  await expect(edge).toHaveAttribute("data-target", "people");

  // Select the edge by its line, then drag its target end.
  const id = await edge.getAttribute("data-id");
  await page.locator(`#schema .hakushi-edge[data-edge="${id}"] .hakushi-edge-hit`).click({ force: true });
  const knob = page.locator(`#schema .hakushi-knob[data-end="target"]`);
  await expect(knob).toHaveCount(1);
  const from = await center(knob);
  const to = await center(page.locator('[data-id="clients"] [data-column="id"] .hakushi-handle[data-side="right"]'));
  await page.mouse.move(from.x, from.y);
  await page.mouse.down();
  await page.mouse.move(from.x - 40, from.y, { steps: 3 });
  // While dragging, the uuid columns may be ends, the text ones not.
  await expect(page.locator('[data-id="clients"] [data-column="id"] .hakushi-handle').first()).toHaveAttribute("data-ui-valid", "");
  await expect(page.locator('[data-id="clients"] [data-column="name"] .hakushi-handle').first()).not.toHaveAttribute("data-ui-valid", "");
  await page.mouse.move(to.x, to.y, { steps: 12 });
  await page.mouse.up();

  await expect(page.locator(`#schema-edge-data > i[data-id="${id}"]`)).toHaveAttribute("data-target", "clients");
  await page.keyboard.press(`${await mod(page)}+z`);
  await expect(page.locator(`#schema-edge-data > i[data-id="${id}"]`)).toHaveAttribute("data-target", "people");
});

// A selected node's edges are drawn above the nodes, in the colour of a
// selection, so that an edge that passes under another node is seen going
// to its own end, not to that node. Others stay under the nodes.
test("a selected node's edges are drawn above the nodes, to their own ends", async ({ page }) => {
  await openCanvas(page, "/");
  const mine = await page.locator('#schema-edge-data > i[data-source="tasks"]').first().getAttribute("data-id");
  const other = await page.locator('#schema-edge-data > i:not([data-source="tasks"]):not([data-target="tasks"])').first().getAttribute("data-id");
  const raised = (id: string | null) => page.locator(`#schema .hakushi-edges-raised .hakushi-edge[data-edge="${id}"]`);
  await expect(raised(mine)).toHaveCount(0);

  await node(page, "tasks").locator("strong").first().click();
  await expect(raised(mine)).toHaveAttribute("data-ui-connected", "");
  await expect(raised(other)).toHaveCount(0);
  // Above every node, not only after them.
  const top = await page.locator("#schema .hakushi-node").evaluateAll((els) => Math.max(...els.map((e) => Number(getComputedStyle(e).zIndex) || 0)));
  expect(await page.locator("#schema .hakushi-edges-raised").evaluate((e) => Number(getComputedStyle(e).zIndex))).toBeGreaterThan(top);

  await page.keyboard.press("Escape");
  await expect(raised(mine)).toHaveCount(0);
  await expect(page.locator(`#schema .hakushi-edges:not(.hakushi-edges-raised) .hakushi-edge[data-edge="${mine}"]`)).toHaveCount(1);
});
