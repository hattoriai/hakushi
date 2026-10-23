// The view of a canvas: from the screen to the canvas and back, zoom at a
// point, and the view that shows a box. Pure functions.

import type { Point, Rect, View } from "./types";

export function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

/** The point of the canvas under a point of the screen (relative to the canvas element). */
export function toCanvas(view: View, x: number, y: number): Point {
  return { x: (x - view.x) / view.zoom, y: (y - view.y) / view.zoom };
}

/** The point of the screen of a point of the canvas. */
export function toScreen(view: View, x: number, y: number): Point {
  return { x: x * view.zoom + view.x, y: y * view.zoom + view.y };
}

/** The view zoomed by `factor`, keeping the point (x, y) of the screen in place. */
export function zoomAt(view: View, factor: number, x: number, y: number, min: number, max: number): View {
  const zoom = clamp(view.zoom * factor, min, max);
  const ratio = zoom / view.zoom;
  return { x: x - (x - view.x) * ratio, y: y - (y - view.y) * ratio, zoom };
}

/** The part of the canvas that a screen of `width` by `height` shows. */
export function visible(view: View, width: number, height: number): Rect {
  const origin = toCanvas(view, 0, 0);
  return { x: origin.x, y: origin.y, width: width / view.zoom, height: height / view.zoom };
}

/**
 * The view that shows `box` in a screen of `width` by `height`, in its
 * middle, with `padding` pixels around it, at no more than `maxZoom` (and
 * at most 100%, so that a small graph is not blown up).
 */
export function fit(box: Rect | null, width: number, height: number, padding: number, minZoom: number, maxZoom: number): View {
  if (!box || width <= 0 || height <= 0) return { x: width / 2, y: height / 2, zoom: 1 };
  const zoom = clamp(
    Math.min((width - padding * 2) / Math.max(box.width, 1), (height - padding * 2) / Math.max(box.height, 1)),
    minZoom,
    Math.min(maxZoom, 1),
  );
  return {
    x: width / 2 - (box.x + box.width / 2) * zoom,
    y: height / 2 - (box.y + box.height / 2) * zoom,
    zoom,
  };
}

/**
 * The view a canvas opens on when it should be read (`fit` "readable"):
 * the fitted view when its zoom is `readable` or more; else the zoom of
 * `readable`, on the middle of `focus` (the heart of the graph).
 */
export function readableView(fitted: View, focus: Rect | null, width: number, height: number, readable: number): View {
  if (fitted.zoom >= readable || !focus) return fitted;
  return centerOn({ x: 0, y: 0, zoom: readable }, focus.x + focus.width / 2, focus.y + focus.height / 2, width, height);
}

/** The view that puts the point (x, y) of the canvas in the middle of the screen. */
export function centerOn(view: View, x: number, y: number, width: number, height: number): View {
  return { x: width / 2 - x * view.zoom, y: height / 2 - y * view.zoom, zoom: view.zoom };
}

/** The view moved just enough to show `box` whole, with `margin` pixels; the same view when it does. */
export function reveal(view: View, box: Rect, width: number, height: number, margin: number): View {
  const left = box.x * view.zoom + view.x;
  const top = box.y * view.zoom + view.y;
  const right = left + box.width * view.zoom;
  const bottom = top + box.height * view.zoom;
  let dx = 0;
  let dy = 0;
  if (left < margin) dx = margin - left;
  else if (right > width - margin) dx = Math.max(width - margin - right, margin - left);
  if (top < margin) dy = margin - top;
  else if (bottom > height - margin) dy = Math.max(height - margin - bottom, margin - top);
  return dx === 0 && dy === 0 ? view : { x: view.x + dx, y: view.y + dy, zoom: view.zoom };
}
