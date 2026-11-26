// The ELK layout engine for Hakushi (`hakushi/elk`): a bundle of its own,
// apart from the canvas's, because ELK is large (about 1.4 MB, 450 KB
// gzipped). An app that wants it imports it and registers it:
//
//     import { registerLayout } from "hakushi"
//     import { elk } from "hakushi/elk"
//     registerLayout("elk", elk())
//
// ELK (the Eclipse Layout Kernel, https://eclipse.dev/elk/, EPL-2.0) lays
// out in layers what is in the groups and the groups together, gives each
// group a size around its nodes, and routes the edges along the axes, apart
// from each other, through the ports of their handles.

import ELK from "elkjs/lib/elk.bundled.js";
import type { ElkExtendedEdge, ElkNode, ElkPort, LayoutOptions } from "elkjs/lib/elk-api";
import type { EngineInput, EngineResult, LayoutEngine } from "./engines";
import type { Point, Side } from "./types";

export type { LayoutOptions };

/** The ELK options of every layout, which `elk(options)` adds to and replaces. */
export const defaults: LayoutOptions = {
  "elk.algorithm": "layered",
  "elk.hierarchyHandling": "INCLUDE_CHILDREN",
  "elk.edgeRouting": "ORTHOGONAL",
  "elk.layered.nodePlacement.strategy": "NETWORK_SIMPLEX",
  "elk.layered.crossingMinimization.strategy": "LAYER_SWEEP",
  "elk.layered.considerModelOrder.strategy": "NODES_AND_EDGES",
  "elk.spacing.nodeNode": "32",
  "elk.layered.spacing.nodeNodeBetweenLayers": "80",
  "elk.spacing.edgeNode": "20",
  "elk.spacing.edgeEdge": "12",
  "elk.layered.spacing.edgeNodeBetweenLayers": "24",
  "elk.layered.spacing.edgeEdgeBetweenLayers": "12",
  "elk.edgeLabels.placement": "CENTER",
};

const SIDES: Record<Side, string> = { top: "NORTH", right: "EAST", bottom: "SOUTH", left: "WEST" };

/**
 * A layout engine of ELK, for `registerLayout`. `options` are ELK's
 * (https://eclipse.dev/elk/reference/options.html), over `defaults`:
 *
 *     registerLayout("elk", elk({ "elk.spacing.nodeNode": "48" }))
 */
export function elk(options: LayoutOptions = {}): LayoutEngine {
  let engine: InstanceType<typeof ELK> | null = null;
  return async (input) => {
    engine ??= new ELK();
    return fromElk(await engine.layout(toElk(input, options)));
  };
}

/** The ELK graph of an engine's input: the groups with their nodes in them, and every edge at the top. */
export function toElk(input: EngineInput, options: LayoutOptions = {}): ElkNode {
  const byId = new Map<string, ElkNode>();
  for (const node of input.nodes) {
    const elkNode: ElkNode = { id: node.id, layoutOptions: {} };
    if (node.group) {
      const p = node.padding;
      elkNode.layoutOptions!["elk.padding"] = `[top=${p.top},left=${p.left},bottom=${p.bottom},right=${p.right}]`;
      elkNode.children = [];
    } else {
      elkNode.width = node.width;
      elkNode.height = node.height;
    }
    if (node.ports.length) {
      elkNode.layoutOptions!["elk.portConstraints"] = "FIXED_POS";
      elkNode.ports = node.ports.map(
        (port): ElkPort => ({ id: port.id, x: port.x, y: port.y, width: 0, height: 0, layoutOptions: { "elk.port.side": SIDES[port.side] } }),
      );
    }
    byId.set(node.id, elkNode);
  }
  const root: ElkNode = {
    id: "\u0000root",
    layoutOptions: { ...defaults, "elk.direction": input.direction === "down" ? "DOWN" : "RIGHT", ...options },
    children: [],
    edges: [],
  };
  for (const node of input.nodes) {
    const parent = node.parent ? byId.get(node.parent) : null;
    (parent?.children ?? root.children!).push(byId.get(node.id)!);
  }
  // A group with nothing in it (they all went): a box of its own size.
  for (const node of input.nodes) {
    const elkNode = byId.get(node.id)!;
    if (elkNode.children && !elkNode.children.length) {
      delete elkNode.children;
      elkNode.width = node.width;
      elkNode.height = node.height;
    }
  }
  const ancestors = (id: string) => {
    const all = new Set<string>();
    let at = input.nodes.find((n) => n.id === id)?.parent ?? null;
    while (at && !all.has(at)) {
      all.add(at);
      at = input.nodes.find((n) => n.id === at)?.parent ?? null;
    }
    return all;
  };
  for (const edge of input.edges) {
    // ELK does not lay out an edge from a group to a node in it.
    if (ancestors(edge.source).has(edge.target) || ancestors(edge.target).has(edge.source)) continue;
    const elkEdge: ElkExtendedEdge = {
      id: edge.id,
      sources: [edge.sourcePort ?? edge.source],
      targets: [edge.targetPort ?? edge.target],
    };
    if (edge.label) elkEdge.labels = [{ text: " ", width: edge.label.width, height: edge.label.height }];
    root.edges!.push(elkEdge);
  }
  return root;
}

/**
 * Every node and edge of ELK's result in the canvas's terms. ELK gives a
 * node's place in its parent and an edge's points in its `container`; this
 * adds those up once.
 */
export function fromElk(out: ElkNode): EngineResult {
  const result: Required<EngineResult> = { nodes: {}, edges: {} };
  const origin = new Map<string, Point>([[out.id, { x: 0, y: 0 }]]);
  const visit = (node: ElkNode, ox: number, oy: number) => {
    const x = ox + (node.x ?? 0);
    const y = oy + (node.y ?? 0);
    origin.set(node.id, { x, y });
    result.nodes[node.id] = { x, y, width: node.width ?? 0, height: node.height ?? 0 };
    node.children?.forEach((child) => visit(child, x, y));
  };
  out.children?.forEach((child) => visit(child, 0, 0));

  const collect = (node: ElkNode) => {
    for (const edge of (node.edges ?? []) as (ElkExtendedEdge & { container?: string })[]) {
      const o = origin.get(edge.container ?? node.id) ?? { x: 0, y: 0 };
      const section = edge.sections?.[0];
      if (!section) continue;
      const shift = (p: Point) => ({ x: p.x + o.x, y: p.y + o.y });
      const points = [section.startPoint, ...(section.bendPoints ?? []), section.endPoint].map(shift);
      const label = edge.labels?.[0];
      result.edges[edge.id] = {
        points,
        label: label && label.x !== undefined ? { x: o.x + label.x + (label.width ?? 0) / 2, y: o.y + (label.y ?? 0) + (label.height ?? 0) / 2 } : null,
      };
    }
    node.children?.forEach(collect);
  };
  collect(out);
  return result;
}
