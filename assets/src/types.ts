// The shapes the canvas works with: its config (from the server's
// data-config), its view, its nodes, handles and edges, as the browser
// keeps them.

export type Side = "left" | "right" | "top" | "bottom";
export type HandleKind = "source" | "target" | "both";
export type PathKind = "bezier" | "smooth" | "step" | "straight";

export interface Rules {
  loops: boolean;
  duplicates: boolean;
  cycles: boolean;
}

export interface Config {
  rules: Rules;
  grid: number;
  snap: boolean;
  minimap: boolean;
  controls: boolean;
  fit: boolean;
  minZoom: number;
  maxZoom: number;
  readonly: boolean;
  /** Whether a shared canvas takes part in following, the room's (false: it follows no one, and shows no one followed). */
  follow?: boolean;
  newNode: boolean;
  wheel: "pan" | "zoom" | "scroll";
  refit: boolean;
  layout: "right" | "down";
  exportable: boolean;
  live: boolean;
  user: string | null;
  messages: Record<string, string>;
  locale: string;
}

/** The view: the place of the canvas's origin on the screen, and its zoom. */
export interface View {
  x: number;
  y: number;
  zoom: number;
}

export interface Rect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface Point {
  x: number;
  y: number;
}

export interface Handle {
  /** The handle's id in its node, or null for a handle without one. */
  id: string | null;
  kind: HandleKind;
  side: Side;
  type: string | null;
  accepts: string[] | null;
  max: number | null;
  /** The handle's middle, from the node's top left corner, at 100%. */
  x: number;
  y: number;
  el: HTMLElement;
}

export interface NodeModel {
  id: string;
  type: string;
  x: number;
  y: number;
  width: number;
  height: number;
  /** A size the server gave (a resized node), or null for its content's. */
  fixed: boolean;
  locked: boolean;
  resizable: boolean;
  /** The group it is in, or null. */
  parent: string | null;
  /** Whether it holds other nodes (a `group` slot). */
  group: boolean;
  label: string;
  handles: Handle[];
  /** Whether its handles were measured since its element last changed. */
  measured: boolean;
  el: HTMLElement;
}

export interface EdgeModel {
  id: string;
  source: string;
  sourceHandle: string | null;
  target: string;
  targetHandle: string | null;
  path: PathKind;
  label: string | null;
  marker: "arrow" | "dot" | "none";
  animated: boolean;
}

/** An end of an edge: a node, and a handle of it. */
export interface End {
  node: string;
  handle: string | null;
}

export interface Person {
  id: string;
  name: string | null;
  color: string;
  avatar: string | null;
}

/** What the browser asks of the server. */
export interface Live {
  push(event: string, payload: object, onReply?: (reply: Record<string, unknown>) => void): void;
}
