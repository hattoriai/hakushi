import { expect, test } from "@playwright/test";
import { node, openCanvas } from "./support";

test("two thousand nodes: only those near the screen are laid out", async ({ page }) => {
  // A megabyte of nodes, twice (the page, then the LiveView's): CI's
  // WebKit takes more than an expect's 5 seconds to connect at times.
  await page.goto(`/scale?room=t${Date.now()}`, { timeout: 60_000 });
  await expect(page.locator("[data-phx-main].phx-connected")).toBeVisible({ timeout: 30_000 });
  await expect(page.locator("#scale .hakushi-node")).toHaveCount(2000, { timeout: 15_000 });
  // The first frame: the view is fitted, and the nodes far off it culled.
  await page.waitForFunction(() => document.querySelectorAll("#scale .hakushi-edge-line[d]").length > 0, null, { timeout: 15_000 });
  const laidOut = await page.locator("#scale .hakushi-node:not([data-ui-culled])").count();
  expect(laidOut).toBeLessThan(300);

  // Far out, they all come back.
  await page.locator("#scale").focus();
  for (let i = 0; i < 12; i++) await page.keyboard.press("-");
  await expect.poll(() => page.locator("#scale .hakushi-node:not([data-ui-culled])").count()).toBeGreaterThan(laidOut);
  await expect(node(page, "n1999")).toBeAttached();
});

// The frames of the browser with nothing moving, then of a pan.
async function panFrames(page: import("@playwright/test").Page, canvas: string) {
  return page.evaluate(async (canvas) => {
    const run = (count: number, pan: boolean) =>
      new Promise<{ median: number; p95: number }>((done) => {
        const times: number[] = [];
        let last = performance.now();
        const tick = (now: number) => {
          times.push(now - last);
          last = now;
          if (pan) document.getElementById(canvas)!.dispatchEvent(new WheelEvent("wheel", { deltaX: 60, deltaY: 35, bubbles: true, cancelable: true, clientX: 600, clientY: 400 }));
          if (times.length < count) return requestAnimationFrame(tick);
          times.sort((a, b) => a - b);
          done({ median: times[Math.floor(times.length / 2)], p95: times[Math.floor(times.length * 0.95)] });
        };
        requestAnimationFrame(tick);
      });
    const idle = await run(30, false);
    return { idle, pan: await run(90, true) };
  }, canvas);
}

test("a fast pan of ten thousand nodes keeps its frames: only what is near is looked at", async ({ page, browserName }) => {
  test.skip(browserName === "webkit" && !!process.env.CI, "CI's headless WebKit, hattoriai/hakushi#5: run it locally");
  test.setTimeout(90_000);
  // Six megabytes of nodes, twice (the page, then the LiveView's): more than a canvas's time.
  await page.goto(`/scale?n=10000&room=t${Date.now()}`, { timeout: 60_000 });
  await expect(page.locator("[data-phx-main].phx-connected")).toBeVisible({ timeout: 60_000 });
  await expect(page.locator("#scale .hakushi-node")).toHaveCount(10_000, { timeout: 30_000 });
  await page.waitForTimeout(500);
  const frames = await panFrames(page, "scale");
  console.log("frames of 10,000 (ms)", frames);
  expect(frames.pan.median).toBeLessThan(Math.max(34, frames.idle.median * 2));
  // No slow frames: a frame that looked at every node or edge is one.
  expect(frames.pan.p95).toBeLessThan(Math.max(67, frames.idle.p95 * 3));
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
