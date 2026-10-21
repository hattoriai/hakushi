// The Hakushi hook for a LiveSocket. The hook's element is an empty child
// of the canvas, with its config: LiveView locks a hook's element while
// its events wait for their replies, and the canvas itself is never
// locked. The hook makes a Canvas of its parent, gives it the new config
// (`updated`) and the state of the connection, and passes it the events of
// Hakushi.Canvas (hakushi:people, hakushi:peer) that are its own.

import { Canvas } from "./canvas";
import type { Person } from "./types";

interface HookContext {
  el: HTMLElement;
  pushEventTo(target: string | HTMLElement, event: string, payload: object, onReply?: (reply: Record<string, unknown>, ref: number) => void): void;
  pushEvent(event: string, payload: object): void;
  handleEvent(event: string, callback: (payload: Record<string, unknown>) => void): void;
}

interface HakushiHook extends HookContext {
  canvas?: Canvas;
}

// The canvases, by their element: for the tests, and for an app's own code
// (`canvasOf(element)`).
const canvases = new WeakMap<HTMLElement, Canvas>();

export const Hakushi = {
  mounted(this: HakushiHook) {
    const hook = this;
    const root = hook.el.parentElement!;
    const canvas = new Canvas(root, hook.el, {
      push(event, payload, onReply) {
        hook.pushEventTo(hook.el, event, payload, onReply ? (reply) => onReply(reply) : undefined);
      },
    });
    hook.canvas = canvas;
    canvases.set(root, canvas);

    hook.handleEvent("hakushi:people", (payload) => {
      if (payload.canvas === canvas.id) canvas.setPeople(payload.people as Person[]);
    });
    hook.handleEvent("hakushi:peer", (payload) => {
      if (payload.canvas === canvas.id) canvas.receivePeer(payload);
    });
    hook.handleEvent("hakushi:layout", (payload) => {
      if (payload.canvas === canvas.id) void canvas.layout({ direction: payload.direction as "right" | "down" | undefined });
    });
    hook.handleEvent("hakushi:export", (payload) => {
      if (payload.canvas === canvas.id) void canvas.download({ format: payload.format as "png" | "svg" | undefined, filename: payload.filename as string | undefined });
    });
  },

  updated(this: HakushiHook) {
    this.canvas?.update();
  },

  disconnected(this: HakushiHook) {
    this.canvas?.setConnected(false);
  },

  reconnected(this: HakushiHook) {
    this.canvas?.setConnected(true);
  },

  destroyed(this: HakushiHook) {
    // A shared canvas that goes while its LiveView stays (an embed deleted
    // from a document): its room lets it go (Issho.Live.release/2), and the
    // LiveView leaves it with its last canvas there.
    const room = this.canvas?.root.dataset.isshoDoc;
    if (room && this.canvas) {
      try {
        this.pushEvent("issho:release", { room, component: this.canvas.id });
      } catch {
        // The LiveView went with it: so did its rooms.
      }
    }
    if (this.canvas) canvases.delete(this.canvas.root);
    this.canvas?.destroy();
    this.canvas = undefined;
  },
};

/** The canvas of a canvas's element (`.hakushi`, the id of the canvas), or undefined. */
export function canvasOf(element: HTMLElement): Canvas | undefined {
  return canvases.get(element);
}
