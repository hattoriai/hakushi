import { expect, test } from "@playwright/test";
import { center, drag, node, openCanvas, place } from "./support";

test("two people on one canvas: the moves, the cursors, the avatars", async ({ browser }) => {
  const ada = await (await browser.newContext()).newPage();
  const kenji = await (await browser.newContext()).newPage();
  const room = await openCanvas(ada, "/", undefined, "&as=ada");
  await openCanvas(kenji, "/", room, "&as=kenji");

  await expect(ada.locator('#schema [data-person="kenji"]')).toBeVisible();
  await expect(kenji.locator('#schema [data-person="ada"]')).toBeVisible();

  // Kenji's cursor, with his name.
  const box = (await kenji.locator("#schema").boundingBox())!;
  await kenji.mouse.move(box.x + 300, box.y + 200);
  await kenji.mouse.move(box.x + 320, box.y + 210, { steps: 3 });
  await expect(ada.locator("#schema .hakushi-cursor")).toContainText("Kenji Mori");

  // Kenji moves a table; Ada sees it where he left it.
  const at = await center(node(kenji, "invoices").locator("header"));
  await drag(kenji, at, { x: at.x - 100, y: at.y + 40 });
  await expect.poll(async () => (await place(kenji, "invoices")).x).not.toBe(360);
  const moved = await place(kenji, "invoices");
  await expect.poll(() => place(ada, "invoices")).toEqual(moved);
});

test("a change the server refuses goes back, with the reason", async ({ page }) => {
  await openCanvas(page, "/");
  // A uuid to a text column: the browser does not offer it, so ask the
  // server through the hook as a browser that does not follow the rules.
  const reply = await page.evaluate(
    () =>
      new Promise((resolve) => {
        const canvas = (window as unknown as { canvasOf(id: string): { live: { push(e: string, p: object, r: (x: unknown) => void): void } } }).canvasOf("schema");
        canvas.live.push("hakushi:change", { op: "connect", edges: [{ source: "tasks", sourceHandle: "title", target: "people", targetHandle: "id" }] }, resolve);
      }),
  );
  expect(JSON.stringify(reply)).toContain("do not join");
  await expect(page.locator("#schema > .hakushi-notice")).toContainText("tasks.title is text and people.id is uuid");
});
