// Helpers for the browser tests.

import { expect, type Locator, type Page } from "@playwright/test";

let rooms = 0;

/**
 * Opens a page of the development app in a room of its own (`?room=`), so
 * that the tests that run at once do not change each other's canvases.
 * Gives the room, to open the same canvas again (as another person).
 */
export async function openCanvas(page: Page, path: string, room = `t${process.pid}-${Date.now()}-${rooms++}`, extra = ""): Promise<string> {
  const sep = path.includes("?") ? "&" : "?";
  await page.goto(`${path}${sep}room=${room}${extra}`);
  await expect(page.locator("[data-phx-main].phx-connected")).toBeVisible();
  await expect(page.locator(".hakushi-controls")).toBeVisible();
  // The first frame: the view is fitted and the edges are drawn.
  await page.waitForFunction(() => document.querySelectorAll(".hakushi-edge-line[d]").length > 0 || !document.querySelector("[id$='-edge-data'] > i"));
  return room;
}

/** The modifier of the canvas's shortcuts in this browser. */
export async function mod(page: Page): Promise<string> {
  const apple = await page.evaluate(() => {
    const platform = (navigator as Navigator & { userAgentData?: { platform?: string } }).userAgentData?.platform || navigator.platform || "";
    return /mac|iphone|ipad|ipod/i.test(platform);
  });
  return apple ? "Meta" : "Control";
}

export const node = (page: Page, id: string): Locator => page.locator(`.hakushi-node[data-id="${id}"]`);

/** The place of a node, as the server last rendered it. */
export async function place(page: Page, id: string): Promise<{ x: number; y: number }> {
  const el = node(page, id);
  return { x: Number(await el.getAttribute("data-x")), y: Number(await el.getAttribute("data-y")) };
}

export async function center(locator: Locator): Promise<{ x: number; y: number }> {
  // An element of the canvas's overlay (a knob, a waypoint) is drawn again
  // on each frame: the one found may be gone when it is measured. Again,
  // then, until one is measured.
  let box = await locator.boundingBox();
  for (let tries = 0; !box && tries < 20; tries++) {
    await locator.page().waitForTimeout(50);
    box = await locator.boundingBox();
  }
  if (!box) throw new Error(`no box for ${locator}`);
  return { x: box.x + box.width / 2, y: box.y + box.height / 2 };
}

/** Drags from one point to another in steps, as a hand does. */
export async function drag(page: Page, from: { x: number; y: number }, to: { x: number; y: number }, steps = 10): Promise<void> {
  await page.mouse.move(from.x, from.y);
  await page.mouse.down();
  await page.mouse.move(from.x + (to.x - from.x) / 4, from.y + (to.y - from.y) / 4, { steps: 3 });
  await page.mouse.move(to.x, to.y, { steps });
  await page.mouse.up();
}

/**
 * Points along an edge's line, on the screen: at `fractions` of its length.
 * The line's points are the canvas's; they are put on the screen by a node's
 * box (its place and its zoom), not by the SVG's getScreenCTM, which WebKit
 * gets wrong under the canvas's CSS transform.
 */
export async function alongEdge(page: Page, canvas: string, id: string, fractions: number[] = [0.5]): Promise<{ x: number; y: number }[]> {
  return page.evaluate(
    ({ canvas, id, fractions }) => {
      const root = document.getElementById(canvas)!;
      const line = root.querySelector<SVGPathElement>(`.hakushi-edge[data-edge="${CSS.escape(id)}"] .hakushi-edge-line`)!;
      const node = root.querySelector<HTMLElement>(".hakushi-node:not([data-parent])")!;
      const box = node.getBoundingClientRect();
      const zoom = box.width / node.offsetWidth;
      const left = box.left - Number(node.dataset.x) * zoom;
      const top = box.top - Number(node.dataset.y) * zoom;
      const total = line.getTotalLength();
      return fractions.map((f) => {
        const p = line.getPointAtLength(total * f);
        return { x: left + p.x * zoom, y: top + p.y * zoom };
      });
    },
    { canvas, id, fractions },
  );
}

/** The ids of the edges the server rendered. */
export async function edgeCount(page: Page, canvas: string): Promise<number> {
  return page.locator(`#${canvas}-edge-data > i`).count();
}

/** The zoom, as the controls say it. */
export async function zoom(page: Page): Promise<number> {
  return Number((await page.locator(".hakushi-zoom").textContent())!.replace("%", ""));
}
