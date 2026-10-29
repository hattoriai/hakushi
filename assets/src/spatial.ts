// Where things are on the canvas: a grid of square cells, each with the
// ids of the boxes over it, so that what is near a place (the screen, a
// point) is found without looking at every box.

import type { Point, Rect } from "./types";

export class SpatialIndex {
  private cells = new Map<number, Set<string>>();
  private boxes = new Map<string, { rect: Rect; range: [number, number, number, number] }>();

  /** `cell` is the side of a cell, in the canvas's terms. */
  constructor(private cell = 512) {}

  get size(): number {
    return this.boxes.size;
  }

  /** Puts a box under its id, or moves it there. */
  set(id: string, rect: Rect): void {
    const range = this.range(rect);
    const old = this.boxes.get(id);
    if (old && old.range.every((v, i) => v === range[i])) {
      old.rect = rect;
      return;
    }
    if (old) this.forEach(old.range, (key) => this.cells.get(key)?.delete(id));
    this.forEach(range, (key) => {
      let set = this.cells.get(key);
      if (!set) this.cells.set(key, (set = new Set()));
      set.add(id);
    });
    this.boxes.set(id, { rect, range });
  }

  delete(id: string): void {
    const old = this.boxes.get(id);
    if (!old) return;
    this.forEach(old.range, (key) => {
      const set = this.cells.get(key);
      if (!set) return;
      set.delete(id);
      if (set.size === 0) this.cells.delete(key);
    });
    this.boxes.delete(id);
  }

  get(id: string): Rect | undefined {
    return this.boxes.get(id)?.rect;
  }

  /** The ids of the boxes that meet `rect`. */
  query(rect: Rect): Set<string> {
    const found = new Set<string>();
    this.forEach(this.range(rect), (key) => {
      for (const id of this.cells.get(key) ?? []) {
        if (found.has(id)) continue;
        const box = this.boxes.get(id)!.rect;
        if (box.x <= rect.x + rect.width && rect.x <= box.x + box.width && box.y <= rect.y + rect.height && rect.y <= box.y + box.height) found.add(id);
      }
    });
    return found;
  }

  /** The ids of the boxes a point is in. */
  at(p: Point): string[] {
    return [...this.query({ x: p.x, y: p.y, width: 0, height: 0 })].filter((id) => {
      const box = this.boxes.get(id)!.rect;
      return p.x >= box.x && p.x <= box.x + box.width && p.y >= box.y && p.y <= box.y + box.height;
    });
  }

  // The cells a box is over: [first column, first row, last column, last row].
  private range(r: Rect): [number, number, number, number] {
    const c = this.cell;
    return [Math.floor(r.x / c), Math.floor(r.y / c), Math.floor((r.x + Math.max(r.width, 0)) / c), Math.floor((r.y + Math.max(r.height, 0)) / c)];
  }

  private forEach([x0, y0, x1, y1]: [number, number, number, number], fn: (key: number) => void) {
    // At most a thousand cells a side (half a million pixels of the canvas,
    // with cells of 512): no node is that large, and a box past it is found
    // only in its first thousand.
    for (let x = x0; x <= Math.min(x1, x0 + 1000); x++) {
      for (let y = y0; y <= Math.min(y1, y0 + 1000); y++) fn(key(x, y));
    }
  }
}

// One number for a cell: columns and rows from -2^20 to 2^20.
function key(x: number, y: number): number {
  return (x + 1_048_576) * 2_097_152 + (y + 1_048_576);
}
