import { expect, test } from "@playwright/test";
import { node, openCanvas } from "./support";

test("two thousand nodes: only those near the screen are laid out", async ({ page }) => {
  await openCanvas(page, "/scale");
  await expect(page.locator("#scale .hakushi-node")).toHaveCount(2000);
  const laidOut = await page.locator("#scale .hakushi-node:not([data-ui-culled])").count();
  expect(laidOut).toBeLessThan(300);

  // Far out, they all come back.
  await page.locator("#scale").focus();
  for (let i = 0; i < 12; i++) await page.keyboard.press("-");
  await expect.poll(() => page.locator("#scale .hakushi-node:not([data-ui-culled])").count()).toBeGreaterThan(laidOut);
  await expect(node(page, "n1999")).toBeAttached();
});

test("a pan of two thousand nodes keeps its frames", async ({ page }) => {
  await openCanvas(page, "/scale");
  const box = (await page.locator("#scale").boundingBox())!;
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  const frames = await page.evaluate(async () => {
    const times: number[] = [];
    let last = performance.now();
    await new Promise<void>((done) => {
      let n = 0;
      const tick = (now: number) => {
        times.push(now - last);
        last = now;
        window.dispatchEvent(new Event("tick"));
        document.getElementById("scale")!.dispatchEvent(new WheelEvent("wheel", { deltaX: 25, deltaY: 15, bubbles: true, cancelable: true, clientX: 600, clientY: 400 }));
        if (++n < 90) requestAnimationFrame(tick);
        else done();
      };
      requestAnimationFrame(tick);
    });
    times.sort((a, b) => a - b);
    return { median: times[Math.floor(times.length / 2)], p95: times[Math.floor(times.length * 0.95)] };
  });
  console.log("pan frames (ms)", frames);
  expect(frames.median).toBeLessThan(34);
});
