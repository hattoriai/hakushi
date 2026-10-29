// The shapes the canvas works with: its config (from the server's
// data-config), its view, its nodes, handles and edges, as the browser
// keeps them.

export type Side = "left" | "right" | "top" | "bottom";
export type HandleKind = "source" | "target" | "both";
export type PathKind = "bezier" | "smooth" | "step" | "straight" | "routed";

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
  /** Whether the app hears what the person selects (the canvas's `on_select`). */
  reportSelect?: boolean;
  /** Whether the app hears where the person's view comes to rest (the canvas's `on_viewport`). */
  reportView?: boolean;
  /** Whether a right click opens the canvas's menu (the canvas's `menu`, Hakushi.Menu), not the browser's. */
  menu?: boolean;
  /** Whether ⌘↑ goes up, out of the canvas (the canvas's `on_up`). */
  up?: boolean;
  /** The tools of the app's own (registerTool) the canvas offers: its `client_tools`. */
  clientTools?: string[];
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
  /** `pick` opens a file picker, and is never the tool chosen; `client` is the app's own (registerTool). */
  mode: "draw" | "erase" | "lasso" | "box" | "line" | "pick" | "client";
  /** The icon of a tool of the app's own: the markup of its SVG. */
  svg?: string;
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
  /** Whether people open it (a slot that `opens`): the canvas's `on_open`. */
  opens: boolean;
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
  /** The points it goes through, where people bent it (in the canvas's terms). */
  points: Point[];
  /** The app's mark of it (Hakushi.Live.mark_edges/3), and whether the spotlight is on it. */
  mark: EdgeMark;
}

/** What an edge is now, as the app marks it: not saved, not in the graph. */
export interface EdgeMark {
  status: string | null;
  highlight: boolean;
  color: string | null;
  dim: boolean;
  title: string | null;
  lit: boolean;
  /** What it is to an older graph, on a canvas that compares: added, removed or changed. */
  diff: string | null;
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
  /** An event to the canvas's LiveView itself, not its component. */
  pushView?(event: string, payload: object, onReply?: (reply: Record<string, unknown>) => void): void;
}

/**
 * An item of the canvas's menu (Hakushi.Menu): a line between items, an
 * action of the canvas's own (`action`), or the app's own (`id`), with an
 * icon (SVG), the words of its keys, and whether it deletes or is disabled.
 */
export interface MenuItem {
  separator?: boolean;
  action?: string;
  id?: string;
  label?: string;
  icon?: string | null;
  shortcut?: string | null;
  danger?: boolean;
  disabled?: boolean;
}

/** A node as the app's code reads it (Canvas.getNodes). */
export interface NodeInfo {
  id: string;
  type: string;
  x: number;
  y: number;
  width: number;
  height: number;
  parent: string | null;
  locked: boolean;
  selected: boolean;
}

/** An edge as the app's code reads it (Canvas.getEdges). */
export interface EdgeInfo {
  id: string;
  source: string;
  sourceHandle: string | null;
  target: string;
  targetHandle: string | null;
  label: string | null;
  selected: boolean;
}

/** What the canvas tells the app's code (Canvas.on). */
export interface CanvasEvents {
  /** The selection changed. */
  select: { nodes: string[]; edges: string[] };
  /** The view moved: its place and zoom. */
  view: View;
  /** A change of the person's came back from the server: taken (`ok`), refused (`error`), or another in its place (`rewritten`). */
  change: { change: Record<string, unknown>; ok: boolean; error: string | null; rewritten: boolean };
  /** Another tool was chosen (`"ink:pen"`, `"app:ruler"`), or the pointer (null). */
  tool: string | null;
}
