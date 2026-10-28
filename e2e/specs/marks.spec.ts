import { expect, test } from "@playwright/test";
import { node, openCanvas } from "./support";

// The app's marks (Hakushi.Live.mark/3): the workflow's Run marks each step
// as it waits, runs and is done, and the edges it takes.

test("a run marks the steps and the edges as it goes", async ({ page }) => {
  await openCanvas(page, "/workflow");
  const steps = page.locator("#workflow .hakushi-node");
  const count = await steps.count();
  await page.getByRole("button", { name: "Run" }).click();

  // On its way: a step runs, with its progress, and its edges flow.
  await expect(page.locator('#workflow .hakushi-node[data-mark-status="running"]')).toHaveCount(1);
  await expect(page.locator("#workflow .hakushi-mark-progress")).toHaveCount(1);
  await expect(page.locator('#workflow .hakushi-edge[data-mark-status="running"]').first()).toBeAttached();

  // Done: every step it reached, each with its badge, and the ring of its colour.
  await expect(page.getByRole("button", { name: "Run" })).toBeEnabled({ timeout: 15_000 });
  const done = page.locator('#workflow .hakushi-node[data-mark-status="done"]');
  expect(await done.count()).toBeGreaterThan(1);
  expect(await done.count()).toBeLessThanOrEqual(count);
  await expect(done.first().locator(".hakushi-mark-badge")).toHaveText("✓");
  const trigger = page.locator('#workflow .hakushi-node[data-type="trigger"]').first();
  await expect(trigger).toHaveAttribute("data-mark-status", "done");
  // The ring is the mark's colour (the selection's ring wins over it).
  const shadow = await trigger.evaluate((el) => getComputedStyle(el).boxShadow);
  expect(shadow).not.toBe("none");
  await expect(page.locator("#workflow .hakushi-mark-progress")).toHaveCount(0);
  await expect(node(page, (await trigger.getAttribute("data-id"))!)).not.toHaveAttribute("data-mark-dim", "true");
});
