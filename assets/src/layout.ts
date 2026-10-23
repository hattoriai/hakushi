// Automatic layout: pure functions that give each node a place.
//
// `layered` lays the nodes out in layers along the edges (left to right, or
// top to bottom), as workflows, schemas and trees read:
//
// 1. Cycles are broken by turning back the edges that close them.
// 2. Each node goes in the layer after its furthest predecessor.
// 3. The nodes of each layer are ordered by the places of their
//    neighbours (barycentres), down and up again, to cross fewer edges.
// 4. Each node goes level with its neighbours where it can, without
//    overlapping the others of its layer.
//
// `force` lets the edges pull their nodes together and every node push the
// others away, as a network or a schema with a few central tables reads,
// then moves the nodes apart where they overlap.
//
// `grid` puts the nodes in rows and columns, in their order.
//
// The parts of a graph that no edge joins are laid out apart, then packed
// in rows (the largest first) to fill a box of about the `aspect` of the
// screen; the nodes that no edge joins go together in a grid.

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

export type Algorithm = "layered" | "force" | "grid";

export const algorithms: Algorithm[] = ["layered", "force", "grid"];

export interface LayoutOptions {
  /** How the nodes are placed: in layers, by forces, or in a grid. */
  algorithm: Algorithm;
  /** For `layered`, "right": layers from left to right; "down": from top to bottom. */
  direction: "right" | "down";
  /** The space between two nodes. */
  gap: number;
  /** The space between two layers (and, halved, between two parts). */
  layerGap: number;
  /** The width over the height of the box the parts are packed in: the screen's. */
  aspect: number;
}

export const defaults: LayoutOptions = { algorithm: "layered", direction: "right", gap: 32, layerGap: 96, aspect: 1.6 };

/**
 * The places (top left corners) of the nodes, from (0, 0), by the
 * algorithm of the options. Edges to nodes not in `nodes`, and an edge from
 * a node to itself, are left out.
 */
export function layout(nodes: LayoutNode[], edges: LayoutEdge[], options: Partial<LayoutOptions> = {}): Map<string, Point> {
  const algorithm = options.algorithm ?? defaults.algorithm;
  if (algorithm === "force") return force(nodes, edges, options);
  if (algorithm === "grid") return grid(nodes, options);
  return layered(nodes, edges, options);
}

/** The nodes in layers along the edges; the parts that no edge joins packed apart. */
export function layered(nodes: LayoutNode[], edges: LayoutEdge[], options: Partial<LayoutOptions> = {}): Map<string, Point> {
  const opts = { ...defaults, ...options };
  return byParts(nodes, edges, opts, (part, links) => layoutPart(part, links, opts));
}

/** The nodes placed by forces: the edges pull, the nodes push; then no two overlap. */
export function force(nodes: LayoutNode[], edges: LayoutEdge[], options: Partial<LayoutOptions> = {}): Map<string, Point> {
  const opts = { ...defaults, ...options };
  return byParts(nodes, edges, opts, (part, links) => forcePart(part, links, opts));
}

/** The nodes in rows and columns, in their order, each column as wide as its widest node. */
export function grid(nodes: LayoutNode[], options: Partial<LayoutOptions> = {}): Map<string, Point> {
  const opts = { ...defaults, ...options };
  const places = new Map<string, Point>();
  if (!nodes.length) return places;
  // The number of columns whose box is nearest the aspect asked for,
  // around that of the mean node.
  const meanW = nodes.reduce((sum, n) => sum + n.width, 0) / nodes.length + opts.gap;
  const meanH = nodes.reduce((sum, n) => sum + n.height, 0) / nodes.length + opts.gap;
  const guess = Math.sqrt((nodes.length * opts.aspect * meanH) / meanW);
  let best: { widths: number[]; heights: number[]; off: number } | null = null;
  for (let columns = Math.max(1, Math.floor(guess / 2)); columns <= Math.min(nodes.length, Math.ceil(guess * 2)); columns++) {
    const widths: number[] = Array(columns).fill(0);
    const heights: number[] = Array(Math.ceil(nodes.length / columns)).fill(0);
    nodes.forEach((n, i) => {
      widths[i % columns] = Math.max(widths[i % columns], n.width);
      heights[Math.floor(i / columns)] = Math.max(heights[Math.floor(i / columns)], n.height);
    });
    const w = widths.reduce((sum, x) => sum + x + opts.gap, 0);
    const h = heights.reduce((sum, x) => sum + x + opts.gap, 0);
    const off = Math.abs(Math.log(w / h / opts.aspect));
    if (!best || off < best.off) best = { widths, heights, off };
  }
  const { widths, heights } = best!;
  const columns = widths.length;
  const xs = starts(widths, opts.gap);
  const ys = starts(heights, opts.gap);
  nodes.forEach((n, i) => places.set(n.id, { x: xs[i % columns], y: ys[Math.floor(i / columns)] }));
  return places;
}

// Where each of a row of sizes starts, with a gap between them.
function starts(sizes: number[], gap: number): number[] {
  let at = 0;
  return sizes.map((size) => {
    const start = at;
    at += size + gap;
    return start;
  });
}

// Each part that edges join laid out by `place`, the nodes that no edge
// joins in a grid, and all of them packed.
function byParts(
  nodes: LayoutNode[],
  edges: LayoutEdge[],
  opts: LayoutOptions,
  place: (part: LayoutNode[], links: LayoutEdge[]) => Map<string, Point>,
): Map<string, Point> {
  const ids = new Set(nodes.map((n) => n.id));
  const links = edges.filter((e) => e.source !== e.target && ids.has(e.source) && ids.has(e.target));
  const joined = new Set(links.flatMap((e) => [e.source, e.target]));
  const blocks: Block[] = [];
  for (const part of components(nodes.filter((n) => joined.has(n.id)), links)) {
    const partIds = new Set(part.map((n) => n.id));
    blocks.push(block(part, place(part, links.filter((e) => partIds.has(e.source)))));
  }
  const loose = nodes.filter((n) => !joined.has(n.id));
  if (loose.length) blocks.push(block(loose, grid(loose, opts)));
  return pack(blocks, opts.layerGap / 2, opts.aspect);
}

interface Block {
  places: Map<string, Point>;
  width: number;
  height: number;
}

// The places of a part, from (0, 0), and the size of its box.
function block(nodes: LayoutNode[], places: Map<string, Point>): Block {
  let minX = Infinity;
  let minY = Infinity;
  let maxX = -Infinity;
  let maxY = -Infinity;
  for (const n of nodes) {
    const p = places.get(n.id)!;
    minX = Math.min(minX, p.x);
    minY = Math.min(minY, p.y);
    maxX = Math.max(maxX, p.x + n.width);
    maxY = Math.max(maxY, p.y + n.height);
  }
  const moved = new Map<string, Point>();
  for (const n of nodes) {
    const p = places.get(n.id)!;
    moved.set(n.id, { x: p.x - minX, y: p.y - minY });
  }
  return { places: moved, width: maxX - minX, height: maxY - minY };
}

/**
 * Boxes in rows, the tallest first, each row no wider than a box of about
 * `aspect` (width over height) that holds them all would be, nor narrower
 * than the widest box.
 */
export function pack(blocks: Block[], gap: number, aspect: number): Map<string, Point> {
  const places = new Map<string, Point>();
  if (!blocks.length) return places;
  const area = blocks.reduce((sum, b) => sum + (b.width + gap) * (b.height + gap), 0);
  const widest = Math.max(...blocks.map((b) => b.width));
  const rowWidth = Math.max(widest, Math.sqrt(area * aspect));
  const order = blocks.map((b, i) => ({ b, i })).sort((p, q) => q.b.height - p.b.height || p.i - q.i);
  let x = 0;
  let y = 0;
  let rowHeight = 0;
  for (const { b } of order) {
    if (x > 0 && x + b.width > rowWidth) {
      x = 0;
      y += rowHeight + gap;
      rowHeight = 0;
    }
    for (const [id, p] of b.places) places.set(id, { x: p.x + x, y: p.y + y });
    x += b.width + gap;
    rowHeight = Math.max(rowHeight, b.height);
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

  // A part much longer across its layers than a box of the aspect asked
  // for (a table that hundreds of others refer to: one layer of hundreds)
  // has its long layers wrapped, in their order, in columns side by side.
  const tight = wrap(layerList, nodes, across, along, opts);

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
  for (const [i, layer] of layerList.entries()) {
    if (tight.has(i)) layerAt -= opts.layerGap / 2;
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

// Wraps the layers too long across, in place, and gives the indexes of the
// layers that go on from the one before (with half a gap between them).
function wrap(layerList: string[][], nodes: LayoutNode[], across: (id: string) => number, along: (id: string) => number, opts: LayoutOptions): Set<number> {
  const tight = new Set<number>();
  const length = (layer: string[]) => layer.reduce((sum, id) => sum + across(id) + opts.gap, 0);
  const longest = Math.max(...layerList.map(length));
  const depth = layerList.reduce((sum, layer) => sum + Math.max(0, ...layer.map(along)) + opts.layerGap, 0);
  // The box's width over its height, and the one asked for, the same way.
  const shape = opts.direction === "right" ? depth / longest : longest / depth;
  if (shape >= opts.aspect / 2.5) return tight;

  const area = nodes.reduce((sum, n) => sum + (n.width + opts.gap) * (n.height + opts.gap), 0);
  const limit = Math.max(opts.direction === "right" ? Math.sqrt(area / opts.aspect) : Math.sqrt(area * opts.aspect), ...nodes.map((n) => across(n.id) + opts.gap));
  const wrapped: string[][] = [];
  for (const layer of layerList) {
    let column: string[] = [];
    let at = 0;
    for (const id of layer) {
      if (column.length && at + across(id) > limit) {
        wrapped.push(column);
        tight.add(wrapped.length);
        column = [];
        at = 0;
      }
      column.push(id);
      at += across(id) + opts.gap;
    }
    wrapped.push(column);
  }
  layerList.splice(0, layerList.length, ...wrapped);
  return tight;
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

// -- Forces -----------------------------------------------------------------
//
// Fruchterman and Reingold's forces between the middles of the nodes: each
// edge pulls its two nodes together, and each node pushes every other away,
// by its size (a large table pushes harder). The pushes are summed with a
// quadtree (Barnes and Hut), so that a step costs n log n and not n², and
// the steps shorten as the layout cools. The nodes start on a spiral, in
// the order of a walk from the most joined one, so neighbours start near
// each other and the same graph is laid out the same way each time.

interface Body {
  x: number;
  y: number;
  dx: number;
  dy: number;
  /** How hard it pushes: its half diagonal, and half a gap. */
  mass: number;
}

function forcePart(nodes: LayoutNode[], edges: LayoutEdge[], opts: LayoutOptions): Map<string, Point> {
  const n = nodes.length;
  const index = new Map(nodes.map((node, i) => [node.id, i]));
  const bodies: Body[] = nodes.map((node) => ({ x: 0, y: 0, dx: 0, dy: 0, mass: Math.hypot(node.width, node.height) / 2 + opts.gap / 2 }));
  const links = edges.map((e) => [index.get(e.source)!, index.get(e.target)!] as const);
  const meanMass = bodies.reduce((sum, b) => sum + b.mass, 0) / n;

  const spacing = meanMass * 2 + opts.gap;
  walk(nodes, links).forEach((i, k) => {
    const angle = k * 2.399963; // the golden angle
    const radius = spacing * 0.6 * Math.sqrt(k);
    bodies[i].x = Math.cos(angle) * radius;
    bodies[i].y = Math.sin(angle) * radius;
  });

  const steps = n <= 200 ? 300 : n <= 1_000 ? 200 : 120;
  let heat = spacing * Math.max(2, Math.sqrt(n) / 2);
  const cool = Math.pow(0.02 * spacing / heat, 1 / steps);
  for (let step = 0; step < steps; step++) {
    for (const b of bodies) b.dx = b.dy = 0;
    const tree = quadtree(bodies);
    for (const b of bodies) push(tree, b);
    for (const [s, t] of links) {
      const a = bodies[s];
      const b = bodies[t];
      const dx = a.x - b.x;
      const dy = a.y - b.y;
      const d = Math.hypot(dx, dy) || 0.01;
      // Pulls to a length that their two sizes leave between them.
      const rest = a.mass + b.mass;
      const f = (d * d) / rest / d;
      a.dx -= dx * f;
      a.dy -= dy * f;
      b.dx += dx * f;
      b.dy += dy * f;
    }
    for (const b of bodies) {
      // Some gravity, so that the part stays round and close.
      b.dx -= b.x * 0.1;
      b.dy -= b.y * 0.1;
      const d = Math.hypot(b.dx, b.dy);
      if (d > 0) {
        const move = Math.min(d, heat);
        b.x += (b.dx / d) * move;
        b.y += (b.dy / d) * move;
      }
    }
    heat *= cool;
  }

  // Room for the nodes: the middles spread out until the nodes would fill
  // no more than a third of their box; then no two overlap.
  let minX = Infinity;
  let minY = Infinity;
  let maxX = -Infinity;
  let maxY = -Infinity;
  nodes.forEach((node, i) => {
    minX = Math.min(minX, bodies[i].x - node.width / 2);
    minY = Math.min(minY, bodies[i].y - node.height / 2);
    maxX = Math.max(maxX, bodies[i].x + node.width / 2);
    maxY = Math.max(maxY, bodies[i].y + node.height / 2);
  });
  const area = nodes.reduce((sum, node) => sum + (node.width + opts.gap) * (node.height + opts.gap), 0);
  const scale = Math.max(1, Math.sqrt(area / 0.33 / Math.max(1, (maxX - minX) * (maxY - minY))));
  const boxes = nodes.map((node, i) => ({ x: bodies[i].x * scale - node.width / 2, y: bodies[i].y * scale - node.height / 2, width: node.width, height: node.height }));
  separate(boxes, opts.gap);
  return new Map(nodes.map((node, i) => [node.id, { x: boxes[i].x, y: boxes[i].y }]));
}

// The nodes in the order of a walk (breadth first) from the most joined.
function walk(nodes: LayoutNode[], links: (readonly [number, number])[]): number[] {
  const near: number[][] = nodes.map(() => []);
  for (const [s, t] of links) {
    near[s].push(t);
    near[t].push(s);
  }
  const seen = new Uint8Array(nodes.length);
  const order: number[] = [];
  const starts = nodes.map((_, i) => i).sort((a, b) => near[b].length - near[a].length || a - b);
  for (const start of starts) {
    if (seen[start]) continue;
    seen[start] = 1;
    const queue = [start];
    for (let q = 0; q < queue.length; q++) {
      const i = queue[q];
      order.push(i);
      for (const j of near[i])
        if (!seen[j]) {
          seen[j] = 1;
          queue.push(j);
        }
    }
  }
  return order;
}

interface Cell {
  x: number;
  y: number;
  size: number;
  mass: number;
  cx: number;
  cy: number;
  body: Body | null;
  kids: Cell[] | null;
}

function quadtree(bodies: Body[]): Cell {
  let minX = Infinity;
  let minY = Infinity;
  let maxX = -Infinity;
  let maxY = -Infinity;
  for (const b of bodies) {
    minX = Math.min(minX, b.x);
    minY = Math.min(minY, b.y);
    maxX = Math.max(maxX, b.x);
    maxY = Math.max(maxY, b.y);
  }
  const root = cell(minX, minY, Math.max(maxX - minX, maxY - minY, 1) + 1);
  for (const b of bodies) insert(root, b, 0);
  return root;
}

function cell(x: number, y: number, size: number): Cell {
  return { x, y, size, mass: 0, cx: 0, cy: 0, body: null, kids: null };
}

function insert(c: Cell, b: Body, depth: number) {
  // The middle of its mass, as the bodies come in.
  c.cx = (c.cx * c.mass + b.x * b.mass) / (c.mass + b.mass);
  c.cy = (c.cy * c.mass + b.y * b.mass) / (c.mass + b.mass);
  c.mass += b.mass;
  if (!c.kids && !c.body) {
    c.body = b;
    return;
  }
  // Two bodies at one place (or a tree too deep): they share the cell.
  if (depth > 40) return;
  if (!c.kids) {
    const half = c.size / 2;
    c.kids = [cell(c.x, c.y, half), cell(c.x + half, c.y, half), cell(c.x, c.y + half, half), cell(c.x + half, c.y + half, half)];
    const old = c.body!;
    c.body = null;
    insert(quarter(c, old), old, depth + 1);
  }
  insert(quarter(c, b), b, depth + 1);
}

function quarter(c: Cell, b: Body): Cell {
  const half = c.size / 2;
  return c.kids![(b.x >= c.x + half ? 1 : 0) + (b.y >= c.y + half ? 2 : 0)];
}

// The push of the bodies of a cell on one body: a far cell as one body at
// the middle of its mass.
function push(c: Cell, b: Body) {
  if (c.mass === 0 || c.body === b) return;
  const dx = b.x - c.cx;
  const dy = b.y - c.cy;
  const d2 = dx * dx + dy * dy;
  if (c.kids && c.size * c.size > 0.64 * d2) {
    for (const kid of c.kids) push(kid, b);
    return;
  }
  if (d2 === 0) {
    // At the same place: apart by a nudge of its own.
    b.dx += b.mass * 0.01;
    return;
  }
  // k² / d, with k² the two sizes multiplied, and a quarter of it.
  const f = (b.mass * c.mass) / 4 / d2;
  b.dx += dx * f;
  b.dy += dy * f;
}

interface Box {
  x: number;
  y: number;
  width: number;
  height: number;
}

/**
 * Moves overlapping boxes apart until no two are nearer than `gap`: first
 * each pair half each, the shorter way, for a few rounds (pairs found in a
 * grid of buckets, so a round costs about n), which moves them least; then
 * what still overlaps in one sweep from left to right, each box right of
 * those before it that it would overlap.
 */
export function separate(boxes: Box[], gap: number) {
  if (boxes.length < 2) return;
  const size = Math.max(...boxes.map((b) => Math.max(b.width, b.height))) + gap;
  for (let round = 0; round < 50; round++) {
    const buckets = new Map<string, number[]>();
    boxes.forEach((b, i) => {
      for (let gx = Math.floor(b.x / size); gx <= Math.floor((b.x + b.width + gap) / size); gx++)
        for (let gy = Math.floor(b.y / size); gy <= Math.floor((b.y + b.height + gap) / size); gy++) {
          const key = `${gx},${gy}`;
          const list = buckets.get(key);
          if (list) list.push(i);
          else buckets.set(key, [i]);
        }
    });
    let moved = false;
    const done = new Set<number>();
    for (const list of buckets.values()) {
      for (let p = 0; p < list.length; p++)
        for (let q = p + 1; q < list.length; q++) {
          const i = Math.min(list[p], list[q]);
          const j = Math.max(list[p], list[q]);
          const key = i * boxes.length + j;
          if (done.has(key)) continue;
          done.add(key);
          const a = boxes[i];
          const b = boxes[j];
          const ox = Math.min(a.x + a.width + gap - b.x, b.x + b.width + gap - a.x);
          const oy = Math.min(a.y + a.height + gap - b.y, b.y + b.height + gap - a.y);
          if (ox <= 0 || oy <= 0) continue;
          moved = true;
          // Half each, the shorter way; the one nearer the start goes back.
          if (ox < oy) {
            const s = a.x + a.width / 2 < b.x + b.width / 2 || (a.x + a.width / 2 === b.x + b.width / 2 && i < j) ? 1 : -1;
            a.x -= (s * ox) / 2;
            b.x += (s * ox) / 2;
          } else {
            const s = a.y + a.height / 2 < b.y + b.height / 2 || (a.y + a.height / 2 === b.y + b.height / 2 && i < j) ? 1 : -1;
            a.y -= (s * oy) / 2;
            b.y += (s * oy) / 2;
          }
        }
    }
    if (!moved) return;
  }
  sweep(boxes, gap);
}

// Each box, from left to right, as far left as it was and right of every
// box placed before it that it would overlap: none overlap after. The boxes
// placed are kept in bands of their height, to find those it may overlap.
function sweep(boxes: Box[], gap: number) {
  const band = Math.max(...boxes.map((b) => b.height)) + gap;
  const bands = new Map<number, Box[]>();
  const order = [...boxes].sort((a, b) => a.x - b.x || a.y - b.y);
  for (const b of order) {
    let x = b.x;
    const first = Math.floor(b.y / band) - 1;
    const last = Math.floor((b.y + b.height + gap) / band);
    for (let k = first; k <= last; k++)
      for (const p of bands.get(k) ?? []) if (p.y < b.y + b.height + gap && b.y < p.y + p.height + gap) x = Math.max(x, p.x + p.width + gap);
    b.x = x;
    for (let k = Math.floor(b.y / band); k <= Math.floor((b.y + b.height) / band); k++) {
      const list = bands.get(k);
      if (list) list.push(b);
      else bands.set(k, [b]);
    }
  }
}
