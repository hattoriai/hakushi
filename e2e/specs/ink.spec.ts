// Ink (Hakushi.Kits.Ink) on the moodboard of the development app (/board):
// a pen, a highlighter, an eraser and a lasso; the others' lines as they
// draw them; and an agent that circles a node.

import { expect, test, type Page } from "@playwright/test";
import { mod, node, openCanvas } from "./support";

// The strokes drawn here: not the line the board has under its title.
const strokes = (page: Page) => page.locator('#board .hakushi-node[data-type="ink-stroke"]:not([data-id="underline"])');
const tool = (page: Page, name: string) => page.locator(`#board .hakushi-tool[data-tool="${name}"]`);

// A line drawn with the mouse, as a hand does: from a point, by others.
async function line(page: Page, points: [number, number][]): Promise<void> {
  const box = (await page.locator("#board").boundingBox())!;
  await page.mouse.move(box.x + points[0][0], box.y + points[0][1]);
  await page.mouse.down();
  for (const [x, y] of points.slice(1)) await page.mouse.move(box.x + x, box.y + y, { steps: 4 });
  await page.mouse.up();
}

const wave = (x: number, y: number, n = 16): [number, number][] => Array.from({ length: n }, (_, i) => [x + i * 12, y + Math.sin(i / 2) * 14]);

async function agent(page: Page, tool: string, args: Record<string, unknown>): Promise<unknown> {
  const response = await page.request.post("/dev/agent", { data: { tool, arguments: args } });
  const reply = (await response.json()) as { result?: unknown; error?: string };
  if (reply.error) throw new Error(`${tool}: ${reply.error}`);
  return reply.result;
}

test("a pen draws a stroke, which is a node that moves, erases and comes back", async ({ page }) => {
  await openCanvas(page, "/board");
  await expect(strokes(page)).toHaveCount(0);

  await tool(page, "ink:pen").click();
  await expect(tool(page, "ink:pen")).toHaveAttribute("aria-pressed", "true");
  await page.locator('#board .hakushi-swatch[data-color="red"]').click();
  await line(page, wave(420, 560));
  await expect(strokes(page)).toHaveCount(1);
  const stroke = strokes(page).first();
  await expect(stroke.locator(".hakushi-ink")).toHaveAttribute("data-color", "red");
  await expect(stroke).toHaveAttribute("aria-label", "Drawing");
  // Simplified when the pen lifts: a stroke is not every point the mouse gave.
  await expect(page.locator("#board .hakushi-ink-live path")).toHaveCount(0);

  // With the pointer, a stroke is selected and dragged by its line.
  await tool(page, "pointer").click();
  const id = (await stroke.getAttribute("data-id"))!;
  const x = Number(await stroke.getAttribute("data-x"));
  const start = await page.evaluate(([id]) => {
    const el = document.querySelector<SVGGeometryElement>(`#board .hakushi-node[data-id="${id}"] .hakushi-ink-aim`)!;
    const p = el.getPointAtLength(0);
    const r = el.ownerSVGElement!.getBoundingClientRect();
    const zoom = r.width / Number(el.ownerSVGElement!.getAttribute("width"));
    return { x: r.left + p.x * zoom, y: r.top + p.y * zoom };
  }, [id]);
  await page.mouse.move(start.x, start.y);
  await page.mouse.down();
  await page.mouse.move(start.x + 40, start.y + 30, { steps: 5 });
  await page.mouse.up();
  await expect.poll(async () => Number(await node(page, id).getAttribute("data-x"))).toBeGreaterThan(x + 20);

  // The eraser takes a stroke it passes over; ⌘Z brings it back.
  await tool(page, "ink:eraser").click();
  const over = (await stroke.locator(".hakushi-ink-aim").boundingBox())!;
  await page.mouse.move(over.x + over.width / 2, over.y - 30);
  await page.mouse.down();
  await page.mouse.move(over.x + over.width / 2, over.y + over.height + 30, { steps: 12 });
  await page.mouse.up();
  await expect(strokes(page)).toHaveCount(0);
  await page.keyboard.press(`${await mod(page)}+z`);
  await expect(strokes(page)).toHaveCount(1);
});

test("a stylus's pressure makes the line thicker; then a finger pans and does not draw", async ({ page }) => {
  await openCanvas(page, "/board");
  await tool(page, "ink:pen").click();
  const box = (await page.locator("#board").boundingBox())!;
  const view = () => page.evaluate(() => (window as any).canvasOf("board").getView());

  await page.evaluate(({ x, y }) => {
    const root = document.getElementById("board")!;
    const fire = (type: string, px: number, py: number, pressure: number, pointerType = "pen") =>
      root.dispatchEvent(new PointerEvent(type, { bubbles: true, cancelable: true, pointerId: 7, pointerType, clientX: px, clientY: py, pressure, button: type === "pointermove" ? -1 : 0, buttons: type === "pointerup" ? 0 : 1, isPrimary: true }));
    fire("pointerdown", x, y, 0.05);
    for (let i = 1; i <= 40; i++) fire("pointermove", x + i * 5, y, i / 40);
    fire("pointerup", x + 200, y, 0);
  }, { x: box.x + 300, y: box.y + 600 });
  await expect(strokes(page)).toHaveCount(1);
  // Thin where it began, thick where it ended.
  const widths = await strokes(page).first().evaluate((el) => {
    const path = el.querySelector<SVGPathElement>(".hakushi-ink-line")!;
    const h = (x: number) => {
      let top = Infinity, bottom = -Infinity;
      const length = path.getTotalLength();
      for (let i = 0; i <= 400; i++) {
        const p = path.getPointAtLength((length * i) / 400);
        if (Math.abs(p.x - x) < 3) {
          top = Math.min(top, p.y);
          bottom = Math.max(bottom, p.y);
        }
      }
      return bottom - top;
    };
    const w = Number(el.getAttribute("data-width"));
    return [h(w * 0.15), h(w * 0.85)];
  });
  expect(widths[1]).toBeGreaterThan(widths[0] * 1.6);

  // A pen was used: a finger pans.
  const before = await view();
  await page.evaluate(({ x, y }) => {
    const root = document.getElementById("board")!;
    const fire = (type: string, px: number, py: number) =>
      root.dispatchEvent(new PointerEvent(type, { bubbles: true, cancelable: true, pointerId: 9, pointerType: "touch", clientX: px, clientY: py, pressure: 0.5, button: type === "pointermove" ? -1 : 0, buttons: type === "pointerup" ? 0 : 1, isPrimary: true }));
    fire("pointerdown", x, y);
    for (let i = 1; i <= 10; i++) fire("pointermove", x + i * 6, y + i * 4);
    fire("pointerup", x + 60, y + 40);
  }, { x: box.x + 500, y: box.y + 300 });
  await expect.poll(async () => (await view()).x).toBeCloseTo(before.x + 60, 0);
  await expect(strokes(page)).toHaveCount(1);
});

test("the others see a line as it is drawn, and the stroke it becomes", async ({ browser }) => {
  const ada = await (await browser.newContext()).newPage();
  const kenji = await (await browser.newContext()).newPage();
  const room = await openCanvas(ada, "/board", undefined, "&as=ada");
  await openCanvas(kenji, "/board", room, "&as=kenji");
  await expect(ada.locator('#board [data-person="kenji"]')).toBeVisible();

  await tool(kenji, "ink:highlighter").click();
  const box = (await kenji.locator("#board").boundingBox())!;
  await kenji.mouse.move(box.x + 300, box.y + 140);
  await kenji.mouse.down();
  for (let i = 1; i <= 12; i++) await kenji.mouse.move(box.x + 300 + i * 15, box.y + 140, { steps: 2 });
  // The pen is down: Ada sees the line, in the highlighter's colour.
  await expect(ada.locator('#board .hakushi-ink-live path[data-tool="highlighter"][data-color="yellow"]')).toHaveCount(1);
  await kenji.mouse.up();
  await expect(strokes(ada)).toHaveCount(1);
  await expect(ada.locator("#board .hakushi-ink-live path")).toHaveCount(0);

  // Both draw at once.
  await tool(ada, "ink:pen").click();
  await tool(kenji, "ink:pen").click();
  await Promise.all([line(ada, wave(380, 520)), line(kenji, wave(380, 620))]);
  await expect(strokes(ada)).toHaveCount(3);
  await expect(strokes(kenji)).toHaveCount(3);
});

test("a lasso selects strokes and nodes alike, to delete them", async ({ page }) => {
  await openCanvas(page, "/board");
  await tool(page, "ink:pen").click();
  const note = (await node(page, "voice").boundingBox())!;
  const box = (await page.locator("#board").boundingBox())!;
  const left = note.x - box.x;
  const top = note.y - box.y;
  // A line under the note.
  await line(page, [[left, top + note.height + 12], [left + note.width / 2, top + note.height + 16], [left + note.width, top + note.height + 12]]);
  await expect(strokes(page)).toHaveCount(1);

  await page.keyboard.press("l");
  await expect(tool(page, "ink:lasso")).toHaveAttribute("aria-pressed", "true");
  await line(page, [
    [left - 20, top - 20],
    [left + note.width + 20, top - 20],
    [left + note.width + 20, top + note.height + 40],
    [left - 20, top + note.height + 40],
    [left - 20, top - 15],
  ]);
  const selected = await page.evaluate(() => (window as any).canvasOf("board").getSelection());
  expect(selected).toContain("voice");
  expect(selected).toHaveLength(2);

  await page.keyboard.press("Delete");
  await expect(strokes(page)).toHaveCount(0);
  await expect(node(page, "voice")).toHaveCount(0);
  // Escape gives the pointer back.
  await page.keyboard.press("Escape");
  await expect(tool(page, "pointer")).toHaveAttribute("aria-pressed", "true");
});

test("an agent circles a node, and the person sees its pen draw the ring", async ({ page }) => {
  const room = await openCanvas(page, "/board", undefined, "&as=ada");
  const canvas = `atelier:board:${room}`;
  // What the person sees reaches the room (the size of the node, for the ring).
  await page.waitForTimeout(1_200);

  const drawn = agent(page, "draw_on_canvas", { canvas, around: "palette" });
  // The line grows under the agent's pointer, before it is a node.
  await expect(page.locator("#board .hakushi-ink-live path[data-color='red']")).toHaveCount(1);
  await expect(page.locator("#board .hakushi-cursor")).toContainText("Claude Code");
  expect(await strokes(page).count()).toBe(0);
  const { strokes: ids } = (await drawn) as { strokes: string[] };
  await expect(strokes(page)).toHaveCount(1);
  await expect(page.locator("#board .hakushi-ink-live path")).toHaveCount(0);

  // The ring is around the palette.
  const ring = (await node(page, ids[0]).boundingBox())!;
  const palette = (await node(page, "palette").boundingBox())!;
  expect(ring.x).toBeLessThan(palette.x);
  expect(ring.y).toBeLessThan(palette.y);
  expect(ring.x + ring.width).toBeGreaterThan(palette.x + palette.width);
  expect(ring.y + ring.height).toBeGreaterThan(palette.y + palette.height);

  // Told not to, it lands at once.
  await agent(page, "draw_on_canvas", { canvas, live: false, strokes: [{ points: [[0, 700], [200, 720]], color: "blue" }] });
  await expect(strokes(page)).toHaveCount(2);
});
