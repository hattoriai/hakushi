// The paper of the moodboard (/board): a picker of papers in the controls,
// one of them the app's own, which everyone on the canvas sees.

import { expect, test, type Page } from "@playwright/test";
import { mod, openCanvas } from "./support";

const button = (page: Page) => page.locator('#board [data-action="paper"]');
const item = (page: Page, key: string) => page.locator(`#board [data-paper-item="${key}"]`);
const grid = (page: Page) => page.evaluate(() => JSON.parse(document.querySelector<HTMLElement>("#board .hakushi-hook")!.dataset.config!).grid as number);

test("a paper chosen from the controls, which the others see and ⌘Z takes back", async ({ browser }) => {
  const ada = await (await browser.newContext()).newPage();
  const kenji = await (await browser.newContext()).newPage();
  const room = await openCanvas(ada, "/board", undefined, "&as=ada");
  await openCanvas(kenji, "/board", room, "&as=kenji");
  await expect(ada.locator("#board")).toHaveAttribute("data-background", "cross");

  await button(ada).click();
  await expect(button(ada)).toHaveAttribute("aria-expanded", "true");
  // The menu opens on the paper there is.
  await expect(item(ada, "paper:cross")).toHaveAttribute("aria-checked", "true");
  await expect(item(ada, "paper:cross")).toBeFocused();

  // The app's own paper, and larger squares.
  await item(ada, "paper:iso").click();
  await expect(ada.locator("#board")).toHaveAttribute("data-background", "iso");
  await expect(item(ada, "paper:iso")).toHaveAttribute("aria-checked", "true");
  const size = () => ada.evaluate(() => parseFloat(document.querySelector<HTMLElement>("#board-viewport")!.style.getPropertyValue("--hakushi-grid-size")));
  const before = await size();
  await item(ada, "grid:40").click();
  await expect.poll(() => grid(ada)).toBe(40);
  await expect(kenji.locator("#board")).toHaveAttribute("data-background", "iso");
  await expect.poll(() => grid(kenji)).toBe(40);
  // The paper is drawn at the new size at once, without a move of the view.
  await expect.poll(size).toBeCloseTo(before * 2, 1);

  // Escape closes the menu, back on its button; ⌘Z takes each choice back.
  await ada.keyboard.press("Escape");
  await expect(ada.locator("#board .hakushi-paper-menu")).toHaveCount(0);
  await expect(button(ada)).toBeFocused();
  await ada.locator("#board").focus();
  await ada.keyboard.press(`${await mod(ada)}+z`);
  await expect.poll(() => grid(kenji)).toBe(20);
  await ada.keyboard.press(`${await mod(ada)}+z`);
  await expect(kenji.locator("#board")).toHaveAttribute("data-background", "cross");
});

test("the menu of papers by the keyboard", async ({ page }) => {
  await openCanvas(page, "/board");
  await button(page).focus();
  await page.keyboard.press("Enter");
  await expect(item(page, "paper:cross")).toBeFocused();
  await page.keyboard.press("ArrowUp");
  await expect(item(page, "paper:lines")).toBeFocused();
  await page.keyboard.press("Enter");
  await expect(page.locator("#board")).toHaveAttribute("data-background", "lines");
  await expect(page.locator("#board .hakushi-status")).toContainText("Paper: Graph paper.");
  // The arrows go round; the view stays.
  const view = await page.evaluate(() => (window as any).canvasOf("board").getView());
  await page.keyboard.press("End");
  await expect(item(page, "grid:40")).toBeFocused();
  await page.keyboard.press("ArrowDown");
  await expect(item(page, "paper:dots")).toBeFocused();
  expect(await page.evaluate(() => (window as any).canvasOf("board").getView())).toEqual(view);
  // A press elsewhere closes it.
  await page.mouse.click(700, 300);
  await expect(page.locator("#board .hakushi-paper-menu")).toHaveCount(0);
});

test("a viewer has no picker; an export may have the paper", async ({ page }) => {
  await openCanvas(page, "/board", undefined, "&as=viewer");
  await expect(button(page)).toHaveCount(0);

  const svg = (await page.evaluate(async () => {
    const blob = await (window as any).canvasOf("board").exportImage({ format: "svg", paper: true });
    return blob.text();
  })) as string;
  expect(svg).toContain('data-background="cross"');
  expect(svg).toContain('class="hakushi-background"');
  const plain = (await page.evaluate(async () => (await (window as any).canvasOf("board").exportImage({ format: "svg" })).text())) as string;
  expect(plain).not.toContain('class="hakushi-background"');
});
