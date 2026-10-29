// The tools of an app's own (registerTool): a button of the canvas's bar
// of tools, and what the pointer does with it, in the browser. A canvas
// shows the ones its `client_tools` names.

import type { Canvas } from "./canvas";
import type { Point } from "./types";

/** What a tool of the app's own has to work with, on the canvas it works on. */
export interface ToolContext {
  /** The canvas: its view, its nodes and edges, its selection. */
  readonly canvas: Canvas;
  /**
   * An SVG group above the nodes, in the canvas's terms (a point of the
   * canvas is a point of it), for what the tool draws as it works; emptied
   * when another tool is chosen.
   */
  readonly layer: SVGGElement;
  /** An SVG element for the layer, with its attributes. */
  svg(tag: string, attributes?: Record<string, string | number>): SVGElement;
  /** The ids of the nodes under a point of the canvas, the topmost first. */
  nodesAt(point: Point): string[];
  /** Selects nodes, as a click does. */
  select(ids: string[]): void;
  /** Moves nodes, as a drag does: a change the server checks (`on_change`), and undo takes back. */
  move(places: { id: string; x: number; y: number }[]): Promise<Record<string, unknown>>;
  /** Connects two nodes (and handles), as a person does. */
  connect(source: { node: string; handle?: string | null }, target: { node: string; handle?: string | null }): Promise<Record<string, unknown>>;
  /** Deletes nodes (with their edges) and edges, as Delete does. */
  remove(nodes: string[], edges?: string[]): Promise<Record<string, unknown>>;
  /** A new node at a point of the canvas: the canvas's `new_node` for `item`, as a drop does. */
  drop(item: string | null, at: Point): void;
  /** An event to the canvas's LiveView (its `handle_event/3`), with a reply if it gives one. */
  pushEvent(event: string, payload: object, onReply?: (reply: Record<string, unknown>) => void): void;
  /** Words for screen readers, in the canvas's live region. */
  announce(text: string): void;
}

/** A tool of the app's own (registerTool). */
export interface ClientTool {
  /** Its name, the canvas's `client_tools` name it: a-z, 0-9 and -. */
  name: string;
  /** Its name for people: the button's label. */
  label: string;
  /** Its icon, as the markup of an SVG of 24 by 24 (stroke `currentColor`); a pointer unless given. */
  icon?: string;
  /** The letter that chooses it, as the kits' tools have theirs. */
  key?: string;
  /** The CSS cursor over the canvas while it is chosen. */
  cursor?: string;
  /** Whether it is offered on a read-only canvas too (a tool that changes nothing: a ruler). */
  readonly?: boolean;
  /** The pointer pressed on the canvas, at a point of the canvas. */
  down?(context: ToolContext, event: PointerEvent, at: Point): void;
  /** The pointer moved, pressed. */
  move?(context: ToolContext, event: PointerEvent, at: Point): void;
  /** The pointer let go. */
  up?(context: ToolContext, event: PointerEvent, at: Point): void;
  /** The press cancelled: Escape, a second finger, the pointer lost. */
  cancel?(context: ToolContext): void;
  /** The tool chosen, and put down for another. */
  chosen?(context: ToolContext): void;
  dropped?(context: ToolContext): void;
}

const registry = new Map<string, ClientTool>();

/**
 * Adds a tool of the app's own to the canvases that name it (their
 * `client_tools`), at once and on those to come. A tool of the same name
 * takes its place.
 */
export function registerTool(tool: ClientTool): void {
  if (!/^[a-z][a-z0-9-]{0,31}$/.test(tool.name)) throw new Error(`Hakushi: a tool's name is a-z, 0-9 and -, got ${JSON.stringify(tool.name)}`);
  if (!tool.label) throw new Error(`Hakushi: the tool ${tool.name} has no label`);
  registry.set(tool.name, tool);
  if (typeof document !== "undefined") document.dispatchEvent(new CustomEvent("hakushi:tools"));
}

/** A tool of the app's own, by its name. */
export function clientTool(name: string): ClientTool | undefined {
  return registry.get(name);
}
