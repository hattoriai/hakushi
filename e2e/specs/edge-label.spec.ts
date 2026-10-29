import { expect, test } from "@playwright/test";
import { center, edgeCount, openCanvas } from "./support";

// A label of the app's own (an :edge_label slot): the workflow's ways out
// of its condition, drawn by the server on their edges, with a button.

test("the server's labels sit on their edges, and their buttons are theirs", async ({ page }) => {
  await openCanvas(page, "/workflow");
  const yes = page.locator('#workflow .way-label[data-way="yes"]');
  await expect(yes).toBeVisible();
  await expect(yes).toContainText("Yes");

  // On the middle of its edge.
  const label = page.locator('#workflow .hakushi-edge-label-own:has(.way-label[data-way="yes"])');
  const id = (await label.getAttribute("data-edge"))!;
  const middle = await page.locator(`#workflow .hakushi-edge[data-edge="${id}"] .hakushi-edge-line`).evaluate((path) => {
    const line = path as SVGPathElement;
    const m = line.getScreenCTM()!;
    // Where the canvas puts a label: the middle of the line, along its length.
    const p = line.getPointAtLength(line.getTotalLength() / 2);
    return { x: p.x * m.a + m.e, y: p.y * m.d + m.f };
  });
  const at = await center(label);
  expect(Math.hypot(at.x - middle.x, at.y - middle.y)).toBeLessThan(20);

  // A click on it selects its edge; its button removes it.
  await label.click({ position: { x: 4, y: 4 } });
  await expect(page.locator(`#workflow .hakushi-edge[data-edge="${id}"]`)).toHaveAttribute("data-ui-selected", "");
  const before = await edgeCount(page, "workflow");
  await yes.getByRole("button", { name: "Remove the way Yes" }).click();
  await expect.poll(() => edgeCount(page, "workflow")).toBe(before - 1);
  await expect(yes).toHaveCount(0);
});
