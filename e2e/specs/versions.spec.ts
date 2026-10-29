import { expect, test } from "@playwright/test";
import { center, drag, openCanvas } from "./support";

// The versions of a canvas (Hakushi.History), and a canvas that compares
// one to now (its compare): the workflow of the development app.

test("a version against now: what moved, and what was deleted", async ({ page }) => {
  await openCanvas(page, "/workflow");
  const steps = page.locator("#workflow .hakushi-node");
  const moved = (await steps.nth(0).getAttribute("data-id"))!;
  const deleted = (await steps.nth((await steps.count()) - 1).getAttribute("data-id"))!;

  const from = await center(steps.nth(0).locator(".kind"));
  await drag(page, from, { x: from.x + 60, y: from.y + 40 });

  await page.locator(`#workflow .hakushi-node[data-id="${deleted}"] .kind`).click();
  await page.keyboard.press("Delete");
  await expect(page.locator(`#workflow .hakushi-node[data-id="${deleted}"]`)).toHaveCount(0);

  await page.getByRole("button", { name: "History" }).click();
  const versions = page.locator(".versions .version");
  await expect(versions).toHaveCount(2);
  // The oldest: the workflow before the move, against now.
  await versions.last().click();

  const then = page.locator("#workflow-then");
  await expect(then).toHaveAttribute("data-compare", "true");
  await expect(then.locator(`.hakushi-node[data-id="${moved}"]`)).toHaveAttribute("data-diff", "moved");
  await expect(then.locator(`.hakushi-node[data-id="${deleted}"]`)).toHaveAttribute("data-diff", "removed");
  await expect(then.locator('.hakushi-edge[data-diff="removed"]').first()).toBeAttached();
  // It changes nothing.
  await expect(then).toHaveAttribute("data-ui-readonly", "");

  await page.getByRole("button", { name: "History" }).click();
  await expect(page.locator("#workflow")).toBeVisible();
});
