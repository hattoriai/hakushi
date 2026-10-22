import { expect, test } from "@playwright/test";
import { center, drag, node, openCanvas, place, zoom } from "./support";

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

test("following someone: the canvas shows what they show, until one goes one's own way", async ({ browser }) => {
  const ada = await (await browser.newContext()).newPage();
  const kenji = await (await browser.newContext()).newPage();
  const room = await openCanvas(ada, "/", undefined, "&as=ada");
  await openCanvas(kenji, "/", room, "&as=kenji");

  // Ada follows Kenji from his avatar: the room's following (Issho's), on the page.
  const avatar = ada.locator('#schema [data-person="kenji"]');
  await avatar.click();
  await expect(avatar).toHaveAttribute("aria-pressed", "true");
  await expect.poll(() => ada.evaluate(() => document.documentElement.dataset.isshoFollowing ?? "")).toContain("kenji");
  // The canvas says whom it follows, in their colour, with Stop, and has a ring of it.
  const line = ada.locator("#schema .hakushi-following");
  await expect(line).toContainText(/Following Kenji/i);
  await expect(ada.locator("#schema")).toHaveAttribute("data-ui-following", "");

  // Kenji zooms in twice: Ada's canvas goes with him.
  await kenji.locator('#schema [data-action="zoom-in"]').click();
  await kenji.locator('#schema [data-action="zoom-in"]').click();
  await expect.poll(() => zoom(kenji)).toBeGreaterThan(100);
  await expect.poll(async () => Math.abs((await zoom(ada)) - (await zoom(kenji)))).toBeLessThanOrEqual(5);

  // Ada's own wheel on the canvas stops following; her view stays hers.
  const box = (await ada.locator("#schema").boundingBox())!;
  await ada.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await ada.mouse.wheel(0, 60);
  await expect(avatar).toHaveAttribute("aria-pressed", "false");
  await expect.poll(() => ada.evaluate(() => document.documentElement.dataset.isshoFollowing ?? "")).toBe("");
  await expect(line).toHaveCount(0);
  await expect(ada.locator("#schema")).not.toHaveAttribute("data-ui-following", "");

  // Stop, from the line.
  await avatar.click();
  await expect(line).toBeVisible();
  await line.getByRole("button", { name: "Stop" }).click();
  await expect(line).toHaveCount(0);
  await expect(avatar).toHaveAttribute("aria-pressed", "false");

  await ada.context().close();
  await kenji.context().close();
});

test("a canvas with follow={false}: its avatars follow no one, and it shows no one followed", async ({ browser }) => {
  const ada = await (await browser.newContext()).newPage();
  const kenji = await (await browser.newContext()).newPage();
  const room = await openCanvas(ada, "/", undefined, "&as=ada&follow=false");
  await openCanvas(kenji, "/", room, "&as=kenji");
  const avatar = ada.locator('#schema .hakushi-person[data-person="kenji"]');
  await expect(avatar).toBeVisible();
  await expect(ada.locator("#schema button.hakushi-person")).toHaveCount(0);
  await avatar.click();
  await expect.poll(() => ada.evaluate(() => document.documentElement.dataset.isshoFollowing ?? "")).toBe("");

  // The room follows Kenji (another block of the page could): this canvas shows nothing of it.
  await ada.evaluate((room) => {
    document.documentElement.dataset.isshoFollowing = JSON.stringify({ [room]: "kenji" });
    document.dispatchEvent(new CustomEvent("issho:following", { detail: { room, key: "kenji" } }));
  }, await ada.locator("#schema").evaluate((el) => el.dataset.isshoDoc!.split("/")[0]));
  await expect(ada.locator("#schema .hakushi-following")).toHaveCount(0);
  await expect(ada.locator("#schema")).not.toHaveAttribute("data-ui-following", "");

  await ada.context().close();
  await kenji.context().close();
});

// A shared canvas lets its room go when it goes: on a navigation away its
// LiveView is gone too, which is no error of the page.
test("a shared canvas that goes with its page, by a navigation, throws nothing", async ({ page }) => {
  const errors: string[] = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await openCanvas(page, "/", undefined, "&as=ada");
  await expect(page.locator("[data-issho-doc]").first()).toBeAttached();
  await page.evaluate(() => (window as unknown as { liveSocket: { js(): { navigate(href: string): void } } }).liveSocket.js().navigate("/board"));
  await expect(page).toHaveURL(/\/board/);
  await expect(page.locator("[data-phx-main].phx-connected")).toBeVisible();
  await page.waitForTimeout(300);
  expect(errors).toEqual([]);
});
