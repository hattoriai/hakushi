// The geometry of images on the canvas (Hakushi.Kits.Images): the size a
// new image takes in the view, the places of several dropped at once, a
// resize that keeps an image's aspect ratio, and a crop, as fractions of
// the file and as a box on the canvas.

import type { Point, Rect } from "./types";

/** The most an image takes of the view, wide or high, when it is added. */
const VIEW_SHARE = 0.6;
/** The widest a new image is, at 100%, whatever the view. */
const MAX_WIDTH = 480;
const GAP = 16;

/** A crop: x, y, width and height, as fractions of the file. */
export type Crop = [number, number, number, number];

/** The size of a new image: its own, made smaller to fit the view (in the canvas's terms). */
export function fitImage(pixels: { width: number; height: number }, view: { width: number; height: number }): { width: number; height: number } {
  const w = Math.max(1, pixels.width);
  const h = Math.max(1, pixels.height);
  const scale = Math.min(1, MAX_WIDTH / w, (view.width * VIEW_SHARE) / w, (view.height * VIEW_SHARE) / h);
  return { width: Math.max(16, Math.round(w * scale)), height: Math.max(16, Math.round(h * scale)) };
}

/** The places of images added together: a row, centred on the point. */
export function rowAt(sizes: { width: number; height: number }[], at: Point): Rect[] {
  const total = sizes.reduce((sum, s) => sum + s.width, 0) + GAP * Math.max(0, sizes.length - 1);
  let x = at.x - total / 2;
  return sizes.map((s) => {
    const rect = { x: Math.round(x), y: Math.round(at.y - s.height / 2), width: s.width, height: s.height };
    x += s.width + GAP;
    return rect;
  });
}

/**
 * A box resized by a corner or a side (`"se"`, `"e"`) by `dx` and `dy`,
 * with its aspect ratio (width / height) kept: a corner follows the side
 * that moved the most, and a side keeps the box's middle on the other axis.
 */
export function aspectResize(rect: Rect, corner: string, dx: number, dy: number, aspect: number, min = 24): Rect {
  const east = corner.includes("e");
  const west = corner.includes("w");
  const south = corner.includes("s");
  const north = corner.includes("n");
  let width = rect.width + (east ? dx : west ? -dx : 0);
  let height = rect.height + (south ? dy : north ? -dy : 0);
  const minW = Math.max(min, min * aspect);
  if ((east || west) && (north || south)) {
    if (Math.abs(width / rect.width - 1) >= Math.abs(height / rect.height - 1)) height = width / aspect;
    else width = height * aspect;
  } else if (east || west) {
    height = width / aspect;
  } else {
    width = height * aspect;
  }
  if (width < minW) {
    width = minW;
    height = width / aspect;
  }
  let x = west ? rect.x + rect.width - width : rect.x;
  let y = north ? rect.y + rect.height - height : rect.y;
  // A side: the box grows about its middle on the other axis.
  if (!(north || south)) y = rect.y + (rect.height - height) / 2;
  if (!(east || west)) x = rect.x + (rect.width - width) / 2;
  return { x, y, width, height };
}

/** The whole file on the canvas, for a node's box and its crop. */
export function fullOf(box: Rect, crop: Crop): Rect {
  const [cx, cy, cw, ch] = crop;
  const width = box.width / cw;
  const height = box.height / ch;
  return { x: box.x - cx * width, y: box.y - cy * height, width, height };
}

/** The crop of a box over the whole file, as fractions of it. */
export function cropOf(full: Rect, box: Rect): Crop {
  const f = (n: number) => Math.round(n * 100_000) / 100_000;
  const x = clamp((box.x - full.x) / full.width, 0, 1);
  const y = clamp((box.y - full.y) / full.height, 0, 1);
  return [f(x), f(y), f(clamp(box.width / full.width, 0.001, 1 - x)), f(clamp(box.height / full.height, 0.001, 1 - y))];
}

/** A crop's box dragged by a corner, a side (`"nw"`, `"e"`) or as a whole (`"move"`), within the file. */
export function dragCrop(full: Rect, start: Rect, handle: string, dx: number, dy: number, min = 16): Rect {
  const right = full.x + full.width;
  const bottom = full.y + full.height;
  if (handle === "move") {
    const x = clamp(start.x + dx, full.x, right - start.width);
    const y = clamp(start.y + dy, full.y, bottom - start.height);
    return { ...start, x, y };
  }
  let { x, y } = start;
  let x2 = start.x + start.width;
  let y2 = start.y + start.height;
  if (handle.includes("w")) x = clamp(start.x + dx, full.x, x2 - min);
  if (handle.includes("e")) x2 = clamp(x2 + dx, x + min, right);
  if (handle.includes("n")) y = clamp(start.y + dy, full.y, y2 - min);
  if (handle.includes("s")) y2 = clamp(y2 + dy, y + min, bottom);
  return { x, y, width: x2 - x, height: y2 - y };
}

/** The address of an image, from what a person pasted or dropped: one `http(s)` URL, or null. */
export function imageAddress(text: string): string | null {
  const value = text.trim();
  if (!/^https?:\/\/\S+$/i.test(value) || value.length > 2048) return null;
  try {
    const url = new URL(value);
    return url.protocol === "http:" || url.protocol === "https:" ? url.href : null;
  } catch {
    return null;
  }
}

function clamp(n: number, lo: number, hi: number): number {
  return Math.min(hi, Math.max(lo, n));
}
