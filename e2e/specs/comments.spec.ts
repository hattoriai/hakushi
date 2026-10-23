import { expect, test } from "@playwright/test";
import { node, openCanvas } from "./support";

// Issho's comments beside a shared canvas (the schema with comments=1): a
// thread on a table, said by its name, marked on the table for everyone.
test("a thread on a node: said by name, and marked on the node for everyone", async ({ browser }) => {
  const ada = await (await browser.newContext()).newPage();
  const kenji = await (await browser.newContext()).newPage();
  const room = await openCanvas(ada, "/", undefined, "&as=ada&comments=1");
  await openCanvas(kenji, "/", room, "&as=kenji&comments=1");

  // Ada selects a table: the comment goes on it, as the canvas says it.
  await node(ada, "clients").locator("header").click();
  await expect(ada.locator("#comments .issho-composer .issho-where-label")).toHaveText("The node “clients”");
  await ada.locator("#comments .issho-composer textarea").fill("Should a client have a phone?");
  await ada.locator("#comments .issho-composer").getByRole("button", { name: "Comment" }).click();

  for (const page of [ada, kenji]) {
    const thread = page.locator("#comments .issho-thread");
    await expect(thread.locator(".issho-thread-place-label")).toHaveText("The node “clients”");
    await expect(thread).toContainText("Should a client have a phone?");

    // Its mark, at the table's top right corner.
    const mark = page.locator(".issho-comment-mark");
    await expect(mark).toBeVisible();
    const table = (await node(page, "clients").boundingBox())!;
    const spot = (await mark.boundingBox())!;
    expect(Math.abs(spot.x + spot.width / 2 - (table.x + table.width))).toBeLessThan(24);
    expect(Math.abs(spot.y + spot.height / 2 - table.y)).toBeLessThan(24);
  }

  // Kenji deletes the table: the thread stays, and its place has no name now.
  await kenji.evaluate(() => {
    const canvas = (window as unknown as { canvasOf(id: string): { live: { push(e: string, p: object, r: (x: unknown) => void): void } } }).canvasOf("schema");
    canvas.live.push("hakushi:change", { op: "delete", nodes: ["clients"] }, () => {});
  });
  await expect(ada.locator("#comments .issho-thread .issho-thread-place-label")).toHaveText("On a part of the page");
});
