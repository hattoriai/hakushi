// Layout engines of the app's (registerLayout): a layout that the canvas
// does not have itself, such as ELK (`hakushi/elk`). An engine gets the
// nodes, with the groups they are in, and the edges, and gives back a place
// for each node, a size for each group with nodes in it, and, if it routes
// them, the points of each edge.
//
// The canvas calls an engine for a tidy up when its `layout` (or the way
// the person chose) names it; an engine that throws leaves the canvas's own
// layered layout to do the work.

import type { Point, Side } from "./types";

/** A node, as an engine gets it: its size, and the group it is in. */
export interface EngineNode {
  id: string;
  width: number;
  height: number;
  /** The group it is in, among the nodes laid out; `null` at the top. */
  parent: string | null;
  /** Whether nodes are in it: the engine gives it a size around them. */
  group: boolean;
  /** For a group: the space between its sides and the nodes in it (its title is in the top one). */
  padding: { top: number; right: number; bottom: number; left: number };
  /** The handles its edges meet, at their places in it. */
  ports: { id: string; x: number; y: number; side: Side }[];
}

/** An edge, as an engine gets it: its ends, and the size of its label. */
export interface EngineEdge {
  id: string;
  source: string;
  target: string;
  /** The port of the source (an `EngineNode`'s), or `null` for a side of the engine's choice. */
  sourcePort: string | null;
  targetPort: string | null;
  label: { width: number; height: number } | null;
}

export interface EngineInput {
  nodes: EngineNode[];
  edges: EngineEdge[];
  /** The way the edges go: from left to right, or from top to bottom. */
  direction: "right" | "down";
}

/** Where an engine puts each node (its top left corner), and the way of each edge. */
export interface EngineResult {
  nodes: Record<string, { x: number; y: number; width?: number; height?: number }>;
  /** The points an edge goes through, its ends too, and the middle of its label: when the engine routes edges. */
  edges?: Record<string, { points: Point[]; label?: Point | null }>;
}

export type LayoutEngine = (input: EngineInput) => EngineResult | Promise<EngineResult>;

const engines = new Map<string, LayoutEngine>();

/**
 * Registers a layout engine under a name, which a canvas's `layout` names
 * (`layout={:elk}`), as `Hakushi.Live.layout/2` does:
 *
 *     import { registerLayout } from "hakushi"
 *     import { elk } from "hakushi/elk"
 *     registerLayout("elk", elk())
 */
export function registerLayout(name: string, engine: LayoutEngine): void {
  if (!/^[a-z][a-z0-9-]{0,31}$/.test(name)) throw new Error(`a layout's name is a-z, 0-9 and -, got: ${name}`);
  engines.set(name, engine);
}

export function engineOf(name: string | undefined | null): LayoutEngine | null {
  return (name && engines.get(name)) || null;
}

/** Forgets every engine (for the tests). */
export function resetLayouts(): void {
  engines.clear();
}
