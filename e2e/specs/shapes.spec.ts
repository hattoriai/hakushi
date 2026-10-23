// Shapes (Hakushi.Kits.Shapes) on the whiteboard of the development app
// (/whiteboard): drawn with the tools, written in, styled from the panel,
// joined by a line, turned, and drawn by an agent.

import { expect, test, type Page } from "@playwright/test";
import { mod, node, openCanvas } from "./support";

const shapes = (page: Page) => page.locator('#whiteboard .hakushi-node[data-type="shape"]');
const tool = (page: Page, name: string) => page.locator(`#whiteboard .hakushi-tool[data-tool="${name}"]`);
const selection = (page: Page) => page.evaluate(() => (window as any).canvasOf("whiteboard").getSelection() as string[]);
const style = async (page: Page, id: string) => JSON.parse((await node(page, id).locator("[data-hakushi-style]").getAttribute("data-hakushi-style"))!);

async function dragOn(page: Page, from: [number, number], to: [number, number], shift = false): Promise<void> {
  const box = (await page.locator("#whiteboard").boundingBox())!;
  await page.mouse.move(box.x + from[0], box.y + from[1]);
  await page.mouse.down();
  if (shift) await page.keyboard.down("Shift");
  await page.mouse.move(box.x + to[0], box.y + to[1], { steps: 6 });
  await page.mouse.up();
  if (shift) await page.keyboard.up("Shift");
}

test("a rectangle drawn by dragging, written in, styled, and taken back", async ({ page }) => {
  await openCanvas(page, "/whiteboard");
  const count = await shapes(page).count();

  await tool(page, "shapes:rect").click();
  await dragOn(page, [200, 480], [380, 560]);
  await expect(shapes(page)).toHaveCount(count + 1);
  // The new shape is selected, and the pointer is back.
  await expect(tool(page, "pointer")).toHaveAttribute("aria-pressed", "true");
  await expect.poll(() => selection(page).then((s) => s.length)).toBe(1);
  const [id] = await selection(page);
  const box = (await node(page, id).boundingBox())!;
  const zoom = await page.evaluate(() => (window as any).canvasOf("whiteboard").getView().zoom as number);
  expect(box.width / zoom).toBeCloseTo(180, -1);

  // A double click writes in it.
  await node(page, id).dblclick();
  await expect(page.locator("#whiteboard .hakushi-text-editor")).toBeFocused();
  await page.keyboard.type("Review the copy");
  await page.keyboard.press(`${await mod(page)}+Enter`);
  await expect(node(page, id).locator("[data-hakushi-text]")).toHaveText("Review the copy");
  await expect(node(page, id)).toHaveAttribute("aria-label", "Rectangle: Review the copy");

  // The panel beside it: a fill, a dashed stroke.
  await node(page, id).click();
  const panel = page.locator("#whiteboard .hakushi-style-panel");
  await expect(panel).toBeVisible();
  await panel.locator('[data-key="fill"][data-value="\\"green\\""]').click();
  await expect.poll(() => style(page, id).then((s) => s.fill)).toBe("green");
  await expect(panel.locator('[data-key="fill"][data-value="\\"green\\""]')).toHaveAttribute("aria-pressed", "true");
  await panel.locator('[data-key="dash"][data-value="true"]').click();
  await expect.poll(() => style(page, id).then((s) => s.dash)).toBe(true);

  // ⌘Z takes them back, one by one.
  await page.locator("#whiteboard").focus();
  await page.keyboard.press(`${await mod(page)}+z`);
  await expect.poll(() => style(page, id).then((s) => s.dash)).toBe(false);
  await page.keyboard.press(`${await mod(page)}+z`);
  await expect.poll(() => style(page, id).then((s) => s.fill)).toBe("blue");
});

test("Shift draws a circle; a click with the text tool writes at once", async ({ page }) => {
  await openCanvas(page, "/whiteboard");
  await page.locator("#whiteboard").focus();
  await page.keyboard.press("o");
  await expect(tool(page, "shapes:ellipse")).toHaveAttribute("aria-pressed", "true");
  await dragOn(page, [200, 480], [320, 540], true);
  await expect.poll(() => selection(page).then((s) => s.length)).toBe(1);
  const [circle] = await selection(page);
  const b = (await node(page, circle).boundingBox())!;
  expect(Math.abs(b.width - b.height)).toBeLessThan(2);

  await page.keyboard.press("t");
  const box = (await page.locator("#whiteboard").boundingBox())!;
  await page.mouse.click(box.x + 600, box.y + 520);
  await expect(page.locator("#whiteboard .hakushi-text-editor")).toBeFocused();
  await page.keyboard.type("A note in the margin");
  await page.mouse.click(box.x + 900, box.y + 300);
  await expect(page.locator('#whiteboard [data-hakushi-text="A note in the margin"]')).toHaveCount(1);
});

test("a line from a shape to a shape is an edge; one elsewhere is a line of its own", async ({ page }) => {
  await openCanvas(page, "/whiteboard");
  const edges = await page.locator("#whiteboard-edge-data > i").count();
  const at = async (id: string): Promise<[number, number]> => {
    const box = (await page.locator("#whiteboard").boundingBox())!;
    const n = (await node(page, id).boundingBox())!;
    return [n.x - box.x + n.width / 2, n.y - box.y + n.height / 2];
  };

  await tool(page, "shapes:line").click();
  await dragOn(page, await at("idea"), await at("ship"));
  await expect(page.locator("#whiteboard-edge-data > i")).toHaveCount(edges + 1);
  await expect(page.locator('#whiteboard-edge-data > i[data-source="idea"][data-target="ship"]')).toHaveCount(1);

  const lines = await page.locator('#whiteboard .hakushi-node[data-type="shape-line"]').count();
  await page.keyboard.press("a");
  const canvas = (await page.locator("#whiteboard").boundingBox())!;
  await dragOn(page, [60, canvas.height - 90], [260, canvas.height - 40]);
  await expect(page.locator('#whiteboard .hakushi-node[data-type="shape-line"]')).toHaveCount(lines + 1);
});

test("the letters of the tools: A an arrow, L Ink's lasso; a letter two tools share takes them in turn", async ({ page }) => {
  await openCanvas(page, "/whiteboard");
  const current = () => page.evaluate(() => (window as any).canvasOf("whiteboard").getTool() as string | null);
  await page.locator("#whiteboard").focus();
  await page.keyboard.press("a");
  expect(await current()).toBe("shapes:line");
  await page.keyboard.press("l");
  expect(await current()).toBe("ink:lasso");
  await page.keyboard.press("v");
  expect(await current()).toBe(null);

  // Two kits' tools with one letter (an app's kits may): the letter again takes the next.
  await page.evaluate(() => {
    const canvas = (window as any).canvasOf("whiteboard");
    canvas.config.tools.find((t: { tool: string }) => t.tool === "lasso").key = "a";
  });
  await page.keyboard.press("a");
  expect(await current()).toBe("shapes:line");
  await page.keyboard.press("a");
  expect(await current()).toBe("ink:lasso");
  await page.keyboard.press("a");
  expect(await current()).toBe("shapes:line");
});

test("a shape turns by its knob, and resizes by its sides", async ({ page }) => {
  await openCanvas(page, "/whiteboard");
  await node(page, "sketch").click();
  const knob = node(page, "sketch").locator(".hakushi-rotator");
  await expect(knob).toBeVisible();
  const k = (await knob.boundingBox())!;
  const n = (await node(page, "sketch").boundingBox())!;
  await page.mouse.move(k.x + k.width / 2, k.y + k.height / 2);
  await page.mouse.down();
  await page.keyboard.down("Shift");
  await page.mouse.move(n.x + n.width + 80, n.y + n.height / 2, { steps: 8 });
  await page.mouse.up();
  await page.keyboard.up("Shift");
  await expect(node(page, "sketch").locator("[data-hakushi-rotate]")).toHaveAttribute("style", /--hakushi-rotation: 90deg/);

  // The east side: wider, as high.
  const height = Number(await node(page, "sketch").getAttribute("data-height"));
  const width = Number(await node(page, "sketch").getAttribute("data-width"));
  const east = (await node(page, "sketch").locator('.hakushi-resizer[data-corner="e"]').boundingBox())!;
  await page.mouse.move(east.x + 5, east.y + 5);
  await page.mouse.down();
  await page.mouse.move(east.x + 65, east.y + 5, { steps: 5 });
  await page.mouse.up();
  await expect.poll(async () => Number(await node(page, "sketch").getAttribute("data-width"))).toBeGreaterThan(width + 30);
  expect(Number(await node(page, "sketch").getAttribute("data-height"))).toBe(height);
});

test("an agent draws a shape, and the person sees it", async ({ page }) => {
  const room = await openCanvas(page, "/whiteboard");
  const response = await page.request.post("/dev/agent", {
    data: { tool: "draw_shape", arguments: { canvas: `atelier:whiteboard:${room}`, kind: "ellipse", x: 0, y: 220, text: "Launch", style: { fill: "red" } } },
  });
  const reply = (await response.json()) as { result: { id: string } };
  await expect(node(page, reply.result.id).locator("[data-hakushi-text]")).toHaveText("Launch");
  expect((await style(page, reply.result.id)).fill).toBe("red");
});
