// A canvas in the browser: the view (pan and zoom), the nodes the server
// renders (read from the DOM, and placed), the edges (drawn here, in SVG,
// from the edge data the server renders), and what a person does with
// them: select, drag, connect, resize, delete, copy, undo. Each change goes
// to the server (Hakushi.Canvas), which applies it, or refuses it and the
// canvas takes it back.
//
// The server owns the nodes' elements: a change it sends patches them, and
// a MutationObserver reads them again and puts back what this file sets on
// them (the place of a node being dragged, its selection, its culling).

import { editable, el, interactive, isApple, numberAttr, svg } from "./dom";
import { contains, edgePath, facing, fromCorners, grow, intersects, sidePoint, union } from "./geometry";
import { icons } from "./icons";
import { Messages } from "./messages";
import { Minimap } from "./minimap";
import { check } from "./rules";
import { align, snapToGrid, type Guide } from "./snap";
import type { Config, EdgeModel, End, Handle, HandleKind, Live, NodeModel, Person, Point, Rect, Side, View } from "./types";
import { centerOn, clamp, fit, reveal, toCanvas, visible, zoomAt } from "./view";

// Nodes are culled (not laid out off the screen) above this many.
const CULL_FROM = 150;
// How far around the screen nodes stay laid out, in pixels.
const CULL_MARGIN = 300;
// A pointer that moves less than this is a click.
const CLICK_SLOP = 3;
// How near a handle the pointer must come to end an edge on it, in pixels.
const CONNECT_RADIUS = 24;
// The helper lines catch a box this near, in pixels.
const ALIGN_THRESHOLD = 6;
// The others' cursors and drags, at most this often.
const PEER_INTERVAL = 50;
// A person not heard of for this long has no cursor.
const PEER_TIMEOUT = 30_000;

type Gesture =
  | { kind: "pan"; pointer: number; start: Point; view: View }
  | {
      kind: "drag";
      pointer: number;
      start: Point;
      moved: boolean;
      primary: string;
      origin: Map<string, Point>;
      others: Rect[];
    }
  | { kind: "box"; pointer: number; start: Point; end: Point; base: Set<string> }
  | {
      kind: "connect";
      pointer: number | null;
      from: End;
      fromHandle: Handle | null;
      reverse: boolean;
      at: Point;
      target: { end: End; handle: Handle | null } | null;
      // Keyboard: the targets in turn, and the one chosen.
      choices?: { end: End; handle: Handle | null }[];
      index?: number;
    }
  | { kind: "resize"; pointer: number; id: string; corner: string; start: Point; rect: Rect }
  | { kind: "pinch"; distance: number; mid: Point; view: View };

interface EdgeView {
  g: SVGGElement;
  line: SVGPathElement;
  hit: SVGPathElement;
  label: HTMLElement | null;
  shown: boolean;
  // Around the path: to cull it.
  box: Rect;
}

interface Peer {
  cursor: Point | null;
  selected: string[];
  dragging: Map<string, Point>;
  seen: number;
  el: HTMLElement | null;
}

export class Canvas {
  readonly id: string;
  private config!: Config;
  private messages!: Messages;

  private viewportEl: HTMLElement;
  private world: HTMLElement;
  private nodesEl: HTMLElement;
  private edgeData: HTMLElement;
  private labelsEl: HTMLElement;
  private edgesSvg: SVGSVGElement;
  private edgesG: SVGGElement;
  private overlay: SVGGElement;
  private ui: HTMLElement;
  private status: HTMLElement;
  private boxEl: HTMLElement;
  private cursorsEl: HTMLElement;
  private controlsEl: HTMLElement | null = null;
  private zoomLabel: HTMLElement | null = null;
  private minimap: Minimap | null = null;

  private view: View = { x: 0, y: 0, zoom: 1 };
  private size = { width: 0, height: 0 };
  private bounds: DOMRect | null = null;
  private nodes = new Map<string, NodeModel>();
  private order: string[] = [];
  private edges = new Map<string, EdgeModel>();
  private edgeViews = new Map<string, EdgeView>();
  private byNode = new Map<string, Set<string>>();
  private selected = new Set<string>();
  private selectedEdges = new Set<string>();
  private gone = new Set<string>();
  private culled = new Set<string>();
  private dirty = new Set<string>();
  private allDirty = true;
  private guides: Guide[] = [];
  private pending: { id: string; source: End; target: End } | null = null;
  private gesture: Gesture | null = null;
  private pointers = new Map<number, Point>();
  private space = false;
  private pointer: Point | null = null;
  private frame = 0;
  private fitted = false;
  private observers: (MutationObserver | ResizeObserver)[] = [];
  private cleanups: (() => void)[] = [];
  private nudge: { origin: Map<string, Point>; timer: number } | null = null;
  private people = new Map<string, Person>();
  private peers = new Map<string, Peer>();
  private peerTimer = 0;
  private peerSent = 0;
  private noticeSeq = "0";
  private noticeTimer = 0;
  private connected = true;
  private lastFocus: Element | null = null;
  private pendingSelect: string[] | null = null;
  // Changes whenever a node moves, comes, goes or is selected: for the minimap.
  private layoutVersion = 0;
  private boundsVersion = -1;
  private allBounds: Rect | null = null;
  private drawnView: View | null = null;
  private culledVersion = -1;
  private culledView: View | null = null;

  constructor(
    readonly root: HTMLElement,
    private hookEl: HTMLElement,
    private live: Live,
  ) {
    this.id = root.id;
    this.readConfig();
    this.viewportEl = this.part("-viewport");
    this.world = this.part("-world");
    this.nodesEl = this.part("-nodes");
    this.edgeData = this.part("-edge-data");
    this.labelsEl = this.part("-labels");
    this.edgesSvg = root.querySelector<SVGSVGElement>(`#${CSS.escape(this.id)}-svg`)!;
    this.ui = this.part("-ui");

    this.edgesSvg.append(this.defs());
    this.edgesG = svg("g", { class: "hakushi-edge-lines" });
    this.overlay = svg("g", { class: "hakushi-overlay" });
    this.edgesSvg.append(this.edgesG, this.overlay);

    this.status = el("div", { class: "hakushi-status", role: "status", "aria-live": "polite" });
    this.boxEl = el("div", { class: "hakushi-box", hidden: "" });
    this.cursorsEl = el("div", { class: "hakushi-cursors", "aria-hidden": "true" });
    this.ui.append(this.cursorsEl, this.boxEl, this.status);
    this.buildControls();

    this.readNodes();
    this.readEdges();
    this.observe();
    this.listen();
    this.measureRoot();
    this.schedule();
  }

  private part(suffix: string): HTMLElement {
    return this.root.querySelector<HTMLElement>(`#${CSS.escape(this.id + suffix)}`)!;
  }

  private readConfig() {
    this.config = JSON.parse(this.hookEl.dataset.config || "{}") as Config;
    this.messages = new Messages(this.config.messages || {}, this.config.locale || "en");
    this.root.toggleAttribute("data-ui-readonly", this.config.readonly);
  }

  // -- The server's renders -------------------------------------------------

  /** After a render of the server: the config, the notice. */
  update() {
    this.minimap?.refresh();
    this.layoutVersion++;
    const minimap = this.config.minimap;
    const controls = this.config.controls;
    this.readConfig();
    if (minimap !== this.config.minimap || controls !== this.config.controls) this.buildControls();
    this.showNotice();
    this.schedule();
  }

  setConnected(connected: boolean) {
    this.connected = connected;
    this.root.toggleAttribute("data-ui-offline", !connected);
    if (!connected) this.announce(this.messages.t("offline"));
  }

  private showNotice() {
    const notice = this.root.querySelector<HTMLElement>(":scope > .hakushi-notice");
    if (!notice) return;
    const seq = notice.dataset.seq ?? "0";
    if (seq !== this.noticeSeq && notice.hasAttribute("data-hakushi-notice")) {
      this.noticeSeq = seq;
      notice.setAttribute("data-ui-shown", "");
      clearTimeout(this.noticeTimer);
      this.noticeTimer = window.setTimeout(() => notice.removeAttribute("data-ui-shown"), 4000);
    } else if (!notice.hasAttribute("data-hakushi-notice")) {
      notice.removeAttribute("data-ui-shown");
    }
  }

  private readNodes() {
    this.order = [];
    for (const element of this.nodesEl.children) {
      if (element instanceof HTMLElement && element.classList.contains("hakushi-node")) this.readNode(element);
    }
  }

  private readNode(element: HTMLElement): NodeModel | null {
    const id = element.dataset.id;
    if (!id) return null;
    const width = numberAttr(element, "data-width");
    const height = numberAttr(element, "data-height");
    const old = this.nodes.get(id);
    const node: NodeModel = {
      id,
      type: element.dataset.type || "default",
      x: numberAttr(element, "data-x") ?? 0,
      y: numberAttr(element, "data-y") ?? 0,
      width: width ?? (old && old.el === element ? old.width : element.offsetWidth),
      height: height ?? (old && old.el === element ? old.height : element.offsetHeight),
      fixed: width !== null,
      locked: element.dataset.locked === "true",
      resizable: element.dataset.resizable === "true",
      label: element.getAttribute("aria-label") || id,
      handles: old && old.el === element ? old.handles : [],
      measured: false,
      el: element,
    };
    this.nodes.set(id, node);
    if (!old) this.order.push(id);
    this.measureHandles(node);
    this.decorate(node);
    this.touchNode(id);
    return node;
  }

  /** The handles of a node, and their places in it. */
  private measureHandles(node: NodeModel) {
    const element = node.el;
    if (element.hasAttribute("data-ui-culled")) return;
    node.measured = true;
    const box = element.getBoundingClientRect();
    const zoom = this.view.zoom || 1;
    if (!node.fixed && box.width > 0) {
      node.width = element.offsetWidth;
      node.height = element.offsetHeight;
    }
    node.handles = [...element.querySelectorAll<HTMLElement>(".hakushi-handle")].map((h) => {
      const r = h.getBoundingClientRect();
      return {
        id: h.dataset.handle || null,
        kind: (h.dataset.kind as HandleKind) || "both",
        side: (h.dataset.side as Side) || "right",
        type: h.dataset.type || null,
        accepts: h.dataset.accepts ? h.dataset.accepts.split(" ") : null,
        max: numberAttr(h, "data-max"),
        x: (r.left + r.width / 2 - box.left) / zoom,
        y: (r.top + r.height / 2 - box.top) / zoom,
        el: h,
      };
    });
  }

  /** What the browser sets on a node's element: its place, selection, culling, the others. */
  private decorate(node: NodeModel) {
    const element = node.el;
    const place = this.placeOf(node);
    element.style.translate = `${place.x}px ${place.y}px`;
    if (node.fixed || this.gesture?.kind === "resize") {
      element.style.width = `${node.width}px`;
      element.style.height = `${node.height}px`;
    }
    toggle(element, "data-ui-selected", this.selected.has(node.id));
    toggle(element, "data-ui-gone", this.gone.has(node.id));
    toggle(element, "data-ui-culled", this.culled.has(node.id));
    const peer = this.peerOf(node.id);
    if (peer) {
      element.setAttribute("data-ui-peer", "");
      element.style.setProperty("--hakushi-peer", peer.color);
      element.dataset.uiPeerName = peer.dragging ? this.messages.t("movingBy", { name: peer.name }) : peer.name;
    } else if (element.hasAttribute("data-ui-peer")) {
      element.removeAttribute("data-ui-peer");
      element.removeAttribute("data-ui-peer-name");
      element.style.removeProperty("--hakushi-peer");
    }
    if (node.resizable && this.selected.has(node.id) && !this.config.readonly && !node.locked) this.addResizers(node);
    else element.querySelectorAll(":scope > .hakushi-resizer").forEach((r) => r.remove());
  }

  private addResizers(node: NodeModel) {
    if (node.el.querySelector(":scope > .hakushi-resizer")) return;
    for (const corner of ["nw", "ne", "sw", "se"]) {
      node.el.append(el("span", { class: "hakushi-resizer", "data-corner": corner, "aria-hidden": "true" }));
    }
  }

  // The place a node shows at: its own, or where a person drags it.
  private placeOf(node: NodeModel): Point {
    for (const peer of this.peers.values()) {
      const at = peer.dragging.get(node.id);
      if (at && !(this.gesture?.kind === "drag" && this.gesture.origin.has(node.id))) return at;
    }
    return { x: node.x, y: node.y };
  }

  private peerOf(id: string): { color: string; name: string; dragging: boolean } | null {
    for (const [person, peer] of this.peers) {
      const dragging = peer.dragging.has(id);
      if (dragging || peer.selected.includes(id)) {
        const who = this.people.get(person);
        if (who) return { color: who.color, name: who.name ?? who.id, dragging };
      }
    }
    return null;
  }

  private readEdges() {
    this.edges.clear();
    this.byNode.clear();
    for (const element of this.edgeData.children) this.readEdge(element as HTMLElement);
    for (const id of [...this.edgeViews.keys()]) if (!this.edges.has(id)) this.dropEdgeView(id);
    this.allDirty = true;
  }

  private readEdge(element: HTMLElement) {
    const id = element.dataset.id;
    if (!id) return;
    const old = this.edges.get(id);
    if (old) this.unindex(old);
    const edge: EdgeModel = {
      id,
      source: element.dataset.source!,
      sourceHandle: element.dataset.sourceHandle ?? null,
      target: element.dataset.target!,
      targetHandle: element.dataset.targetHandle ?? null,
      path: (element.dataset.path as EdgeModel["path"]) || "bezier",
      label: element.dataset.label ?? null,
      marker: (element.dataset.marker as EdgeModel["marker"]) || "arrow",
      animated: element.dataset.animated === "true",
    };
    this.edges.set(id, edge);
    this.index(edge);
    this.dirty.add(id);
    if (
      this.pending &&
      edge.source === this.pending.source.node &&
      edge.target === this.pending.target.node &&
      (edge.sourceHandle ?? null) === this.pending.source.handle &&
      (edge.targetHandle ?? null) === this.pending.target.handle
    ) {
      this.pending = null;
    }
  }

  private index(edge: EdgeModel) {
    for (const node of [edge.source, edge.target]) {
      let set = this.byNode.get(node);
      if (!set) this.byNode.set(node, (set = new Set()));
      set.add(edge.id);
    }
  }

  private unindex(edge: EdgeModel) {
    this.byNode.get(edge.source)?.delete(edge.id);
    this.byNode.get(edge.target)?.delete(edge.id);
  }

  private touchNode(id: string) {
    this.layoutVersion++;
    for (const edge of this.byNode.get(id) ?? []) this.dirty.add(edge);
  }

  private observe() {
    const nodes = new MutationObserver((records) => this.nodesChanged(records));
    nodes.observe(this.nodesEl, { childList: true, subtree: true, attributes: true, characterData: true });
    const edges = new MutationObserver((records) => this.edgesChanged(records));
    edges.observe(this.edgeData, { childList: true, subtree: true, attributes: true });
    const sizes = new ResizeObserver((entries) => {
      for (const entry of entries) {
        const element = entry.target as HTMLElement;
        if (element === this.root) {
          this.measureRoot();
          continue;
        }
        const node = this.nodes.get(element.dataset.id || "");
        if (!node || node.el !== element || element.hasAttribute("data-ui-culled")) continue;
        this.measureHandles(node);
        this.touchNode(node.id);
      }
      this.schedule();
    });
    sizes.observe(this.root);
    for (const node of this.nodes.values()) sizes.observe(node.el);
    const notice = this.root.querySelector(":scope > .hakushi-notice");
    const notices = new MutationObserver(() => this.showNotice());
    if (notice) notices.observe(notice, { attributes: true, childList: true, characterData: true, subtree: true });
    this.observers.push(nodes, edges, sizes, notices);
  }

  private get sizes(): ResizeObserver {
    return this.observers[2] as ResizeObserver;
  }

  // The server inserted, patched or deleted nodes.
  private nodesChanged(records: MutationRecord[]) {
    const touched = new Set<HTMLElement>();
    let removed = false;
    for (const record of records) {
      if (record.type === "childList" && record.target === this.nodesEl) {
        record.addedNodes.forEach((n) => n instanceof HTMLElement && n.classList.contains("hakushi-node") && touched.add(n));
        if (record.removedNodes.length) removed = true;
        continue;
      }
      // What the browser sets on a node is not news.
      if (record.type === "attributes" && (record.target as Element).classList?.contains("hakushi-node")) {
        const name = record.attributeName || "";
        if (!name.startsWith("data-") || name.startsWith("data-ui-")) continue;
      }
      const target = record.target instanceof Element ? record.target : record.target.parentElement;
      if (target?.closest(".hakushi-resizer")) continue;
      const node = target?.closest<HTMLElement>(".hakushi-node");
      if (node && this.nodesEl.contains(node)) touched.add(node);
    }

    if (removed) {
      // A node that had the focus went: the focus stays in the canvas.
      if (this.lastFocus && !this.lastFocus.isConnected && (document.activeElement === document.body || document.activeElement === null)) this.root.focus({ preventScroll: true });
      for (const [id, node] of this.nodes) {
        if (!node.el.isConnected) {
          this.nodes.delete(id);
          this.selected.delete(id);
          this.gone.delete(id);
          this.culled.delete(id);
          this.sizes.unobserve(node.el);
        }
      }
      this.order = [...this.nodesEl.children].map((n) => (n as HTMLElement).dataset.id!).filter((id) => this.nodes.has(id));
    }
    for (const element of touched) {
      const fresh = !this.nodes.has(element.dataset.id || "");
      const node = this.readNode(element);
      if (node && fresh) {
        this.sizes.observe(element);
        this.order = [...this.nodesEl.children].map((n) => (n as HTMLElement).dataset.id!).filter((id) => this.nodes.has(id));
      }
    }
    this.allDirty = true;
    this.layoutVersion++;
    if (this.pendingSelect) this.selectPending();
    this.schedule();
  }

  private edgesChanged(records: MutationRecord[]) {
    let removed = false;
    for (const record of records) {
      if (record.type === "childList") {
        record.addedNodes.forEach((n) => n instanceof HTMLElement && this.readEdge(n));
        if (record.removedNodes.length) removed = true;
      } else if (record.target instanceof HTMLElement && record.target.parentElement === this.edgeData) {
        this.readEdge(record.target);
      }
    }
    if (removed) {
      const present = new Set([...this.edgeData.children].map((n) => (n as HTMLElement).dataset.id));
      for (const [id, edge] of this.edges) {
        if (!present.has(id)) {
          this.unindex(edge);
          this.edges.delete(id);
          this.selectedEdges.delete(id);
          this.gone.delete(id);
          this.dropEdgeView(id);
        }
      }
    }
    this.schedule();
  }

  // -- Drawing --------------------------------------------------------------

  private schedule() {
    if (this.frame) return;
    this.frame = requestAnimationFrame(() => {
      this.frame = 0;
      this.render();
    });
  }

  private render() {
    if (!this.fitted && this.size.width > 0) {
      this.fitted = true;
      this.view = this.config.fit && this.nodes.size ? this.fitView() : { x: 40, y: 40, zoom: 1 };
    }
    const viewChanged = this.view !== this.drawnView;
    if (viewChanged) {
      this.drawnView = this.view;
      this.world.style.transform = `translate(${this.view.x}px, ${this.view.y}px) scale(${this.view.zoom})`;
      const bg = this.viewportEl.style;
      bg.setProperty("--hakushi-grid-size", `${this.config.grid * this.view.zoom}px`);
      bg.setProperty("--hakushi-grid-x", `${this.view.x}px`);
      bg.setProperty("--hakushi-grid-y", `${this.view.y}px`);
      const far = this.view.zoom < 0.5 ? "far" : "near";
      if (this.root.dataset.uiZoom !== far) this.root.dataset.uiZoom = far;
    }

    // Culled again when the view moved half the margin, or the zoom by a
    // tenth: in between, a pan moves what is laid out, and changes nothing
    // in the page but the transform.
    const last = this.culledView;
    const recull =
      this.layoutVersion !== this.culledVersion ||
      !last ||
      Math.abs(this.view.x - last.x) > CULL_MARGIN / 2 ||
      Math.abs(this.view.y - last.y) > CULL_MARGIN / 2 ||
      Math.abs(this.view.zoom / last.zoom - 1) > 0.1;
    if (recull) {
      this.culledVersion = this.layoutVersion;
      this.culledView = this.view;
      this.cull();
    }
    this.drawEdges(recull && viewChanged);
    this.drawOverlay();
    this.drawPeers();
    const percent = `${Math.round(this.view.zoom * 100)}%`;
    if (this.zoomLabel && this.zoomLabel.textContent !== percent) this.zoomLabel.textContent = percent;
    if (this.minimap) {
      if (this.layoutVersion !== this.boundsVersion) {
        this.boundsVersion = this.layoutVersion;
        this.allBounds = union([...this.nodes.values()].map((n) => this.rect(n)));
      }
      this.minimap.draw(
        () =>
          this.order.map((id) => {
            const n = this.nodes.get(id)!;
            return { ...this.placeOf(n), width: n.width, height: n.height, selected: this.selected.has(id) };
          }),
        this.layoutVersion,
        this.allBounds,
        visible(this.view, this.size.width, this.size.height),
      );
    }
  }

  private cull() {
    if (this.nodes.size < CULL_FROM) {
      if (this.culled.size) {
        const was = [...this.culled];
        this.culled.clear();
        for (const id of was) {
          const node = this.nodes.get(id);
          if (node) node.el.removeAttribute("data-ui-culled");
        }
      }
      return;
    }
    const area = grow(visible(this.view, this.size.width, this.size.height), CULL_MARGIN / this.view.zoom);
    const focused = document.activeElement;
    const unmeasured: NodeModel[] = [];
    for (const node of this.nodes.values()) {
      const shown =
        intersects(area, { ...this.placeOf(node), width: node.width, height: node.height }) ||
        this.selected.has(node.id) ||
        node.el.contains(focused);
      if (shown === !this.culled.has(node.id)) continue;
      if (shown) {
        this.culled.delete(node.id);
        node.el.removeAttribute("data-ui-culled");
        // The handles keep their places while a node is culled: a node
        // measured once is not measured again, which would lay out the page
        // for each node that comes into view.
        if (!node.measured) unmeasured.push(node);
        this.touchNode(node.id);
      } else {
        this.culled.add(node.id);
        node.el.setAttribute("data-ui-culled", "");
      }
    }
    for (const node of unmeasured) this.measureHandles(node);
  }

  // The edges that changed get their paths again; with a new view, every
  // edge is shown or hidden by its box, so that the edges far off the screen
  // are not painted.
  private drawEdges(viewChanged: boolean) {
    const area = grow(visible(this.view, this.size.width, this.size.height), CULL_MARGIN / this.view.zoom);
    const all = this.edges.size < CULL_FROM * 2;
    const ids = this.allDirty ? [...this.edges.keys()] : [...this.dirty];
    for (const id of ids) {
      const edge = this.edges.get(id);
      if (!edge) continue;
      const geometry = this.geometry(edge);
      if (!geometry) {
        this.dropEdgeView(id);
        continue;
      }
      const view = this.edgeView(edge);
      const path = edgePath(edge.path, geometry.from, geometry.fromSide, geometry.to, geometry.toSide);
      view.box = grow(fromCorners(geometry.from, geometry.to), 80);
      view.line.setAttribute("d", path.d);
      view.hit.setAttribute("d", path.d);
      view.line.setAttribute("marker-end", edge.marker === "none" ? "" : `url(#${this.id}-${edge.marker}${this.selectedEdges.has(id) ? "-on" : ""})`);
      toggle(view.g, "data-ui-selected", this.selectedEdges.has(id));
      toggle(view.g, "data-ui-gone", this.gone.has(id));
      toggle(view.g, "data-animated", edge.animated);
      if (edge.label) {
        if (!view.label) {
          view.label = el("div", { class: "hakushi-edge-label", "data-edge": id });
          this.labelsEl.append(view.label);
        }
        view.label.hidden = this.gone.has(id);
        if (view.label.textContent !== edge.label) view.label.textContent = edge.label;
        view.label.style.translate = `${path.label.x}px ${path.label.y}px`;
        toggle(view.label, "data-ui-selected", this.selectedEdges.has(id));
      } else if (view.label) {
        view.label.remove();
        view.label = null;
      }
      if (!viewChanged) this.showEdge(view, all || intersects(view.box, area) || this.selectedEdges.has(id));
    }
    if (viewChanged) {
      for (const [id, view] of this.edgeViews) this.showEdge(view, all || intersects(view.box, area) || this.selectedEdges.has(id));
    }
    this.dirty.clear();
    this.allDirty = false;
  }

  private showEdge(view: EdgeView, shown: boolean) {
    if (shown === view.shown) return;
    view.shown = shown;
    view.g.style.display = shown ? "" : "none";
    if (view.label) view.label.style.display = shown ? "" : "none";
  }

  private edgeView(edge: EdgeModel): EdgeView {
    let view = this.edgeViews.get(edge.id);
    if (!view) {
      const g = svg("g", { class: "hakushi-edge", "data-edge": edge.id });
      const hit = svg("path", { class: "hakushi-edge-hit" });
      const line = svg("path", { class: "hakushi-edge-line" });
      g.append(hit, line);
      this.edgesG.append(g);
      view = { g, line, hit, label: null, shown: true, box: { x: 0, y: 0, width: 0, height: 0 } };
      this.edgeViews.set(edge.id, view);
    }
    return view;
  }

  private dropEdgeView(id: string) {
    const view = this.edgeViews.get(id);
    if (!view) return;
    view.g.remove();
    view.label?.remove();
    this.edgeViews.delete(id);
  }

  private geometry(edge: EdgeModel): { from: Point; fromSide: Side; to: Point; toSide: Side } | null {
    const source = this.nodes.get(edge.source);
    const target = this.nodes.get(edge.target);
    if (!source || !target) return null;
    const s = this.anchor(source, edge.sourceHandle, "source", this.center(target));
    const t = this.anchor(target, edge.targetHandle, "target", this.center(source));
    return { from: s.point, fromSide: s.side, to: t.point, toSide: t.side };
  }

  private center(node: NodeModel): Point {
    const at = this.placeOf(node);
    return { x: at.x + node.width / 2, y: at.y + node.height / 2 };
  }

  private rect(node: NodeModel): Rect {
    return { ...this.placeOf(node), width: node.width, height: node.height };
  }

  /** Where an edge meets a node: at its handle, or its first handle of that kind, or its side. */
  private anchor(node: NodeModel, handleId: string | null, kind: "source" | "target", towards: Point): { point: Point; side: Side } {
    const at = this.placeOf(node);
    const handle = this.handleOf(node, handleId, kind, towards);
    if (handle) return { point: { x: at.x + handle.x, y: at.y + handle.y }, side: handle.side };
    const rect = this.rect(node);
    const side = facing(rect, towards);
    return { point: sidePoint(rect, side), side };
  }

  // The handle of an id that an edge of that kind meets: of several with
  // one id (a row with a handle on each side), the one nearest `towards`.
  private handleOf(node: NodeModel, id: string | null, kind: "source" | "target", towards?: Point): Handle | null {
    const fits = (h: Handle) => h.kind === "both" || h.kind === kind;
    let list = id !== null ? node.handles.filter((h) => h.id === id && fits(h)) : node.handles.filter((h) => h.id === null && fits(h));
    if (!list.length) list = id !== null ? node.handles.filter((h) => h.id === id) : node.handles.filter(fits).slice(0, 1);
    if (list.length < 2 || !towards) return list[0] ?? null;
    const at = this.placeOf(node);
    let best = list[0];
    let distance = Infinity;
    for (const h of list) {
      const d = Math.hypot(at.x + h.x - towards.x, at.y + h.y - towards.y);
      if (d < distance) {
        distance = d;
        best = h;
      }
    }
    return best;
  }

  private drawOverlay() {
    this.overlay.replaceChildren();
    for (const guide of this.guides) {
      const line =
        guide.axis === "x"
          ? svg("line", { x1: `${guide.at}`, x2: `${guide.at}`, y1: `${guide.from}`, y2: `${guide.to}` })
          : svg("line", { y1: `${guide.at}`, y2: `${guide.at}`, x1: `${guide.from}`, x2: `${guide.to}` });
      line.setAttribute("class", "hakushi-guide");
      line.setAttribute("vector-effect", "non-scaling-stroke");
      this.overlay.append(line);
    }

    const g = this.gesture;
    if (g?.kind === "connect") {
      const node = this.nodes.get(g.from.node);
      if (node) {
        const fromKind = g.reverse ? "target" : "source";
        const start = this.anchor(node, g.from.handle, fromKind, g.at);
        let end = g.at;
        let endSide: Side = facing({ x: g.at.x, y: g.at.y, width: 0, height: 0 }, start.point);
        if (g.target) {
          const targetNode = this.nodes.get(g.target.end.node);
          if (targetNode) {
            const a = this.anchor(targetNode, g.target.end.handle, g.reverse ? "source" : "target", start.point);
            end = a.point;
            endSide = a.side;
          }
        }
        const path = g.reverse ? edgePath("bezier", end, endSide, start.point, start.side) : edgePath("bezier", start.point, start.side, end, endSide);
        this.overlay.append(svg("path", { class: "hakushi-edge-pending", d: path.d, "data-ui-valid": g.target ? "true" : "false" }));
      }
    }
    if (this.pending) {
      const source = this.nodes.get(this.pending.source.node);
      const target = this.nodes.get(this.pending.target.node);
      if (source && target) {
        const s = this.anchor(source, this.pending.source.handle, "source", this.center(target));
        const t = this.anchor(target, this.pending.target.handle, "target", this.center(source));
        this.overlay.append(svg("path", { class: "hakushi-edge-pending", d: edgePath("bezier", s.point, s.side, t.point, t.side).d }));
      }
    }
  }

  private defs(): SVGDefsElement {
    const defs = svg("defs");
    for (const on of ["", "-on"]) {
      const arrow = svg("marker", {
        id: `${this.id}-arrow${on}`,
        viewBox: "0 0 10 10",
        refX: "9",
        refY: "5",
        markerWidth: "7",
        markerHeight: "7",
        orient: "auto-start-reverse",
        class: `hakushi-marker${on ? " hakushi-marker-on" : ""}`,
      });
      arrow.append(svg("path", { d: "M0,0L10,5L0,10z" }));
      const dot = svg("marker", {
        id: `${this.id}-dot${on}`,
        viewBox: "0 0 10 10",
        refX: "5",
        refY: "5",
        markerWidth: "6",
        markerHeight: "6",
        class: `hakushi-marker${on ? " hakushi-marker-on" : ""}`,
      });
      dot.append(svg("circle", { cx: "5", cy: "5", r: "4" }));
      defs.append(arrow, dot);
    }
    return defs;
  }

  // -- Controls --------------------------------------------------------------

  private buildControls() {
    this.controlsEl?.remove();
    this.minimap?.el.remove();
    this.controlsEl = null;
    this.zoomLabel = null;
    this.minimap = null;

    if (this.config.controls) {
      const button = (action: string, label: string, content: string, run: () => void) => {
        const b = el("button", { type: "button", class: "hakushi-control", "data-action": action, "aria-label": label, title: label });
        b.innerHTML = content;
        b.addEventListener("click", (event) => {
          event.stopPropagation();
          run();
        });
        return b;
      };
      const t = (key: string) => this.messages.t(key);
      this.zoomLabel = button("zoom-reset", t("zoomReset"), "100%", () => this.zoomTo(1));
      this.zoomLabel.classList.add("hakushi-zoom");
      const group = el("div", { class: "hakushi-controls", role: "toolbar", "aria-label": t("zoom") }, [
        button("zoom-out", t("zoomOut"), icons.zoomOut, () => this.zoomBy(1 / 1.25)),
        this.zoomLabel,
        button("zoom-in", t("zoomIn"), icons.zoomIn, () => this.zoomBy(1.25)),
        button("fit", t("fit"), icons.fit, () => this.fitAll()),
      ]);
      if (!this.config.readonly) {
        group.append(button("undo", t("undo"), icons.undo, () => this.undo()), button("redo", t("redo"), icons.redo, () => this.redo()));
      }
      group.addEventListener("pointerdown", (event) => event.stopPropagation());
      this.controlsEl = group;
      this.ui.append(group);
    }

    if (this.config.minimap) {
      this.minimap = new Minimap(this.messages.t("minimap"), (x, y) => {
        this.view = centerOn(this.view, x, y, this.size.width, this.size.height);
        this.schedule();
      });
      this.ui.append(this.minimap.el);
    }
  }

  // -- The view ----------------------------------------------------------------

  private measureRoot() {
    const rect = this.root.getBoundingClientRect();
    this.bounds = rect;
    const changed = rect.width !== this.size.width || rect.height !== this.size.height;
    this.size = { width: rect.width, height: rect.height };
    if (changed) this.schedule();
  }

  private fitView(ids?: Iterable<string>): View {
    const list = ids ? [...ids].map((id) => this.nodes.get(id)).filter((n): n is NodeModel => !!n) : [...this.nodes.values()];
    return fit(union(list.map((n) => this.rect(n))), this.size.width, this.size.height, 48, this.config.minZoom, this.config.maxZoom);
  }

  fitAll() {
    this.view = this.fitView();
    this.schedule();
  }

  zoomBy(factor: number, at?: Point) {
    const p = at ?? { x: this.size.width / 2, y: this.size.height / 2 };
    this.view = zoomAt(this.view, factor, p.x, p.y, this.config.minZoom, this.config.maxZoom);
    this.schedule();
  }

  zoomTo(zoom: number) {
    this.zoomBy(zoom / this.view.zoom);
  }

  /** The view, for the tests and the app. */
  getView(): View {
    return { ...this.view };
  }

  setView(view: Partial<View>) {
    this.view = { ...this.view, ...view, zoom: clamp(view.zoom ?? this.view.zoom, this.config.minZoom, this.config.maxZoom) };
    this.fitted = true;
    this.schedule();
  }

  private local(event: { clientX: number; clientY: number }): Point {
    const rect = this.bounds ?? this.root.getBoundingClientRect();
    return { x: event.clientX - rect.left, y: event.clientY - rect.top };
  }

  private canvasPoint(event: { clientX: number; clientY: number }): Point {
    const p = this.local(event);
    return toCanvas(this.view, p.x, p.y);
  }

  // -- Pointer ---------------------------------------------------------------

  private listen() {
    const on = <K extends keyof HTMLElementEventMap>(target: HTMLElement | Document | Window, type: K, fn: (event: HTMLElementEventMap[K]) => void, opts?: AddEventListenerOptions) => {
      target.addEventListener(type, fn as EventListener, opts);
      this.cleanups.push(() => target.removeEventListener(type, fn as EventListener, opts));
    };

    on(this.root, "pointerdown", (e) => this.pointerDown(e));
    on(this.root, "pointermove", (e) => this.pointerMove(e));
    on(this.root, "pointerup", (e) => this.pointerUp(e));
    on(this.root, "pointercancel", (e) => this.pointerUp(e, true));
    on(this.root, "pointerleave", () => {
      this.pointer = null;
      this.sendPeer();
    });
    on(this.root, "wheel", (e) => this.wheel(e), { passive: false });
    on(this.root, "dblclick", (e) => this.doubleClick(e));
    on(this.root, "keydown", (e) => this.keyDown(e));
    on(this.root, "keyup", (e) => {
      if (e.key === " ") {
        this.space = false;
        this.root.removeAttribute("data-ui-space");
      }
    });
    on(this.root, "focusin", (e) => this.focusIn(e));
    on(this.root, "contextmenu", (e) => {
      if (this.gesture) e.preventDefault();
    });
    on(document, "pointerdown", (e) => this.itemDown(e as PointerEvent), { capture: true });
    on(document, "keydown", (e) => this.itemKey(e as KeyboardEvent));
    on(window, "scroll", () => (this.bounds = null), { capture: true, passive: true });
  }

  private pointerDown(event: PointerEvent) {
    const target = event.target as Element;
    this.root.removeAttribute("data-ui-keyboard");
    if (target.closest(".hakushi-controls, .hakushi-minimap, .hakushi-edge-input")) return;
    this.bounds = this.root.getBoundingClientRect();
    this.pointers.set(event.pointerId, this.local(event));

    if (this.pointers.size === 2) {
      // A second finger: a pinch, which ends whatever the first began.
      this.cancelGesture();
      const [a, b] = [...this.pointers.values()];
      this.gesture = { kind: "pinch", distance: Math.hypot(a.x - b.x, a.y - b.y), mid: { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 }, view: this.view };
      return;
    }
    if (this.pointers.size > 2) return;

    const at = this.canvasPoint(event);
    const nodeEl = target.closest<HTMLElement>(".hakushi-node");
    const node = nodeEl && this.nodesEl.contains(nodeEl) ? this.nodes.get(nodeEl.dataset.id || "") : undefined;
    const handleEl = target.closest<HTMLElement>(".hakushi-handle");
    const edgeEl = target.closest<SVGGElement>(".hakushi-edge");
    const labelEl = target.closest<HTMLElement>(".hakushi-edge-label");

    // The middle button, or Space held: pan, wherever.
    if (event.button === 1 || this.space) {
      event.preventDefault();
      this.startPan(event);
      return;
    }
    if (event.button !== 0) return;

    if (handleEl && node && !this.config.readonly && !node.locked) {
      event.preventDefault();
      this.startConnect(event, node, handleEl, at);
      return;
    }
    const resizer = target.closest<HTMLElement>(".hakushi-resizer");
    if (resizer && node) {
      event.preventDefault();
      this.capture(event);
      this.gesture = { kind: "resize", pointer: event.pointerId, id: node.id, corner: resizer.dataset.corner!, start: at, rect: this.rect(node) };
      return;
    }
    if (node) {
      if (interactive(target, node.el)) return;
      const grips = node.el.querySelectorAll("[data-hakushi-drag]");
      const onGrip = grips.length === 0 || target.closest("[data-hakushi-drag]") !== null;
      if (event.shiftKey || event.metaKey || event.ctrlKey) {
        this.toggleSelect(node.id);
      } else if (!this.selected.has(node.id)) {
        this.select([node.id]);
      }
      if (!onGrip || this.config.readonly) return;
      event.preventDefault();
      this.root.focus({ preventScroll: true });
      this.startDrag(event, node.id, at);
      return;
    }
    const edgeId = edgeEl?.dataset.edge ?? labelEl?.dataset.edge;
    if (edgeId) {
      event.preventDefault();
      this.root.focus({ preventScroll: true });
      if (event.shiftKey) {
        if (this.selectedEdges.has(edgeId)) this.selectedEdges.delete(edgeId);
        else this.selectedEdges.add(edgeId);
      } else {
        this.selected.clear();
        this.selectedEdges = new Set([edgeId]);
      }
      this.selectionChanged();
      return;
    }

    // The sheet: a box to select with a mouse or a pen, a pan with a finger.
    event.preventDefault();
    this.root.focus({ preventScroll: true });
    if (event.pointerType === "touch") {
      this.startPan(event);
      return;
    }
    const base = event.shiftKey ? new Set(this.selected) : new Set<string>();
    if (!event.shiftKey) this.select([]);
    this.capture(event);
    this.gesture = { kind: "box", pointer: event.pointerId, start: at, end: at, base };
  }

  private capture(event: PointerEvent) {
    try {
      this.root.setPointerCapture(event.pointerId);
    } catch {
      // A pointer that is gone already.
    }
  }

  private startPan(event: PointerEvent) {
    this.capture(event);
    this.gesture = { kind: "pan", pointer: event.pointerId, start: this.local(event), view: this.view };
    this.root.setAttribute("data-ui-panning", "");
  }

  private startDrag(event: PointerEvent, primary: string, at: Point) {
    const ids = [...this.selected].filter((id) => !this.nodes.get(id)?.locked);
    if (!ids.includes(primary)) return;
    const origin = new Map(ids.map((id) => [id, { x: this.nodes.get(id)!.x, y: this.nodes.get(id)!.y }]));
    const area = grow(visible(this.view, this.size.width, this.size.height), 200 / this.view.zoom);
    const others: Rect[] = [];
    for (const node of this.nodes.values()) {
      if (origin.has(node.id)) continue;
      const r = this.rect(node);
      if (intersects(r, area)) others.push(r);
    }
    this.capture(event);
    this.gesture = { kind: "drag", pointer: event.pointerId, start: at, moved: false, primary, origin, others };
  }

  private startConnect(event: PointerEvent, node: NodeModel, handleEl: HTMLElement, at: Point) {
    const handle = node.handles.find((h) => h.el === handleEl) ?? null;
    const reverse = handle?.kind === "target";
    this.capture(event);
    this.gesture = { kind: "connect", pointer: event.pointerId, from: { node: node.id, handle: handle?.id ?? null }, fromHandle: handle, reverse, at, target: null };
    this.markTargets();
    this.schedule();
  }

  private pointerMove(event: PointerEvent) {
    if (this.pointers.has(event.pointerId)) this.pointers.set(event.pointerId, this.local(event));
    const at = this.canvasPoint(event);
    this.pointer = at;
    const g = this.gesture;

    if (!g) {
      this.sendPeer();
      return;
    }

    switch (g.kind) {
      case "pinch": {
        if (this.pointers.size < 2) return;
        const [a, b] = [...this.pointers.values()];
        const distance = Math.hypot(a.x - b.x, a.y - b.y);
        const mid = { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
        const zoomed = zoomAt(g.view, distance / g.distance, g.mid.x, g.mid.y, this.config.minZoom, this.config.maxZoom);
        this.view = { ...zoomed, x: zoomed.x + mid.x - g.mid.x, y: zoomed.y + mid.y - g.mid.y };
        this.schedule();
        return;
      }
      case "pan": {
        if (event.pointerId !== g.pointer) return;
        const p = this.local(event);
        this.view = { ...g.view, x: g.view.x + p.x - g.start.x, y: g.view.y + p.y - g.start.y };
        this.schedule();
        return;
      }
      case "box": {
        g.end = at;
        const box = fromCorners(g.start, g.end);
        const ids = new Set(g.base);
        for (const node of this.nodes.values()) if (intersects(box, this.rect(node))) ids.add(node.id);
        this.setSelection(ids);
        const tl = { x: box.x * this.view.zoom + this.view.x, y: box.y * this.view.zoom + this.view.y };
        Object.assign(this.boxEl.style, { left: `${tl.x}px`, top: `${tl.y}px`, width: `${box.width * this.view.zoom}px`, height: `${box.height * this.view.zoom}px` });
        this.boxEl.hidden = false;
        this.schedule();
        return;
      }
      case "drag": {
        let dx = at.x - g.start.x;
        let dy = at.y - g.start.y;
        if (!g.moved && Math.hypot(dx, dy) * this.view.zoom < CLICK_SLOP) return;
        g.moved = true;
        this.root.setAttribute("data-ui-dragging", "");
        const primary = this.nodes.get(g.primary)!;
        const origin = g.origin.get(g.primary)!;
        this.guides = [];
        if (this.config.snap) {
          dx = snapToGrid(origin.x + dx, this.config.grid) - origin.x;
          dy = snapToGrid(origin.y + dy, this.config.grid) - origin.y;
        } else if (!event.altKey) {
          const moved = { x: origin.x + dx, y: origin.y + dy, width: primary.width, height: primary.height };
          const a = align(moved, g.others, ALIGN_THRESHOLD / this.view.zoom);
          dx += a.dx;
          dy += a.dy;
          this.guides = a.guides;
        }
        for (const [id, o] of g.origin) {
          const node = this.nodes.get(id);
          if (!node) continue;
          node.x = round(o.x + dx);
          node.y = round(o.y + dy);
          node.el.style.translate = `${node.x}px ${node.y}px`;
          this.touchNode(id);
        }
        this.sendPeer();
        this.schedule();
        return;
      }
      case "resize": {
        const node = this.nodes.get(g.id);
        if (!node) return;
        const dx = at.x - g.start.x;
        const dy = at.y - g.start.y;
        let { x, y, width, height } = g.rect;
        if (g.corner.includes("e")) width = Math.max(40, width + dx);
        if (g.corner.includes("s")) height = Math.max(24, height + dy);
        if (g.corner.includes("w")) {
          width = Math.max(40, width - dx);
          x = g.rect.x + g.rect.width - width;
        }
        if (g.corner.includes("n")) {
          height = Math.max(24, height - dy);
          y = g.rect.y + g.rect.height - height;
        }
        if (this.config.snap) {
          width = Math.max(this.config.grid, snapToGrid(width, this.config.grid));
          height = Math.max(this.config.grid, snapToGrid(height, this.config.grid));
        }
        Object.assign(node, { x: round(x), y: round(y), width: round(width), height: round(height), fixed: true });
        this.decorate(node);
        this.measureHandles(node);
        this.touchNode(node.id);
        this.schedule();
        return;
      }
      case "connect": {
        g.at = at;
        g.target = this.targetAt(event, g);
        this.schedule();
        return;
      }
    }
  }

  private pointerUp(event: PointerEvent, cancelled = false) {
    this.pointers.delete(event.pointerId);
    const g = this.gesture;
    if (!g) return;
    if (g.kind === "pinch") {
      if (this.pointers.size < 2) this.gesture = null;
      return;
    }
    if ("pointer" in g && g.pointer !== event.pointerId) return;
    this.gesture = null;
    this.root.removeAttribute("data-ui-panning");
    this.root.removeAttribute("data-ui-dragging");

    switch (g.kind) {
      case "box":
        this.boxEl.hidden = true;
        this.selectionChanged();
        break;
      case "drag":
        this.guides = [];
        if (g.moved && !cancelled) this.commitMove(g.origin);
        else if (g.moved) this.revert(g.origin);
        else if (!event.shiftKey && !event.metaKey && !event.ctrlKey) this.select([g.primary]);
        break;
      case "resize": {
        const node = this.nodes.get(g.id);
        if (node && !cancelled) {
          const place = { id: node.id, x: node.x, y: node.y, width: node.width, height: node.height };
          this.push("hakushi:change", { op: "move", nodes: [place] }, (reply) => {
            if (reply.error) this.readNode(node.el);
          });
        }
        break;
      }
      case "connect":
        this.unmarkTargets();
        if (!cancelled && g.target) this.commitConnect(g);
        break;
    }
    this.sendPeer();
    this.schedule();
  }

  private cancelGesture() {
    const g = this.gesture;
    if (!g) return;
    this.gesture = null;
    if (g.kind === "drag" && g.moved) this.revert(g.origin);
    if (g.kind === "connect") this.unmarkTargets();
    if (g.kind === "box") this.boxEl.hidden = true;
    if (g.kind === "resize") {
      const node = this.nodes.get(g.id);
      if (node) this.readNode(node.el);
    }
    this.guides = [];
    this.root.removeAttribute("data-ui-panning");
    this.root.removeAttribute("data-ui-dragging");
    this.schedule();
  }

  private wheel(event: WheelEvent) {
    if (this.gesture?.kind === "pinch") return;
    event.preventDefault();
    const p = this.local(event);
    // A pinch on a trackpad comes as a wheel with Ctrl.
    const zooming = event.ctrlKey || event.metaKey || this.config.wheel === "zoom";
    if (zooming) {
      const delta = event.deltaMode === 1 ? event.deltaY * 16 : event.deltaY;
      this.zoomBy(Math.exp(-delta * (event.ctrlKey && !event.metaKey ? 0.01 : 0.002)), p);
      return;
    }
    const scale = event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? this.size.height : 1;
    const dx = (event.shiftKey && !event.deltaX ? event.deltaY : event.deltaX) * scale;
    const dy = (event.shiftKey && !event.deltaX ? 0 : event.deltaY) * scale;
    this.view = { ...this.view, x: this.view.x - dx, y: this.view.y - dy };
    this.schedule();
  }

  private doubleClick(event: MouseEvent) {
    const target = event.target as Element;
    const edgeId = target.closest<SVGGElement>(".hakushi-edge")?.dataset.edge ?? target.closest<HTMLElement>(".hakushi-edge-label")?.dataset.edge;
    if (edgeId && !this.config.readonly) {
      this.editLabel(edgeId);
      return;
    }
    if (target.closest(".hakushi-node, .hakushi-controls, .hakushi-minimap") || this.config.readonly || !this.config.newNode) return;
    const at = this.canvasPoint(event);
    this.drop(null, this.config.snap ? { x: snapToGrid(at.x, this.config.grid), y: snapToGrid(at.y, this.config.grid) } : at);
  }

  // -- Connecting --------------------------------------------------------------

  // The handles an edge from the gesture's end may end on.
  private validTargets(g: Extract<Gesture, { kind: "connect" }>): { end: End; handle: Handle | null }[] {
    const out: { end: End; handle: Handle | null }[] = [];
    const want = g.reverse ? "source" : "target";
    for (const node of this.nodes.values()) {
      if (this.gone.has(node.id)) continue;
      const handles = node.handles.filter((h) => h.kind === "both" || h.kind === want);
      const candidates: (Handle | null)[] = handles.length ? handles : node.handles.length ? [] : [null];
      for (const handle of candidates) {
        const end = { node: node.id, handle: handle?.id ?? null };
        const ok = g.reverse
          ? check(this.config.rules, this.edges.values(), end, handle, g.from, g.fromHandle)
          : check(this.config.rules, this.edges.values(), g.from, g.fromHandle, end, handle);
        if (ok === null) out.push({ end, handle });
      }
    }
    return out;
  }

  private markTargets() {
    const g = this.gesture;
    if (g?.kind !== "connect") return;
    this.root.setAttribute("data-ui-connecting", "");
    for (const t of this.validTargets(g)) {
      if (t.handle) t.handle.el.setAttribute("data-ui-valid", "");
      else this.nodes.get(t.end.node)?.el.setAttribute("data-ui-valid", "");
    }
    g.fromHandle?.el.setAttribute("data-ui-from", "");
  }

  private unmarkTargets() {
    this.root.removeAttribute("data-ui-connecting");
    this.root.querySelectorAll("[data-ui-valid], [data-ui-from], [data-ui-target]").forEach((e) => {
      e.removeAttribute("data-ui-valid");
      e.removeAttribute("data-ui-from");
      e.removeAttribute("data-ui-target");
    });
  }

  // The valid handle nearest the pointer, or a valid node under it.
  private targetAt(event: PointerEvent, g: Extract<Gesture, { kind: "connect" }>) {
    this.root.querySelectorAll("[data-ui-target]").forEach((e) => e.removeAttribute("data-ui-target"));
    const p = this.local(event);
    let best: { end: End; handle: Handle | null; d: number } | null = null;
    const under = document.elementFromPoint(event.clientX, event.clientY)?.closest<HTMLElement>(".hakushi-node");
    for (const handleEl of this.root.querySelectorAll<HTMLElement>(".hakushi-handle[data-ui-valid]")) {
      const r = handleEl.getBoundingClientRect();
      const rect = this.bounds!;
      const d = Math.hypot(r.left + r.width / 2 - rect.left - p.x, r.top + r.height / 2 - rect.top - p.y);
      const nodeEl = handleEl.closest<HTMLElement>(".hakushi-node")!;
      const within = d <= CONNECT_RADIUS || nodeEl === under;
      if (within && (!best || d < best.d)) {
        const node = this.nodes.get(nodeEl.dataset.id!)!;
        const handle = node.handles.find((h) => h.el === handleEl) ?? null;
        best = { end: { node: node.id, handle: handle?.id ?? null }, handle, d };
      }
    }
    if (!best && under?.hasAttribute("data-ui-valid")) best = { end: { node: under.dataset.id!, handle: null }, handle: null, d: 0 };
    if (best) (best.handle?.el ?? this.nodes.get(best.end.node)?.el)?.setAttribute("data-ui-target", "");
    void g;
    return best ? { end: best.end, handle: best.handle } : null;
  }

  private commitConnect(g: Extract<Gesture, { kind: "connect" }>) {
    if (!g.target) return;
    const source = g.reverse ? g.target.end : g.from;
    const target = g.reverse ? g.from : g.target.end;
    this.pending = { id: "pending", source, target };
    const names = { source: this.nodes.get(source.node)?.label ?? source.node, target: this.nodes.get(target.node)?.label ?? target.node };
    this.push("hakushi:change", { op: "connect", edges: [{ source: source.node, sourceHandle: source.handle, target: target.node, targetHandle: target.handle }] }, (reply) => {
      if (reply.error) {
        this.pending = null;
        this.schedule();
      } else {
        this.announce(this.messages.t("connected", names));
      }
    });
  }

  // -- Changes -------------------------------------------------------------------

  private push(event: string, payload: object, onReply?: (reply: Record<string, unknown>) => void) {
    this.live.push(event, payload, (reply) => {
      onReply?.(reply);
      if (Array.isArray(reply.select)) {
        // The new nodes may come after the reply: they are selected as
        // they come.
        this.pendingSelect = reply.select as string[];
        this.selectPending();
      }
    });
  }

  private selectPending() {
    const ids = this.pendingSelect;
    if (!ids || !ids.every((id) => this.nodes.has(id))) return;
    this.pendingSelect = null;
    this.select(ids);
    if (ids.length && !ids.some((id) => this.isOnScreen(id))) this.revealNodes(ids);
  }

  private commitMove(origin: Map<string, Point>) {
    const places = [...origin.keys()].map((id) => {
      const node = this.nodes.get(id)!;
      return { id, x: node.x, y: node.y };
    });
    if (places.every((p) => p.x === origin.get(p.id)!.x && p.y === origin.get(p.id)!.y)) return;
    const name = this.nodes.get(places[0].id)?.label ?? places[0].id;
    this.push("hakushi:change", { op: "move", nodes: places }, (reply) => {
      if (reply.error) this.revert(origin);
      else this.announce(places.length === 1 ? this.messages.t("movedOne", { name }) : this.messages.count("moved", places.length));
    });
  }

  private revert(origin: Map<string, Point>) {
    for (const [id, o] of origin) {
      const node = this.nodes.get(id);
      if (!node) continue;
      node.x = o.x;
      node.y = o.y;
      this.decorate(node);
      this.touchNode(id);
    }
    this.schedule();
  }

  deleteSelection() {
    if (this.config.readonly) return;
    const nodes = [...this.selected].filter((id) => !this.nodes.get(id)?.locked);
    const edges = [...this.selectedEdges];
    if (!nodes.length && !edges.length) return;
    const hide = new Set([...nodes, ...edges]);
    for (const id of nodes) for (const e of this.byNode.get(id) ?? []) hide.add(e);
    for (const id of hide) this.gone.add(id);
    const name = nodes.length === 1 && !edges.length ? this.nodes.get(nodes[0])?.label : null;
    // The focus stays in the canvas when its node goes.
    if (nodes.some((id) => this.nodes.get(id)?.el.contains(document.activeElement))) this.root.focus({ preventScroll: true });
    this.select([]);
    this.refresh(hide);
    this.push("hakushi:change", { op: "delete", nodes, edges }, (reply) => {
      if (reply.error) {
        for (const id of hide) this.gone.delete(id);
        this.refresh(hide);
      } else {
        this.announce(name ? this.messages.t("deletedOne", { name }) : this.messages.count("deleted", hide.size));
      }
    });
  }

  private refresh(ids: Iterable<string>) {
    for (const id of ids) {
      const node = this.nodes.get(id);
      if (node) {
        this.decorate(node);
        this.touchNode(id);
      } else {
        this.dirty.add(id);
      }
    }
    this.schedule();
  }

  copy(cut = false) {
    const ids = [...this.selected];
    if (!ids.length) return;
    this.push("hakushi:copy", { nodes: ids }, () => {
      if (cut) this.deleteSelection();
    });
  }

  paste() {
    if (this.config.readonly) return;
    const at = this.pointer && contains(visible(this.view, this.size.width, this.size.height), this.pointer) ? this.pointer : null;
    this.push("hakushi:paste", at ? { x: round(at.x), y: round(at.y) } : {});
  }

  duplicate() {
    if (this.config.readonly || !this.selected.size) return;
    this.push("hakushi:duplicate", { nodes: [...this.selected] });
  }

  undo() {
    if (!this.config.readonly) this.push("hakushi:undo", {}, (reply) => reply.error && this.announce(String(reply.error)));
  }

  redo() {
    if (!this.config.readonly) this.push("hakushi:redo", {}, (reply) => reply.error && this.announce(String(reply.error)));
  }

  /** A new node at a point of the canvas: for an item, or a double click (`item` null). */
  drop(item: string | null, at?: Point) {
    if (this.config.readonly || !this.config.newNode) return;
    const p = at ?? toCanvas(this.view, this.size.width / 2, this.size.height / 2);
    this.push("hakushi:drop", { item, x: round(p.x), y: round(p.y) });
  }

  private editLabel(id: string) {
    const edge = this.edges.get(id);
    const geometry = edge && this.geometry(edge);
    if (!edge || !geometry) return;
    const middle = edgePath(edge.path, geometry.from, geometry.fromSide, geometry.to, geometry.toSide).label;
    const input = el("input", { class: "hakushi-edge-input", type: "text", "aria-label": this.messages.t("label"), value: edge.label ?? "" });
    input.style.translate = `${middle.x}px ${middle.y}px`;
    this.labelsEl.append(input);
    input.focus();
    input.select();
    let done = false;
    const finish = (save: boolean) => {
      if (done) return;
      done = true;
      const value = input.value.trim();
      input.remove();
      this.root.focus({ preventScroll: true });
      if (save && value !== (edge.label ?? "")) this.push("hakushi:change", { op: "update", edges: [{ id, label: value || null }] });
    };
    input.addEventListener("keydown", (event) => {
      event.stopPropagation();
      if (event.key === "Enter") finish(true);
      if (event.key === "Escape") finish(false);
    });
    input.addEventListener("blur", () => finish(true));
    input.addEventListener("pointerdown", (event) => event.stopPropagation());
  }

  // -- Selection ---------------------------------------------------------------

  select(ids: string[]) {
    this.selectedEdges.clear();
    this.setSelection(new Set(ids));
    this.selectionChanged();
  }

  private toggleSelect(id: string) {
    const next = new Set(this.selected);
    if (next.has(id)) next.delete(id);
    else next.add(id);
    this.setSelection(next);
    this.selectionChanged();
  }

  private setSelection(ids: Set<string>) {
    this.layoutVersion++;
    const changed = new Set([...this.selected, ...ids]);
    this.selected = ids;
    for (const id of changed) {
      const node = this.nodes.get(id);
      if (node) this.decorate(node);
    }
    this.allDirty = true;
    this.schedule();
  }

  private selectionChanged() {
    this.allDirty = true;
    const n = this.selected.size + this.selectedEdges.size;
    if (n === 1 && this.selected.size === 1) {
      const node = this.nodes.get([...this.selected][0]);
      if (node) this.announce(this.messages.t("selectedOne", { name: node.label }));
    } else if (n > 1) {
      this.announce(this.messages.count("selected", n));
    }
    this.sendPeer();
    this.schedule();
  }

  /** The ids of the selected nodes, for the tests and the app. */
  getSelection(): string[] {
    return [...this.selected];
  }

  // -- Keyboard ----------------------------------------------------------------

  private focusIn(event: FocusEvent) {
    this.lastFocus = event.target as Element;
    const nodeEl = (event.target as Element).closest<HTMLElement>(".hakushi-node");
    if (!nodeEl || event.target !== nodeEl) return;
    const node = this.nodes.get(nodeEl.dataset.id || "");
    if (!node) return;
    node.el.setAttribute("aria-description", this.describe(node));
    if (!this.selected.has(node.id)) this.select([node.id]);
    this.revealNodes([node.id]);
  }

  // The connections of a node, in words, for screen readers.
  private describe(node: NodeModel): string {
    const edges = [...(this.byNode.get(node.id) ?? [])].map((id) => this.edges.get(id)!).filter(Boolean);
    if (!edges.length) return "";
    const names = edges.map((e) => {
      const other = this.nodes.get(e.source === node.id ? e.target : e.source);
      const arrow = e.source === node.id ? "→" : "←";
      return `${arrow} ${other?.label ?? ""}${e.label ? ` (${e.label})` : ""}`;
    });
    return `${this.messages.count("connections", edges.length)}: ${names.join(", ")}`;
  }

  private keyDown(event: KeyboardEvent) {
    if (event.defaultPrevented) return;
    if (event.key === "Tab" || event.key.startsWith("Arrow")) this.root.setAttribute("data-ui-keyboard", "");
    const target = event.target as HTMLElement;
    if (editable(target) || (target !== this.root && !target.classList.contains("hakushi-node") && interactive(target, this.root))) {
      // Escape from a field of a node goes back to the node.
      if (event.key === "Escape") {
        const node = target.closest<HTMLElement>(".hakushi-node");
        if (node) {
          event.preventDefault();
          node.focus();
        }
      }
      return;
    }
    const mod = isApple() ? event.metaKey : event.ctrlKey;
    const key = event.key;
    const g = this.gesture;

    if (g?.kind === "connect" && g.pointer === null) {
      this.connectKey(event, g);
      return;
    }

    if (key === " " && !this.space) {
      this.space = true;
      this.root.setAttribute("data-ui-space", "");
      event.preventDefault();
      return;
    }
    if (key === "Escape") {
      if (this.gesture) this.cancelGesture();
      else this.select([]);
      return;
    }
    if (key === "Tab") {
      this.tab(event);
      return;
    }
    if (mod && key.toLowerCase() === "z") {
      event.preventDefault();
      if (event.shiftKey) this.redo();
      else this.undo();
      return;
    }
    if (mod && key.toLowerCase() === "y") {
      event.preventDefault();
      this.redo();
      return;
    }
    if (mod && key.toLowerCase() === "a") {
      event.preventDefault();
      this.select([...this.order]);
      return;
    }
    if (mod && key.toLowerCase() === "c") return this.copy();
    if (mod && key.toLowerCase() === "x") return this.copy(true);
    if (mod && key.toLowerCase() === "v") {
      event.preventDefault();
      return this.paste();
    }
    if (mod && key.toLowerCase() === "d") {
      event.preventDefault();
      return this.duplicate();
    }
    if (mod && key === "0") {
      event.preventDefault();
      return this.zoomTo(1);
    }
    if (key === "Delete" || key === "Backspace") {
      event.preventDefault();
      return this.deleteSelection();
    }
    if (key === "+" || key === "=") return this.zoomBy(1.25);
    if (key === "-" || key === "_") return this.zoomBy(1 / 1.25);
    if (key === "!" || (event.shiftKey && event.code === "Digit1")) return this.fitAll();
    if (key === ")" || (event.shiftKey && event.code === "Digit0")) return this.zoomTo(1);
    if ((key === "c" || key === "C") && !mod && !event.altKey) {
      event.preventDefault();
      return this.startKeyboardConnect();
    }
    if (key === "Enter") {
      // Into the node: its first field or button.
      const node = this.focusedNode();
      const inner = node?.el.querySelector<HTMLElement>("input, textarea, select, button, a[href], [contenteditable], [tabindex]:not([tabindex='-1'])");
      if (inner) {
        event.preventDefault();
        inner.focus();
      }
      return;
    }
    if (key.startsWith("Arrow")) {
      event.preventDefault();
      if (event.altKey) return this.focusToward(key);
      if (this.selected.size && !this.config.readonly) return this.nudgeBy(key, event.shiftKey);
      const step = event.shiftKey ? 200 : 50;
      const d = { ArrowLeft: [step, 0], ArrowRight: [-step, 0], ArrowUp: [0, step], ArrowDown: [0, -step] }[key]!;
      this.view = { ...this.view, x: this.view.x + d[0], y: this.view.y + d[1] };
      this.schedule();
    }
  }

  private focusedNode(): NodeModel | undefined {
    const active = document.activeElement?.closest<HTMLElement>(".hakushi-node");
    return (active && this.nodes.get(active.dataset.id || "")) || (this.selected.size === 1 ? this.nodes.get([...this.selected][0]) : undefined);
  }

  // Tab and Shift+Tab go from node to node, in their order, and out of the canvas past the ends.
  private tab(event: KeyboardEvent) {
    const ids = this.order.filter((id) => !this.gone.has(id));
    if (!ids.length) return;
    const current = document.activeElement?.closest<HTMLElement>(".hakushi-node")?.dataset.id;
    const index = current ? ids.indexOf(current) : -1;
    const next = event.shiftKey ? (index === -1 ? -1 : index - 1) : index + 1;
    if (next < 0 || next >= ids.length) return;
    event.preventDefault();
    this.focusNode(ids[next]);
  }

  private focusNode(id: string) {
    const node = this.nodes.get(id);
    if (!node) return;
    this.culled.delete(id);
    node.el.removeAttribute("data-ui-culled");
    this.select([id]);
    this.revealNodes([id]);
    node.el.focus({ preventScroll: true });
  }

  // Alt and an arrow: the nearest node that way.
  private focusToward(key: string) {
    const from = this.focusedNode();
    if (!from) {
      if (this.order.length) this.focusNode(this.order[0]);
      return;
    }
    const c = this.center(from);
    const dir = { ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1] }[key]!;
    let best: { id: string; score: number } | null = null;
    for (const node of this.nodes.values()) {
      if (node.id === from.id || this.gone.has(node.id)) continue;
      const o = this.center(node);
      const along = (o.x - c.x) * dir[0] + (o.y - c.y) * dir[1];
      if (along <= 0) continue;
      const across = Math.abs((o.x - c.x) * dir[1] + (o.y - c.y) * dir[0]);
      const score = along + across * 2;
      if (!best || score < best.score) best = { id: node.id, score };
    }
    if (best) this.focusNode(best.id);
  }

  // The arrow keys move the selection; the moves of a burst of presses go as one change.
  private nudgeBy(key: string, shift: boolean) {
    const step = this.config.snap ? this.config.grid : shift ? 10 : 1;
    const d = { ArrowLeft: [-step, 0], ArrowRight: [step, 0], ArrowUp: [0, -step], ArrowDown: [0, step] }[key]!;
    if (!this.nudge) this.nudge = { origin: new Map(), timer: 0 };
    for (const id of this.selected) {
      const node = this.nodes.get(id);
      if (!node || node.locked) continue;
      if (!this.nudge.origin.has(id)) this.nudge.origin.set(id, { x: node.x, y: node.y });
      node.x = this.config.snap ? snapToGrid(node.x + d[0], step) : node.x + d[0];
      node.y = this.config.snap ? snapToGrid(node.y + d[1], step) : node.y + d[1];
      this.decorate(node);
      this.touchNode(id);
    }
    clearTimeout(this.nudge.timer);
    this.nudge.timer = window.setTimeout(() => {
      const origin = this.nudge!.origin;
      this.nudge = null;
      this.commitMove(origin);
    }, 400);
    this.revealNodes([...this.selected]);
    this.schedule();
  }

  // C: an edge from the focused node, to a node chosen with the arrow keys.
  private startKeyboardConnect() {
    if (this.config.readonly) return;
    const node = this.focusedNode();
    if (!node || node.locked) return;
    const sources = node.handles.filter((h) => h.kind !== "target");
    const g: Extract<Gesture, { kind: "connect" }> = {
      kind: "connect",
      pointer: null,
      from: { node: node.id, handle: sources[0]?.id ?? null },
      fromHandle: sources[0] ?? null,
      reverse: false,
      at: this.center(node),
      target: null,
    };
    const c = this.center(node);
    const choices = this.validTargets(g).sort((a, b) => {
      const pa = this.center(this.nodes.get(a.end.node)!);
      const pb = this.center(this.nodes.get(b.end.node)!);
      return Math.hypot(pa.x - c.x, pa.y - c.y) - Math.hypot(pb.x - c.x, pb.y - c.y);
    });
    if (!choices.length) {
      this.announce(this.messages.t("noTargets", { name: node.label }));
      return;
    }
    g.choices = choices;
    g.index = 0;
    g.target = choices[0];
    this.gesture = g;
    this.markTargets();
    this.announce(`${this.messages.t("connectStart", { name: node.label })} ${this.describeChoice(choices[0])}`);
    this.revealNodes([node.id, choices[0].end.node]);
    this.schedule();
  }

  private describeChoice(choice: { end: End; handle: Handle | null }): string {
    const node = this.nodes.get(choice.end.node);
    const name = `${node?.label ?? choice.end.node}${choice.handle?.id ? ` · ${choice.handle.el.getAttribute("aria-label") || choice.handle.id}` : ""}`;
    return this.messages.t("connectTo", { name });
  }

  private connectKey(event: KeyboardEvent, g: Extract<Gesture, { kind: "connect" }>) {
    const choices = g.choices ?? [];
    event.preventDefault();
    if (event.key === "Escape") {
      this.cancelGesture();
      this.announce(this.messages.t("connectCancelled"));
      return;
    }
    if (event.key === "Enter") {
      this.gesture = null;
      this.unmarkTargets();
      this.commitConnect(g);
      this.schedule();
      return;
    }
    const forward = ["ArrowRight", "ArrowDown", "Tab"].includes(event.key) && !(event.key === "Tab" && event.shiftKey);
    const back = ["ArrowLeft", "ArrowUp"].includes(event.key) || (event.key === "Tab" && event.shiftKey);
    if (!forward && !back) return;
    g.index = ((g.index ?? 0) + (forward ? 1 : -1) + choices.length) % choices.length;
    g.target = choices[g.index];
    this.root.querySelectorAll("[data-ui-target]").forEach((e) => e.removeAttribute("data-ui-target"));
    (g.target.handle?.el ?? this.nodes.get(g.target.end.node)?.el)?.setAttribute("data-ui-target", "");
    this.announce(this.describeChoice(g.target));
    this.revealNodes([g.target.end.node]);
    this.schedule();
  }

  private isOnScreen(id: string): boolean {
    const node = this.nodes.get(id);
    return !!node && intersects(visible(this.view, this.size.width, this.size.height), this.rect(node));
  }

  private revealNodes(ids: string[]) {
    const box = union(ids.map((id) => this.nodes.get(id)).filter((n): n is NodeModel => !!n).map((n) => this.rect(n)));
    if (!box) return;
    const next = reveal(this.view, box, this.size.width, this.size.height, 32);
    if (next !== this.view) {
      this.view = next;
      this.schedule();
    }
  }

  private announce(text: string) {
    if (!text) return;
    this.status.textContent = "";
    requestAnimationFrame(() => (this.status.textContent = text));
  }

  // -- Items dropped from outside ------------------------------------------------

  private itemDown(event: PointerEvent) {
    const item = (event.target as Element).closest?.<HTMLElement>(`[data-hakushi-item][data-hakushi-for="${CSS.escape(this.id)}"]`);
    if (!item || event.button !== 0 || this.config.readonly) return;
    event.preventDefault();
    const start = { x: event.clientX, y: event.clientY };
    let ghost: HTMLElement | null = null;
    const move = (e: PointerEvent) => {
      if (!ghost && Math.hypot(e.clientX - start.x, e.clientY - start.y) < CLICK_SLOP) return;
      if (!ghost) {
        ghost = item.cloneNode(true) as HTMLElement;
        ghost.classList.add("hakushi-ghost");
        ghost.removeAttribute("id");
        ghost.style.width = `${item.offsetWidth}px`;
        document.body.append(ghost);
      }
      ghost.style.translate = `${e.clientX + 8}px ${e.clientY + 8}px`;
      const rect = this.root.getBoundingClientRect();
      toggle(this.root, "data-ui-drop", e.clientX >= rect.left && e.clientX <= rect.right && e.clientY >= rect.top && e.clientY <= rect.bottom);
    };
    const up = (e: PointerEvent) => {
      document.removeEventListener("pointermove", move);
      document.removeEventListener("pointerup", up);
      document.removeEventListener("pointercancel", up);
      this.root.removeAttribute("data-ui-drop");
      const name = item.dataset.hakushiItem!;
      if (!ghost) {
        if (e.type === "pointerup") this.drop(name);
        return;
      }
      (ghost as HTMLElement).remove();
      const rect = this.root.getBoundingClientRect();
      if (e.type === "pointerup" && e.clientX >= rect.left && e.clientX <= rect.right && e.clientY >= rect.top && e.clientY <= rect.bottom) {
        this.bounds = rect;
        const at = this.canvasPoint(e);
        this.drop(name, this.config.snap ? { x: snapToGrid(at.x, this.config.grid), y: snapToGrid(at.y, this.config.grid) } : at);
      }
    };
    document.addEventListener("pointermove", move);
    document.addEventListener("pointerup", up);
    document.addEventListener("pointercancel", up);
  }

  private itemKey(event: KeyboardEvent) {
    if (event.key !== "Enter" && event.key !== " ") return;
    const item = (event.target as Element).closest?.<HTMLElement>(`[data-hakushi-item][data-hakushi-for="${CSS.escape(this.id)}"]`);
    if (!item) return;
    event.preventDefault();
    this.drop(item.dataset.hakushiItem!);
  }

  // -- The others ------------------------------------------------------------------

  setPeople(people: Person[]) {
    this.people = new Map(people.map((p) => [p.id, p]));
    for (const id of [...this.peers.keys()]) if (!this.people.has(id)) this.dropPeer(id);
    this.refreshPeers();
  }

  receivePeer(payload: Record<string, unknown>) {
    const id = String(payload.person);
    const peer = this.peers.get(id) ?? { cursor: null, selected: [], dragging: new Map(), seen: 0, el: null };
    const cursor = payload.cursor as [number, number] | null;
    peer.cursor = cursor ? { x: cursor[0], y: cursor[1] } : null;
    const before = new Set([...peer.selected, ...peer.dragging.keys()]);
    peer.selected = (payload.selected as string[]) ?? [];
    peer.dragging = new Map(((payload.dragging as [string, number, number][]) ?? []).map(([n, x, y]) => [n, { x, y }]));
    peer.seen = Date.now();
    this.peers.set(id, peer);
    for (const n of [...before, ...peer.selected, ...peer.dragging.keys()]) {
      const node = this.nodes.get(n);
      if (node) {
        this.decorate(node);
        this.touchNode(n);
      }
    }
    clearTimeout(this.peerTimer);
    this.peerTimer = window.setTimeout(() => this.expirePeers(), PEER_TIMEOUT);
    this.schedule();
  }

  private expirePeers() {
    const now = Date.now();
    for (const [id, peer] of this.peers) if (now - peer.seen >= PEER_TIMEOUT) this.dropPeer(id);
  }

  private dropPeer(id: string) {
    const peer = this.peers.get(id);
    if (!peer) return;
    peer.el?.remove();
    this.peers.delete(id);
    for (const n of [...peer.selected, ...peer.dragging.keys()]) {
      const node = this.nodes.get(n);
      if (node) {
        this.decorate(node);
        this.touchNode(n);
      }
    }
    this.schedule();
  }

  private refreshPeers() {
    for (const node of this.nodes.values()) if (node.el.hasAttribute("data-ui-peer")) this.decorate(node);
    for (const peer of this.peers.values()) {
      peer.el?.remove();
      peer.el = null;
    }
    this.schedule();
  }

  private drawPeers() {
    for (const [id, peer] of this.peers) {
      const person = this.people.get(id);
      if (!peer.cursor || !person) {
        if (peer.el) peer.el.hidden = true;
        continue;
      }
      if (!peer.el) {
        peer.el = el("div", { class: "hakushi-cursor" }, [el("span", {}, [person.name ?? person.id])]);
        peer.el.style.setProperty("--hakushi-peer", person.color);
        this.cursorsEl.append(peer.el);
      }
      peer.el.hidden = false;
      peer.el.style.translate = `${peer.cursor.x * this.view.zoom + this.view.x}px ${peer.cursor.y * this.view.zoom + this.view.y}px`;
    }
  }

  // The person's cursor, selection and drag, for the others: at most every PEER_INTERVAL.
  private sendPeer() {
    if (!this.config.live || !this.connected) return;
    const now = Date.now();
    const wait = PEER_INTERVAL - (now - this.peerSent);
    if (wait > 0) {
      if (!this.peerQueued) {
        this.peerQueued = true;
        window.setTimeout(() => {
          this.peerQueued = false;
          this.sendPeer();
        }, wait);
      }
      return;
    }
    this.peerSent = now;
    const g = this.gesture;
    const dragging = g?.kind === "drag" && g.moved ? [...g.origin.keys()].map((id) => [id, this.nodes.get(id)!.x, this.nodes.get(id)!.y]) : [];
    this.live.push("hakushi:peer", {
      cursor: this.pointer ? [round(this.pointer.x), round(this.pointer.y)] : null,
      selected: [...this.selected],
      dragging,
    });
  }

  private peerQueued = false;

  destroy() {
    for (const o of this.observers) o.disconnect();
    for (const cleanup of this.cleanups) cleanup();
    cancelAnimationFrame(this.frame);
    clearTimeout(this.noticeTimer);
    clearTimeout(this.peerTimer);
  }
}

function toggle(element: Element, name: string, on: boolean) {
  if (on && !element.hasAttribute(name)) element.setAttribute(name, "");
  else if (!on && element.hasAttribute(name)) element.removeAttribute(name);
}

function round(n: number): number {
  return Math.round(n * 100) / 100;
}
