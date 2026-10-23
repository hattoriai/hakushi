// Images (Hakushi.Kits.Images) on the moodboard of the development app
// (/board): picked, dropped and pasted, with a placeholder while they
// upload (the others' too); resized with their aspect ratio, cropped,
// captioned, described; drawn in an export; and added by an agent.

import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { expect, test, type Page } from "@playwright/test";
import { mod, node, openCanvas } from "./support";

const fixture = (name: string) => resolve(__dirname, "../../test/fixtures/images", name);
const images = (page: Page) => page.locator('#board .hakushi-node[data-type="image"]');
const selection = (page: Page) => page.evaluate(() => (window as any).canvasOf("board").getSelection() as string[]);

// A file dropped on the canvas, at a point of the screen, as a browser drops one.
async function dropFile(page: Page, name: string, type: string, x: number, y: number): Promise<void> {
  const data = readFileSync(fixture(name)).toString("base64");
  await page.evaluate(
    ({ data, name, type, x, y }) => {
      const bytes = Uint8Array.from(atob(data), (c) => c.charCodeAt(0));
      const transfer = new DataTransfer();
      transfer.items.add(new File([bytes], name, { type }));
      const root = document.getElementById("board")!;
      for (const kind of ["dragover", "drop"]) root.dispatchEvent(new DragEvent(kind, { dataTransfer: transfer, clientX: x, clientY: y, bubbles: true, cancelable: true }));
    },
    { data, name, type, x, y },
  );
}

const middle = (box: { x: number; y: number; width: number; height: number }) => ({ x: box.x + box.width / 2, y: box.y + box.height / 2 });

// A paste on the canvas, of a file or of text. A ClipboardEvent made by a
// script does not keep the `clipboardData` given to it in every browser,
// so the event carries it as a property of its own.
async function pasteOn(page: Page, what: { text?: string; file?: { name: string; type: string; text: string } }): Promise<void> {
  await page.locator("#board").focus();
  await page.evaluate((what) => {
    const transfer = new DataTransfer();
    if (what.text) transfer.setData("text/plain", what.text);
    if (what.file) transfer.items.add(new File([what.file.text], what.file.name, { type: what.file.type }));
    const event = new Event("paste", { bubbles: true, cancelable: true });
    Object.defineProperty(event, "clipboardData", { value: transfer });
    document.getElementById("board")!.dispatchEvent(event);
  }, what);
}

test("an image picked with the tool is a node in the view, selected, at its aspect ratio", async ({ page }) => {
  await openCanvas(page, "/board");
  const count = await images(page).count();
  const chooser = page.waitForEvent("filechooser");
  await page.locator('#board .hakushi-tool[data-tool="images:image"]').click();
  await (await chooser).setFiles(fixture("facade.jpg"));

  await expect(images(page)).toHaveCount(count + 1);
  await expect(page.locator("#board .hakushi-file")).toHaveCount(0);
  await expect.poll(() => selection(page).then((s) => s.length)).toBe(1);
  const [id] = await selection(page);
  const width = Number(await node(page, id).getAttribute("data-width"));
  const height = Number(await node(page, id).getAttribute("data-height"));
  expect(width / height).toBeCloseTo(0.8, 2);
  // The pointer is back: the tool picks, and is never the one chosen.
  await expect(page.locator('#board .hakushi-tool[data-tool="pointer"]')).toHaveAttribute("aria-pressed", "true");
});

test("an image dropped lands where it is dropped, and the other person sees its placeholder, then it", async ({ page, browser }) => {
  const room = await openCanvas(page, "/board");
  const other = await browser.newPage();
  await openCanvas(other, "/board", room, "&as=kenji");
  const count = await images(page).count();

  const box = (await page.locator("#board").boundingBox())!;
  const at = { x: box.x + 400, y: box.y + 500 };
  await dropFile(page, "harbour.jpg", "image/jpeg", at.x, at.y);
  await expect(images(page)).toHaveCount(count + 1);
  await expect(images(other)).toHaveCount(count + 1);
  const [id] = await selection(page);
  const placed = (await node(page, id).boundingBox())!;
  // Its middle is where it was dropped.
  expect(Math.abs(placed.x + placed.width / 2 - at.x)).toBeLessThan(4);
  expect(Math.abs(placed.y + placed.height / 2 - at.y)).toBeLessThan(4);

  // An agent's image: the other person sees its placeholder while it comes.
  const seen = other.waitForSelector("#board .hakushi-file[data-peer]");
  const reply = await page.request.post("/dev/agent", {
    data: { tool: "add_image", arguments: { canvas: `atelier:board:${room}`, file: "rope.png", x: -400, y: 0, width: 160, alt: "Rope" } },
  });
  expect(await reply.json()).toMatchObject({ result: { width: 160, height: 160 } });
  await seen;
  await expect(images(other)).toHaveCount(count + 2);
  await expect(other.locator("#board .hakushi-file")).toHaveCount(0);
  await other.close();
});

test("an image resizes with its aspect ratio, and Shift frees it", async ({ page }) => {
  await openCanvas(page, "/board");
  await node(page, "quay").click();
  const ratio = async () => Number(await node(page, "quay").getAttribute("data-width")) / Number(await node(page, "quay").getAttribute("data-height"));
  const before = await ratio();
  // The middle of a resizer: it is as small as the zoom makes it, which
  // depends on the fonts of the browser.
  const corner = middle((await node(page, "quay").locator('.hakushi-resizer[data-corner="se"]').boundingBox())!);
  await page.mouse.move(corner.x, corner.y);
  const probe = (label: string) =>
    page.evaluate(({ label, x, y }) => {
      const hit = document.elementFromPoint(x, y) as HTMLElement | null;
      const canvas = (window as any).canvasOf("board");
      const g = canvas?.gesture;
      const quay = document.querySelector('.hakushi-node[data-id="quay"]') as HTMLElement;
      console.log(`DEBUG ${label}: hit=${hit?.tagName}.${hit?.className} gesture=${g?.kind}/${g?.corner} aspect=${g?.aspect} width=${quay.dataset.width} style=${quay.style.width}`);
    }, { label, x: corner.x, y: corner.y });
  page.on("console", (m) => m.text().startsWith("DEBUG") && console.log(m.text()));
  page.on("pointercancel" as any, () => {});
  await page.evaluate(() => ["pointerdown", "pointermove", "pointerup", "pointercancel", "lostpointercapture", "dragstart", "mousedown", "mousemove", "mouseup", "dragend", "drop"].forEach((t) => window.addEventListener(t, (e: any) => console.log(`DEBUG event ${t} target=${e.target?.nodeName}.${e.target?.className ?? ""} xy=${e.clientX},${e.clientY} buttons=${e.buttons} prevented=${e.defaultPrevented}`), true)));
  await probe("before down");
  await page.mouse.down();
  await probe("after down");
  await page.mouse.move(corner.x + 80, corner.y + 10, { steps: 5 });
  await probe("after move");
  await page.mouse.up();
  await probe("after up");
  await expect.poll(() => node(page, "quay").getAttribute("data-width").then(Number)).toBeGreaterThan(400);
  expect(await ratio()).toBeCloseTo(before, 1);

  const side = middle((await node(page, "quay").locator('.hakushi-resizer[data-corner="w"]').boundingBox())!);
  await page.mouse.move(side.x, side.y);
  await page.mouse.down();
  await page.keyboard.down("Shift");
  await page.mouse.move(side.x - 100, side.y, { steps: 5 });
  await page.mouse.up();
  await page.keyboard.up("Shift");
  await expect.poll(ratio).toBeGreaterThan(before + 0.2);
});

test("an image is captioned, described, and cropped in place; ⌘Z takes the crop back", async ({ page }) => {
  await openCanvas(page, "/board");
  const quay = node(page, "quay");

  await quay.dblclick();
  await expect(page.locator("#board .hakushi-text-editor")).toBeFocused();
  await page.keyboard.press(`${await mod(page)}+a`);
  await page.keyboard.type("From the north pier");
  await page.keyboard.press(`${await mod(page)}+Enter`);
  await expect(quay.locator("figcaption")).toHaveText("From the north pier");

  await quay.click();
  const alt = page.locator("#board .hakushi-style-panel .hakushi-style-text");
  await alt.fill("Three piers at dusk");
  await alt.press("Enter");
  await expect(quay.locator("img")).toHaveAttribute("alt", "Three piers at dusk");
  await expect(quay).toHaveAttribute("aria-label", "Image: Three piers at dusk");

  const width = Number(await quay.getAttribute("data-width"));
  await page.locator("#board .hakushi-style-panel .hakushi-style-action").click();
  await expect(page.locator("#board .hakushi-crop")).toBeVisible();
  const west = (await page.locator('#board .hakushi-crop-handle[data-handle="w"]').boundingBox())!;
  await page.mouse.move(west.x + 6, west.y + 6);
  await page.mouse.down();
  await page.mouse.move(west.x + 86, west.y + 6, { steps: 5 });
  await page.mouse.up();
  await page.keyboard.press("Enter");
  await expect(page.locator("#board .hakushi-crop")).toHaveCount(0);
  await expect.poll(() => quay.getAttribute("data-width").then(Number)).toBeLessThan(width - 50);
  const crop = JSON.parse((await quay.locator("[data-hakushi-crop]").getAttribute("data-hakushi-crop"))!) as number[];
  expect(crop[0]).toBeGreaterThan(0.1);
  expect(crop[2]).toBeCloseTo(1 - crop[0], 3);

  await page.locator("#board").focus();
  await page.keyboard.press(`${await mod(page)}+z`);
  await expect.poll(() => quay.getAttribute("data-width").then(Number)).toBe(width);
  await expect(quay.locator("[data-hakushi-crop]")).toHaveAttribute("data-hakushi-crop", "[0,0,1,1]");
});

test("an image's address pasted is fetched by the server; a file that is not an image is refused", async ({ page }) => {
  await openCanvas(page, "/board");
  const count = await images(page).count();
  const origin = new URL(page.url()).origin;
  await pasteOn(page, { text: `${origin}/fixtures/rope.png` });
  await expect(images(page)).toHaveCount(count + 1);
  await expect(page.locator("#board .hakushi-file")).toHaveCount(0);

  await pasteOn(page, { file: { name: "page.png", type: "image/png", text: "<html><script>alert(1)</script></html>" } });
  await expect(page.locator("#board .hakushi-notice")).toContainText("not an image");
  await expect(page.locator("#board .hakushi-file")).toHaveCount(0);
  await expect(images(page)).toHaveCount(count + 1);
});

test("the export draws the images; a zoomed-out canvas shows their smaller copies", async ({ page }) => {
  await openCanvas(page, "/board");
  const svg = await page.evaluate(async () => (await (window as any).canvasOf("board").exportImage({ format: "svg" })).text() as Promise<string>);
  expect(svg.match(/<img [^>]*src="data:image\/(jpeg|png)/g)?.length).toBe(3);

  const quay = node(page, "quay").locator("img");
  const full = await quay.getAttribute("src");
  await page.evaluate(() => (window as any).canvasOf("board").zoomTo(0.3));
  await expect(quay).toHaveAttribute("src", /harbour-small\.jpg$/);
  await page.evaluate(() => (window as any).canvasOf("board").zoomTo(1));
  await expect(quay).toHaveAttribute("src", full!);
});
