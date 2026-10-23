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
  /** The paper's pattern (the canvas's `data-background`). */
  background?: string;
  snap: boolean;
  minimap: boolean;
  controls: boolean;
  /** How it opens: on all its nodes, on none (false), or on all of them unless too small to read, then on its most joined node ("readable"). */
  fit: boolean | "readable";
  minZoom: number;
  maxZoom: number;
  readonly: boolean;
  /** With `readonly`: people still move the nodes and tidy them up, and undo that (the canvas's `readonly={:arrange}`). */
  arrange?: boolean;
  /** Whether a shared canvas takes part in following, the room's (false: it follows no one, and shows no one followed). */
  follow?: boolean;
  newNode: boolean;
  wheel: "pan" | "zoom" | "scroll";
  refit: boolean;
  /** The way of the layers of a tidy up. */
  layout: "right" | "down";
  /** Whether the canvas lays its nodes out as it opens, before they show (the canvas's `tidy`). */
  tidy?: boolean;
  /** How a tidy up places the nodes: in layers, by forces, or in a grid. */
  algorithm?: "layered" | "force" | "grid";
  exportable: boolean;
  live: boolean;
  user: string | null;
  /** The tools of the kits, for the bar of tools (Hakushi.Kit's `tools/1`). */
  tools?: Tool[];
  /** The style panels of the kits (Hakushi.Kit's `styles/1`), each for the node types of its kit. */
  styles?: { kit: string; types: string[]; groups: StyleGroup[] }[];
  /** The files the canvas takes (a kit's upload, Hakushi.Kit's `upload/0`): their extensions, and whether an address pasted is one. */
  files?: { kit: string; accept: string[]; urls: boolean } | null;
  /** The papers people choose from (the canvas's `papers`), and the sizes of their squares. */
  papers?: { name: string; label: string }[];
  paperGrids?: number[];
  messages: Record<string, string>;
  locale: string;
}

/**
 * A group of a kit's style panel: choices of a key of the nodes' data
 * (`color`, `width`, `choice`), a field for a text (`text`), or a button
 * that starts something of the canvas's own (`action`, by its key: `crop`).
 */
export interface StyleGroup {
  key: string;
  label: string;
  kind: "color" | "width" | "choice" | "text" | "action";
  options: { value: unknown; label: string }[];
  placeholder?: string;
  icon?: string;
}

/** A tool of a kit: what the pointer does on the canvas while it is chosen. */
export interface Tool {
  kit: string;
  tool: string;
  /** `pick` opens a file picker, and is never the tool chosen. */
  mode: "draw" | "erase" | "lasso" | "box" | "line" | "pick";
  label: string;
  icon: string;
  key: string | null;
  /** A drawing tool's colours and widths, and the ones it starts with. */
  colors?: string[];
  color?: string;
  sizes?: number[];
  size?: number;
  /** One width, whatever the pressure (a highlighter). */
  flat?: boolean;
  /** The node types an eraser takes. */
  types?: string[];
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
  /** Whether it is drawn faint, and its edges too: its content has `data-hakushi-faint` (a table of another schema). */
  faint: boolean;
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
