// The overview in a corner: the nodes as boxes, the part of the canvas on
// the screen, and a pointer that moves the view.

import { union } from "./geometry";
import type { Rect } from "./types";

const WIDTH = 200;
const HEIGHT = 140;

export class Minimap {
  readonly el: HTMLCanvasElement;
  private scale = 1;
  private origin = { x: 0, y: 0 };
  private dragging = false;
  // The nodes drawn once, and drawn again only when they change.
  private layer: HTMLCanvasElement = document.createElement("canvas");
  private drawn: { version: number; box: string } | null = null;
  private colors: { node: string; accent: string; mask: string } | null = null;

  constructor(
    label: string,
    private onMove: (x: number, y: number) => void,
  ) {
    this.el = document.createElement("canvas");
    this.el.className = "hakushi-minimap";
    this.el.setAttribute("role", "img");
    this.el.setAttribute("aria-label", label);
    const ratio = window.devicePixelRatio || 1;
    this.el.width = WIDTH * ratio;
    this.el.height = HEIGHT * ratio;
    this.el.style.width = `${WIDTH}px`;
    this.el.style.height = `${HEIGHT}px`;

    this.el.addEventListener("pointerdown", (event) => {
      event.preventDefault();
      event.stopPropagation();
      this.dragging = true;
      this.el.setPointerCapture(event.pointerId);
      this.move(event);
    });
    this.el.addEventListener("pointermove", (event) => {
      if (this.dragging) this.move(event);
    });
    const stop = () => (this.dragging = false);
    this.el.addEventListener("pointerup", stop);
    this.el.addEventListener("pointercancel", stop);
  }

  private move(event: PointerEvent) {
    const rect = this.el.getBoundingClientRect();
    const x = (event.clientX - rect.left) / this.scale + this.origin.x;
    const y = (event.clientY - rect.top) / this.scale + this.origin.y;
    this.onMove(x, y);
  }

  /** The colors of the theme: read again when the theme changes (`refresh`). */
  refresh() {
    this.colors = null;
    this.drawn = null;
  }

  /**
   * Draws the nodes (with the selected ones in the accent) and the view.
   * `version` changes whenever the nodes do: the same version, with the
   * same box, draws only the view again.
   */
  draw(nodes: () => (Rect & { selected: boolean })[], version: number, all: Rect | null, view: Rect) {
    const box = union(all ? [all, view] : [view]) ?? view;
    const pad = 8;
    this.scale = Math.min((WIDTH - pad * 2) / Math.max(box.width, 1), (HEIGHT - pad * 2) / Math.max(box.height, 1));
    this.origin = {
      x: box.x - (WIDTH / this.scale - box.width) / 2,
      y: box.y - (HEIGHT / this.scale - box.height) / 2,
    };

    const ratio = window.devicePixelRatio || 1;
    if (!this.colors) {
      const style = getComputedStyle(this.el);
      this.colors = {
        node: style.getPropertyValue("--hakushi-minimap-node").trim() || "#9a9aa6",
        accent: style.getPropertyValue("--hakushi-accent").trim() || "#2f5bd3",
        mask: style.getPropertyValue("--hakushi-minimap-mask").trim() || "rgba(0,0,0,0.06)",
      };
    }
    const colors = this.colors;

    const key = `${this.scale}:${this.origin.x}:${this.origin.y}`;
    if (!this.drawn || this.drawn.version !== version || this.drawn.box !== key) {
      this.layer.width = WIDTH * ratio;
      this.layer.height = HEIGHT * ratio;
      const lc = this.layer.getContext("2d");
      if (lc) {
        lc.setTransform(ratio, 0, 0, ratio, 0, 0);
        for (const r of nodes()) {
          lc.fillStyle = r.selected ? colors.accent : colors.node;
          lc.fillRect((r.x - this.origin.x) * this.scale, (r.y - this.origin.y) * this.scale, Math.max(r.width * this.scale, 1.5), Math.max(r.height * this.scale, 1.5));
        }
      }
      this.drawn = { version, box: key };
    }

    const ctx = this.el.getContext("2d");
    if (!ctx) return;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, this.el.width, this.el.height);
    ctx.drawImage(this.layer, 0, 0);
    ctx.setTransform(ratio, 0, 0, ratio, 0, 0);

    // Outside the view, a veil.
    const vx = (view.x - this.origin.x) * this.scale;
    const vy = (view.y - this.origin.y) * this.scale;
    const vw = view.width * this.scale;
    const vh = view.height * this.scale;
    ctx.fillStyle = colors.mask;
    ctx.beginPath();
    ctx.rect(0, 0, WIDTH, HEIGHT);
    ctx.rect(vx, vy, vw, vh);
    ctx.fill("evenodd");
    ctx.strokeStyle = colors.accent;
    ctx.lineWidth = 1.5;
    ctx.strokeRect(vx, vy, vw, vh);
  }
}
