// Automatic layout: the nodes in layers along the edges (left to right, or
// top to bottom), as workflows, schemas and trees read. Pure functions.
//
// 1. Cycles are broken by turning back the edges that close them.
// 2. Each node goes in the layer after its furthest predecessor.
// 3. The nodes of each layer are ordered by the places of their
//    neighbours (barycentres), down and up again, to cross fewer edges.
// 4. Each node goes level with its neighbours where it can, without
//    overlapping the others of its layer.
// The parts of a graph that no edge joins are laid out apart, side by side.

import type { Point } from "./types";

export interface LayoutNode {
  id: string;
  width: number;
  height: number;
}

export interface LayoutEdge {
  source: string;
  target: string;
}

export interface LayoutOptions {
  /** "right": layers from left to right; "down": from top to bottom. */
  direction: "right" | "down";
  /** The space between two nodes of a layer. */
  gap: number;
  /** The space between two layers. */
  layerGap: number;
}

export const defaults: LayoutOptions = { direction: "right", gap: 32, layerGap: 96 };

/**
 * The places (top left corners) of the nodes, from (0, 0). Edges to nodes
 * not in `nodes`, and an edge from a node to itself, are left out.
 */
export function layered(nodes: LayoutNode[], edges: LayoutEdge[], options: Partial<LayoutOptions> = {}): Map<string, Point> {
  const opts = { ...defaults, ...options };
  const ids = new Set(nodes.map((n) => n.id));
  const links = edges.filter((e) => e.source !== e.target && ids.has(e.source) && ids.has(e.target));
  const places = new Map<string, Point>();
  let offset = 0;

  for (const part of components(nodes, links)) {
    const partIds = new Set(part.map((n) => n.id));
    const partLinks = links.filter((e) => partIds.has(e.source));
    const placed = layoutPart(part, partLinks, opts);
    // Side by side across the layers: one part after the other.
    let extent = 0;
    for (const node of part) {
      const p = placed.get(node.id)!;
      const at = opts.direction === "right" ? { x: p.x, y: p.y + offset } : { x: p.x + offset, y: p.y };
      places.set(node.id, at);
      extent = Math.max(extent, opts.direction === "right" ? p.y + node.height : p.x + node.width);
    }
    offset += extent + opts.layerGap / 2;
  }
  return places;
}

// The parts of the graph that edges join, each in the order of `nodes`.
export function components(nodes: LayoutNode[], edges: LayoutEdge[]): LayoutNode[][] {
  const root = new Map(nodes.map((n) => [n.id, n.id]));
  const find = (id: string): string => {
    let r = id;
    while (root.get(r) !== r) r = root.get(r)!;
    let c = id;
    while (root.get(c) !== r) {
      const next = root.get(c)!;
      root.set(c, r);
      c = next;
    }
    return r;
  };
  for (const e of edges) root.set(find(e.source), find(e.target));
  const parts = new Map<string, LayoutNode[]>();
  for (const n of nodes) {
    const r = find(n.id);
    const list = parts.get(r);
    if (list) list.push(n);
    else parts.set(r, [n]);
  }
  return [...parts.values()];
}

function layoutPart(nodes: LayoutNode[], edges: LayoutEdge[], opts: LayoutOptions): Map<string, Point> {
  const byId = new Map(nodes.map((n) => [n.id, n]));
  const acyclic = breakCycles(nodes, edges);
  const layerOf = layers(nodes, acyclic);
  const count = Math.max(0, ...layerOf.values()) + 1;
  const layerList: string[][] = Array.from({ length: count }, () => []);
  for (const n of nodes) layerList[layerOf.get(n.id)!].push(n.id);

  const preds = new Map<string, string[]>(nodes.map((n) => [n.id, []]));
  const succs = new Map<string, string[]>(nodes.map((n) => [n.id, []]));
  for (const e of acyclic) {
    preds.get(e.target)!.push(e.source);
    succs.get(e.source)!.push(e.target);
  }

  order(layerList, preds, succs);

  // Across a layer: each node's size across, and along: the layer's depth.
  const across = (id: string) => (opts.direction === "right" ? byId.get(id)!.height : byId.get(id)!.width);
  const along = (id: string) => (opts.direction === "right" ? byId.get(id)!.width : byId.get(id)!.height);

  const pos = new Map<string, number>(); // the middle of each node, across
  for (const layer of layerList) {
    let at = 0;
    for (const id of layer) {
      pos.set(id, at + across(id) / 2);
      at += across(id) + opts.gap;
    }
  }
  // Level with the neighbours: down the layers by predecessors, then up by successors.
  for (let pass = 0; pass < 4; pass++) {
    const down = pass % 2 === 0;
    const indexes = down ? layerList.map((_, i) => i) : layerList.map((_, i) => layerList.length - 1 - i);
    for (const i of indexes) align(layerList[i], down ? preds : succs, pos, across, opts.gap);
  }

  let min = Infinity;
  for (const [id, p] of pos) min = Math.min(min, p - across(id) / 2);

  const places = new Map<string, Point>();
  let layerAt = 0;
  for (const layer of layerList) {
    const depth = Math.max(0, ...layer.map(along));
    for (const id of layer) {
      const a = pos.get(id)! - across(id) / 2 - min;
      // In its layer, a node is centred on the layer's depth.
      const l = layerAt + (depth - along(id)) / 2;
      places.set(id, opts.direction === "right" ? { x: l, y: a } : { x: a, y: l });
    }
    layerAt += depth + opts.layerGap;
  }
  return places;
}

/** The edges with those that close a cycle turned back (by a depth-first walk in the nodes' order). */
export function breakCycles(nodes: LayoutNode[], edges: LayoutEdge[]): LayoutEdge[] {
  const out = new Map<string, LayoutEdge[]>(nodes.map((n) => [n.id, []]));
  for (const e of edges) out.get(e.source)!.push(e);
  const state = new Map<string, 0 | 1 | 2>(); // 1: on the path, 2: done
  const back = new Set<LayoutEdge>();
  for (const n of nodes) {
    if (state.get(n.id)) continue;
    const stack: [string, number][] = [[n.id, 0]];
    state.set(n.id, 1);
    while (stack.length) {
      const top = stack[stack.length - 1];
      const list = out.get(top[0])!;
      if (top[1] >= list.length) {
        state.set(top[0], 2);
        stack.pop();
        continue;
      }
      const e = list[top[1]++];
      const s = state.get(e.target) ?? 0;
      if (s === 1) back.add(e);
      else if (s === 0) {
        state.set(e.target, 1);
        stack.push([e.target, 0]);
      }
    }
  }
  return edges.map((e) => (back.has(e) ? { source: e.target, target: e.source } : e));
}

/** Each node's layer: one after its furthest predecessor (the edges have no cycle). */
export function layers(nodes: LayoutNode[], edges: LayoutEdge[]): Map<string, number> {
  const indegree = new Map(nodes.map((n) => [n.id, 0]));
  const out = new Map<string, string[]>(nodes.map((n) => [n.id, []]));
  for (const e of edges) {
    indegree.set(e.target, indegree.get(e.target)! + 1);
    out.get(e.source)!.push(e.target);
  }
  const layer = new Map(nodes.map((n) => [n.id, 0]));
  const queue = nodes.filter((n) => indegree.get(n.id) === 0).map((n) => n.id);
  while (queue.length) {
    const id = queue.shift()!;
    for (const next of out.get(id)!) {
      layer.set(next, Math.max(layer.get(next)!, layer.get(id)! + 1));
      indegree.set(next, indegree.get(next)! - 1);
      if (indegree.get(next) === 0) queue.push(next);
    }
  }
  return layer;
}

// The nodes of each layer ordered by the mean place of their neighbours in
// the layer before (going down) or after (going up), a few times over.
function order(layerList: string[][], preds: Map<string, string[]>, succs: Map<string, string[]>) {
  const index = new Map<string, number>();
  const reindex = () => layerList.forEach((layer) => layer.forEach((id, i) => index.set(id, i)));
  reindex();
  let best = crossings(layerList, succs, index);
  let bestOrder = layerList.map((l) => [...l]);
  for (let sweep = 0; sweep < 8; sweep++) {
    const down = sweep % 2 === 0;
    const range = down ? layerList.map((_, i) => i).slice(1) : layerList.map((_, i) => layerList.length - 1 - i).slice(1);
    for (const i of range) {
      const neighbours = down ? preds : succs;
      const centre = new Map<string, number>();
      layerList[i].forEach((id, k) => {
        const list = neighbours.get(id)!.filter((n) => index.has(n));
        centre.set(id, list.length ? list.reduce((sum, n) => sum + index.get(n)!, 0) / list.length : k);
      });
      layerList[i].sort((a, b) => centre.get(a)! - centre.get(b)!);
      layerList[i].forEach((id, k) => index.set(id, k));
    }
    const c = crossings(layerList, succs, index);
    if (c < best) {
      best = c;
      bestOrder = layerList.map((l) => [...l]);
    }
  }
  bestOrder.forEach((layer, i) => (layerList[i] = layer));
  reindex();
}

/** How many pairs of edges cross between neighbouring layers. */
export function crossings(layerList: string[][], succs: Map<string, string[]>, index: Map<string, number>): number {
  let count = 0;
  const layerOf = new Map<string, number>();
  layerList.forEach((layer, i) => layer.forEach((id) => layerOf.set(id, i)));
  for (let i = 0; i < layerList.length - 1; i++) {
    const pairs: [number, number][] = [];
    for (const id of layerList[i]) for (const t of succs.get(id)!) if (layerOf.get(t) === i + 1) pairs.push([index.get(id)!, index.get(t)!]);
    for (let a = 0; a < pairs.length; a++)
      for (let b = a + 1; b < pairs.length; b++) if ((pairs[a][0] - pairs[b][0]) * (pairs[a][1] - pairs[b][1]) < 0) count++;
  }
  return count;
}

// Each node of a layer as near the mean of its neighbours' middles as it
// can be, in the layer's order, with `gap` between them.
function align(layer: string[], neighbours: Map<string, string[]>, pos: Map<string, number>, size: (id: string) => number, gap: number) {
  const want = layer.map((id) => {
    const list = neighbours.get(id)!;
    return list.length ? list.reduce((sum, n) => sum + pos.get(n)!, 0) / list.length : pos.get(id)!;
  });
  // Forward: no node above the one before it; backward: none below the one after it.
  const placed = [...want];
  for (let k = 1; k < layer.length; k++) {
    const min = placed[k - 1] + size(layer[k - 1]) / 2 + gap + size(layer[k]) / 2;
    if (placed[k] < min) placed[k] = min;
  }
  for (let k = layer.length - 2; k >= 0; k--) {
    const max = placed[k + 1] - size(layer[k + 1]) / 2 - gap - size(layer[k]) / 2;
    if (placed[k] > max) placed[k] = max;
  }
  layer.forEach((id, k) => pos.set(id, placed[k]));
}
