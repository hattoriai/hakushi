import { expect, test, type Page } from "@playwright/test";
import { alongEdge, center, drag, node, openCanvas } from "./support";

// A routed edge goes around the nodes in its way: a node dragged onto its
// line, and away again.

// Points along an edge's line, on the screen.
const along = (page: Page, canvas: string, id: string) => alongEdge(page, canvas, id, Array.from({ length: 201 }, (_, i) => i / 200));

const edgeOf = (page: Page, source: string, target: string) => page.locator(`#workflow-edge-data > i[data-source="${source}"][data-target="${target}"]`).getAttribute("data-id");

test("a node dragged onto a routed edge's line, the edge goes around it; dragged away, it goes straight again", async ({ page }) => {
  await openCanvas(page, "/workflow");
  const id = (await edgeOf(page, "receipt", "close"))!;
  const line = page.locator(`#workflow .hakushi-edge[data-edge="${id}"] .hakushi-edge-line`);
  const before = await line.getAttribute("d");

  const points = await along(page, "workflow", id);
  const middle = points[100];
  const moved = node(page, "thanks");
  const from = await center(moved);
  await drag(page, from, middle, 15);

  // The node is where the line was; the line is not in the node.
  const box = (await moved.boundingBox())!;
  expect(box.x < middle.x && middle.x < box.x + box.width && box.y < middle.y && middle.y < box.y + box.height).toBe(true);
  await expect
    .poll(async () => (await along(page, "workflow", id)).filter((p) => p.x > box.x + 2 && p.x < box.x + box.width - 2 && p.y > box.y + 2 && p.y < box.y + box.height - 2).length)
    .toBe(0);
  expect(await line.getAttribute("d")).not.toBe(before);

  // Away again, far below: the way it was.
  const now = await center(moved);
  await drag(page, now, { x: from.x, y: from.y }, 15);
  await expect(line).toHaveAttribute("d", before!);
});
