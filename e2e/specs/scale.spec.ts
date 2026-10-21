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

test("a pan of two thousand nodes keeps its frames", async ({ page, browserName }) => {
  // CI's headless WebKit measures a median pan frame of about 60ms that no
  // other WebKit reproduced (WebKitGTK: 23-28ms): run it locally in WebKit
  // until it is understood (hattoriai/hakushi#5).
  test.skip(browserName === "webkit" && !!process.env.CI, "CI's headless WebKit, hattoriai/hakushi#5: run it locally");
  await openCanvas(page, "/scale");
  const box = (await page.locator("#scale").boundingBox())!;
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  // The frames of the browser itself, with nothing moving, and then those
  // of a pan: a headless browser without a GPU (WebKit in CI) has slower
  // frames of its own, which are not the canvas's.
  const frames = await page.evaluate(async () => {
    const run = (count: number, pan: boolean) =>
      new Promise<{ median: number; p95: number }>((done) => {
        const times: number[] = [];
        let last = performance.now();
        const tick = (now: number) => {
          times.push(now - last);
          last = now;
          if (pan) document.getElementById("scale")!.dispatchEvent(new WheelEvent("wheel", { deltaX: 25, deltaY: 15, bubbles: true, cancelable: true, clientX: 600, clientY: 400 }));
          if (times.length < count) return requestAnimationFrame(tick);
          times.sort((a, b) => a - b);
          done({ median: times[Math.floor(times.length / 2)], p95: times[Math.floor(times.length * 0.95)] });
        };
        requestAnimationFrame(tick);
      });
    const idle = await run(30, false);
    return { idle, pan: await run(90, true) };
  });
  console.log("frames (ms)", frames);
  expect(frames.pan.median).toBeLessThan(Math.max(34, frames.idle.median * 2));
});
