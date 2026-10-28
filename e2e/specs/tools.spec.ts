import { expect, test } from "@playwright/test";
import { openCanvas } from "./support";

// Tools of the app's own (registerTool): the moodboard's ruler and stamp,
// a button each in the bar of tools, and what the canvas tells the page's
// script (canvasOf(element).on).

test("a ruler of the app's own measures, drawing on its layer", async ({ page }) => {
  await openCanvas(page, "/board");
  const ruler = page.locator('#board .hakushi-tool[data-tool="app:ruler"]');
  await expect(ruler).toHaveAttribute("aria-label", "Ruler");
  await ruler.click();
  await expect(ruler).toHaveAttribute("aria-pressed", "true");

  const box = (await page.locator("#board").boundingBox())!;
  await page.mouse.move(box.x + 100, box.y + 300);
  await page.mouse.down();
  await page.mouse.move(box.x + 400, box.y + 300, { steps: 5 });
  await page.mouse.up();
  const layer = page.locator("#board .hakushi-tool-layer");
  await expect(layer.locator("line")).toHaveCount(1);
  const zoom = Number((await page.locator(".hakushi-zoom").textContent())!.replace("%", "")) / 100;
  const measured = Number((await layer.getAttribute("data-measured"))!.replace(" px", ""));
  expect(Math.abs(measured - 300 / zoom)).toBeLessThan(2);

  // The pointer again: what it drew goes.
  await page.keyboard.press("v");
  await expect(layer.locator("line")).toHaveCount(0);
});

test("a stamp of the app's own drops a note, a change as a person's", async ({ page }) => {
  await openCanvas(page, "/board");
  const count = await page.locator("#board .hakushi-node").count();
  await page.locator("#board").focus();
  await page.keyboard.press("s");
  await expect(page.locator('#board .hakushi-tool[data-tool="app:stamp"]')).toHaveAttribute("aria-pressed", "true");
  const box = (await page.locator("#board").boundingBox())!;
  await page.mouse.click(box.x + 200, box.y + box.height - 120);
  await expect(page.locator("#board .hakushi-node")).toHaveCount(count + 1);
});

test("the page's script hears the selection, the view, the tool and the changes", async ({ page }) => {
  await openCanvas(page, "/board");
  await page.evaluate(() => {
    const canvas = (window as unknown as { canvasOf(id: string): { on(e: string, f: (p: unknown) => void): () => void } }).canvasOf("board");
    const heard: Record<string, unknown[]> = { select: [], view: [], tool: [], change: [] };
    for (const event of Object.keys(heard)) canvas.on(event, (p) => heard[event].push(p));
    (window as unknown as { heard: typeof heard }).heard = heard;
  });
  const heard = () => page.evaluate(() => (window as unknown as { heard: Record<string, unknown[]> }).heard);

  await page.locator('#board .hakushi-node[data-id="tide"]').click();
  await expect.poll(async () => (await heard()).select.at(-1)).toEqual({ nodes: ["tide"], edges: [] });
  await page.locator('[data-action="zoom-in"]').click();
  await expect.poll(async () => (await heard()).view.length).toBeGreaterThan(0);
  await page.locator("#board").focus();
  await page.keyboard.press("m");
  await expect.poll(async () => (await heard()).tool.at(-1)).toBe("app:ruler");
  await page.keyboard.press("v");
  await page.keyboard.press("ArrowRight");
  await expect.poll(async () => (await heard()).change.at(-1)).toMatchObject({ ok: true, change: { op: "move" } });

  const nodes = await page.evaluate(() => (window as unknown as { canvasOf(id: string): { getNodes(): { id: string }[] } }).canvasOf("board").getNodes().map((n) => n.id));
  expect(nodes).toContain("tide");
});

test("a viewer has the ruler, which changes nothing, and not the stamp", async ({ page }) => {
  await openCanvas(page, "/board", undefined, "&as=viewer");
  await expect(page.locator('#board .hakushi-tool[data-tool="app:ruler"]')).toBeVisible();
  await expect(page.locator('#board .hakushi-tool[data-tool="app:stamp"]')).toHaveCount(0);
});
