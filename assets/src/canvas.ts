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

import { editable, el, interactive, isApple, numberAttr, prefersReducedMotion, svg } from "./dom";
import { contains, edgePath, facing, fromCorners, grow, intersects, sidePoint, union } from "./geometry";
import { exportImage, type ExportOptions } from "./export";
import { icons } from "./icons";
import { aspectResize, cropOf, dragCrop, fitImage, fullOf, imageAddress, rowAt, type Crop } from "./images";
import { FLAT, inkBox, inside, outline, simplify, streamline, type InkPoint, type InkStroke } from "./ink";
import { layout as place, type Algorithm } from "./layout";
import { Messages } from "./messages";
import { Minimap } from "./minimap";
import { check } from "./rules";
import { align, snapToGrid, type Guide } from "./snap";
import type { Config, EdgeModel, End, Handle, HandleKind, Live, NodeModel, Person, Point, Rect, Side, Tool, View } from "./types";
import { centerOn, clamp, fit, readableView, reveal, toCanvas, visible, zoomAt } from "./view";

// The smallest zoom a canvas that should be read (fit "readable") opens at.
const READABLE_ZOOM = 0.6;
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
// The most nodes, and edges, of what a person sees that go to the room.
const SEEN_MAX = 200;
// The most points of a line being drawn that go to the others (the server
// takes no more).
const INK_SENT_MAX = 1_400;
// How far from the line a point of a stroke may be left out when the pen
// lifts, in pixels of the screen.
const INK_TOLERANCE = 0.6;

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
  | { kind: "box"; pointer: number; start: Point; end: Point; base: Set<string>; within: Set<string> }
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
      // An end of an edge dragged to another handle: the edge.
      reconnect?: string;
    }
  // A node resized by a corner or a side; an image (`data-hakushi-aspect`) keeps its aspect ratio, unless Shift.
  | { kind: "resize"; pointer: number; id: string; corner: string; start: Point; rect: Rect; aspect: number | null }
  // A line drawn with a tool of a kit (ink), the strokes an eraser passes over, a lasso.
  | { kind: "ink"; pointer: number; tool: Tool; stroke: InkStroke; pen: boolean }
  | { kind: "erase"; pointer: number; tool: Tool; last: Point; hit: Set<string> }
  | { kind: "lasso"; pointer: number; points: Point[]; base: Set<string> }
  // A shape drawn as a box (Shift: as wide as high), or a line from a point to a point.
  | { kind: "shape"; pointer: number; tool: Tool; start: Point; end: Point; square: boolean }
  // A node turned by its knob, about its middle.
  | { kind: "rotate"; pointer: number; id: string; center: Point; from: number; base: number; deg: number; el: HTMLElement }
  | { kind: "pinch"; distance: number; mid: Point; view: View };

interface EdgeView {
  g: SVGGElement;
  line: SVGPathElement;
  hit: SVGPathElement;
  label: HTMLElement | null;
  shown: boolean;
  // Around the path: to cull it.
  box: Rect;
  // What its path and marker were last written as.
  d: string;
  marker: string | null;
}

interface Peer {
  cursor: Point | null;
  // What their canvas shows, in the canvas's terms ([x, y, width, height]), for those who follow them.
  view: [number, number, number, number] | null;
  selected: string[];
  dragging: Map<string, Point>;
  seen: number;
  el: HTMLElement | null;
  // Where the cursor and the dragged nodes come from: each browser draws the
  // way to where a person (an agent, a jump) said they went.
  from: Point | null;
  dragFrom: Map<string, Point>;
  start: number;
  duration: number;
  // Their pointer is on this canvas on a page of the room with Issho's
  // pointers, which draw it there.
  paged?: boolean;
  // The line they draw, as they draw it.
  ink: InkStroke | null;
  // The files they upload: a box and a progress each, and their placeholders.
  files: number[][];
  fileEls: HTMLElement[];
}

// The canvas of a room this person uses last (it has their pointer, a
// press, the focus), when one page shows a canvas twice (an embed, again):
// that one says where they are in it, and its copies say nothing.
const activeIn = new Map<string, Canvas>();

// The way to a new place: longer the farther it goes, never longer than this.
const GLIDE_MAX = 400;
// A view still for this long has come to rest, and the app hears of it (`on_viewport`).
const VIEW_REST = 300;
const ease = (t: number): number => 1 - (1 - t) ** 3;

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
  // Above the nodes: the edges of the selected nodes, a selected edge, and
  // the overlay (the knobs of a selected edge, an edge being drawn).
  private raisedG: SVGGElement;
  private overlay: SVGGElement;
  private ui: HTMLElement;
  private status: HTMLElement;
  private boxEl: HTMLElement;
  private cursorsEl: HTMLElement;
  private controlsEl: HTMLElement | null = null;
  private zoomLabel: HTMLElement | null = null;
  private minimap: Minimap | null = null;

  private view: View = { x: 0, y: 0, zoom: 1 };
  // The way the view goes to where the app sent it (`Hakushi.Live.fit/2`, `focus/3`).
  // It gives way when anything else moves the view (`last` is the view it set).
  private viewGlide: { from: View; to: View; start: number; duration: number; last: View } | null = null;
  // A move of the view the app sent before the canvas had a size, made when it has one.
  private pendingMove: Record<string, unknown> | null = null;
  // What the app last heard of the selection and of the view (`on_select`, `on_viewport`).
  private reportedSelection = JSON.stringify([[], []]);
  private reportedView = "";
  private viewTimer = 0;
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
  private parentsChanged = false;
  // Changes whenever a node moves, comes, goes or is selected: for the minimap.
  private layoutVersion = 0;
  private boundsVersion = -1;
  private allBounds: Rect | null = null;
  private drawnView: View | null = null;
  private panTimer = 0;
  // Issho: the canvas's document on the page, its room, and whom the room
  // follows (Issho's following: the canvas shows what they show).
  private docEl: HTMLElement | null = null;
  private room = "";
  private followKey: string | null = null;
  private followedAt = "";
  private culledVersion = -1;
  private culledView: View | null = null;
  // The tools of the kits: the one chosen (null: the pointer), the colour
  // and width of each drawing tool, and whether a pen was used (then touch
  // pans, and only the pen draws).
  private tool: Tool | null = null;
  private toolsEl: HTMLElement | null = null;
  private inkPrefs = new Map<string, { color: string; size: number }>();
  private penSeen = false;
  // The lines being drawn: this person's, theirs drawn until they are
  // nodes, and the others'.
  private inkG: SVGGElement;
  private inkPaths = new Map<string, { path: SVGPathElement; stroke: InkStroke; length: number }>();
  private inkPending: { key: string; stroke: InkStroke; id: string | null }[] = [];
  private inkSeq = 0;

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
    // The edges' layer is the engine's to keep or not (see .hakushi-edges).
    if (webkit()) root.setAttribute("data-ui-webkit", "");
    this.ui = this.part("-ui");

    this.edgesSvg.append(this.defs());
    this.edgesG = svg("g", { class: "hakushi-edge-lines" });
    this.overlay = svg("g", { class: "hakushi-overlay" });
    this.raisedG = svg("g", { class: "hakushi-edge-lines" });
    this.inkG = svg("g", { class: "hakushi-ink-live" });
    const raisedSvg = root.querySelector<SVGSVGElement>(`#${CSS.escape(this.id)}-svg-raised`);
    if (raisedSvg) {
      this.edgesSvg.append(this.edgesG);
      raisedSvg.append(this.raisedG, this.inkG, this.overlay);
    } else {
      this.edgesSvg.append(this.edgesG, this.raisedG, this.inkG, this.overlay);
    }

    this.status = el("div", { class: "hakushi-status", role: "status", "aria-live": "polite" });
    this.boxEl = el("div", { class: "hakushi-box", hidden: "" });
    this.cursorsEl = el("div", { class: "hakushi-cursors", "aria-hidden": "true" });
    this.ui.append(this.cursorsEl, this.boxEl, this.status);
    this.buildControls();
    this.buildTools();

    this.readNodes();
    this.readEdges();
    this.tidying = this.config.tidy === true && !this.config.live;
    if (!this.tidying) this.root.setAttribute("data-ui-tidied", "");
    this.observe();
    this.listen();
    this.measureRoot();
    this.joinPage();
    this.schedule();
  }

  // -- Issho's page ---------------------------------------------------------
  //
  // The canvas's part in Issho's page, by its contracts (no import of
  // Issho's script): where a place of the canvas is on the screen (a point,
  // a node), for Issho's pointers (`locate`); what point is under the
  // pointer (`point`), so that a person's pointer is a point of the canvas,
  // drawn where it is on each screen; and following, the room's.

  private joinPage() {
    this.docEl = this.root.closest<HTMLElement>("[data-issho-doc]");
    const doc = this.docEl?.dataset.isshoDoc;
    if (!this.docEl || !doc) return;
    this.room = doc.split("/")[0];
    // The copy of this canvas the person uses says where they are in it.
    const use = () => activeIn.set(this.room, this);
    for (const type of ["pointerenter", "pointerdown", "focusin"] as const) this.root.addEventListener(type, use, { passive: true });
    this.cleanups.push(() => {
      for (const type of ["pointerenter", "pointerdown", "focusin"] as const) this.root.removeEventListener(type, use);
      if (activeIn.get(this.room) === this) activeIn.delete(this.room);
    });
    const element = this.docEl as unknown as Record<symbol, unknown>;
    const locator = (at: unknown) => this.locatePlace(at);
    const pointer = (x: number, y: number) => this.pointAt(x, y);
    element[Symbol.for("issho.locator")] = locator;
    element[Symbol.for("issho.point")] = pointer;
    const forget = () => {
      if (element[Symbol.for("issho.locator")] === locator) delete element[Symbol.for("issho.locator")];
      if (element[Symbol.for("issho.point")] === pointer) delete element[Symbol.for("issho.point")];
    };
    // A canvas that takes no part in following (follow={false}): its pointers, and no more.
    if (this.config.follow === false) {
      this.cleanups.push(forget);
      return;
    }
    const onFollowing = (event: Event) => {
      const detail = (event as CustomEvent<{ room?: string; key?: string | null }>).detail;
      if (detail?.room === this.room) this.followPerson(detail.key ?? null);
    };
    document.addEventListener("issho:following", onFollowing);
    // Going one's own way on the canvas (a wheel, a press, a key) stops following.
    const ownWay = (event: Event) => {
      if (!this.followKey || !event.isTrusted) return;
      if ((event.target as Element | null)?.closest?.("[data-issho-follow-control]")) return;
      if (event instanceof KeyboardEvent && ["Shift", "Control", "Alt", "Meta", "Tab"].includes(event.key)) return;
      followIn(this.room, null);
    };
    const types = ["wheel", "pointerdown", "keydown"] as const;
    for (const type of types) this.root.addEventListener(type, ownWay, { capture: true, passive: true });
    // Its avatars follow someone, or stop.
    const onAvatar = (event: Event) => {
      const button = (event.target as Element | null)?.closest?.<HTMLElement>(".hakushi-person[data-person]");
      if (!button || !this.root.contains(button)) return;
      const key = button.dataset.person!;
      followIn(this.room, followingIn(this.room) === key ? null : key);
    };
    this.root.addEventListener("click", onAvatar);
    this.cleanups.push(() => {
      forget();
      document.removeEventListener("issho:following", onFollowing);
      for (const type of types) this.root.removeEventListener(type, ownWay, { capture: true });
      this.root.removeEventListener("click", onAvatar);
    });
    this.followPerson(followingIn(this.room));
  }

  // A place of the canvas on the screen: a point, or a node.
  private locatePlace(at: unknown): DOMRect | null {
    const place = at as { point?: [number, number]; node?: string; nodes?: string[] } | null;
    const rect = this.root.getBoundingClientRect();
    if (place?.point && place.point.length === 2) {
      const [x, y] = place.point;
      return new DOMRect(rect.left + x * this.view.zoom + this.view.x, rect.top + y * this.view.zoom + this.view.y, 0, 0);
    }
    const id = place?.node ?? place?.nodes?.[0];
    const node = id ? this.nodes.get(id) : undefined;
    if (!node) return null;
    const at2 = this.placeOf(node);
    return new DOMRect(
      rect.left + at2.x * this.view.zoom + this.view.x,
      rect.top + at2.y * this.view.zoom + this.view.y,
      node.width * this.view.zoom,
      node.height * this.view.zoom,
    );
  }

  // The point of the canvas under a point of the screen.
  private pointAt(clientX: number, clientY: number): { point: [number, number] } | null {
    const rect = this.root.getBoundingClientRect();
    if (clientX < rect.left || clientX > rect.right || clientY < rect.top || clientY > rect.bottom) return null;
    const round = (value: number) => Math.round(value * 10) / 10;
    return { point: [round((clientX - rect.left - this.view.x) / this.view.zoom), round((clientY - rect.top - this.view.y) / this.view.zoom)] };
  }

  // Whom the room follows: their avatar is pressed, and the canvas shows
  // what they show.
  private followPerson(key: string | null) {
    if (key !== this.followKey) this.followScrolled = null;
    this.followKey = key;
    this.followedAt = "";
    for (const avatar of this.root.querySelectorAll<HTMLElement>(".hakushi-person[data-person]")) {
      avatar.setAttribute("aria-pressed", String(avatar.dataset.person === key));
    }
    this.drawFollowing();
    const peer = key ? this.peers.get(key) : undefined;
    if (peer) this.showFollowed(peer);
  }

  // Whom the room follows, when they are on this canvas and it shows its
  // people (its avatars): "Following Ada", with Stop, in their colour, and
  // a ring of it around the canvas.
  private drawFollowing() {
    const key = this.followKey;
    const avatar = key ? [...this.root.querySelectorAll<HTMLElement>("[data-hakushi-people] .hakushi-person[data-person]")].find((a) => a.dataset.person === key) : undefined;
    let line = this.ui.querySelector<HTMLElement>(":scope > .hakushi-following");
    const ring = this.ui.querySelector<HTMLElement>(":scope > .hakushi-following-ring");
    if (!avatar || !key) {
      line?.remove();
      ring?.remove();
      this.root.removeAttribute("data-ui-following");
      this.root.style.removeProperty("--hakushi-follow-color");
      return;
    }
    const color = avatar.style.getPropertyValue("--hakushi-person").trim();
    if (color) this.root.style.setProperty("--hakushi-follow-color", color);
    this.root.setAttribute("data-ui-following", "");
    if (!ring) this.ui.prepend(el("div", { class: "hakushi-following-ring", "aria-hidden": "true" }));
    const name = avatar.title || key;
    if (line?.dataset.followed === key && line.dataset.name === name) return;
    // Issho's look of following (its classes and properties), the same on every block of the page.
    line ??= this.ui.appendChild(el("p", { class: "hakushi-following issho-following", role: "status", "data-issho-follow-control": "" }));
    if (color) line.style.setProperty("--issho-color", color);
    line.dataset.followed = key;
    line.dataset.name = name;
    const text = el("span", {});
    text.textContent = this.messages.t("following", { name });
    const stop = el("button", { type: "button", class: "hakushi-following-stop issho-following-stop" });
    stop.textContent = this.messages.t("stopFollowing", {});
    stop.addEventListener("click", () => followIn(this.room, null));
    line.replaceChildren(text, stop);
  }

  // The followed person's view, when their canvas shares it (a person's);
  // else their pointer kept on the screen (an agent's).
  private showFollowed(peer: Peer) {
    if (peer.view) {
      const where = peer.view.join(",");
      if (where === this.followedAt) return;
      this.followedAt = where;
      const [x, y, w, h] = peer.view;
      const zoom = clamp(Math.min(this.size.width / w, this.size.height / h), this.config.minZoom, this.config.maxZoom);
      this.setView({ zoom, x: this.size.width / 2 - (x + w / 2) * zoom, y: this.size.height / 2 - (y + h / 2) * zoom });
      this.keepOnScreen();
      return;
    }
    if (!peer.cursor) return;
    this.keepOnScreen();
    const sx = peer.cursor.x * this.view.zoom + this.view.x;
    const sy = peer.cursor.y * this.view.zoom + this.view.y;
    const margin = 48;
    if (sx >= margin && sy >= margin && sx <= this.size.width - margin && sy <= this.size.height - margin) return;
    this.setView({ x: this.size.width / 2 - peer.cursor.x * this.view.zoom, y: this.size.height / 2 - peer.cursor.y * this.view.zoom });
  }

  // A canvas in a page (an embed in a document) that follows someone comes
  // into view once, when it is off the screen: the page then scrolls as
  // the person who follows likes.
  private keepOnScreen() {
    if (this.followScrolled === this.followKey) return;
    this.followScrolled = this.followKey;
    const rect = this.root.getBoundingClientRect();
    if (rect.bottom > 0 && rect.top < document.documentElement.clientHeight) return;
    this.root.scrollIntoView({ block: "nearest", behavior: reducedMotion() ? "auto" : "smooth" });
  }

  private followScrolled: string | null = null;

  /** Whether people move the nodes: on a canvas they edit, or one they only arrange. */
  private get arranges(): boolean {
    return !this.config.readonly || this.config.arrange === true;
  }

  private part(suffix: string): HTMLElement {
    return this.root.querySelector<HTMLElement>(`#${CSS.escape(this.id + suffix)}`)!;
  }

  private readConfig() {
    this.config = JSON.parse(this.hookEl.dataset.config || "{}") as Config;
    this.messages = new Messages(this.config.messages || {}, this.config.locale || "en");
    this.root.toggleAttribute("data-ui-readonly", this.config.readonly);
    this.root.toggleAttribute("data-ui-arrange", this.arranges);
    this.root.dataset.uiWheel = this.config.wheel;
  }

  // -- The server's renders -------------------------------------------------

  /** After a render of the server: the config, the notice. */
  update() {
    this.minimap?.refresh();
    this.layoutVersion++;
    const minimap = this.config.minimap;
    const controls = this.config.controls;
    const tools = JSON.stringify(this.config.tools ?? []) + this.config.readonly + this.arranges;
    const papers = JSON.stringify(this.config.papers ?? []);
    const grid = this.config.grid;
    this.readConfig();
    // Another size of squares: the paper is drawn again at once.
    if (grid !== this.config.grid) this.drawnView = null;
    if (minimap !== this.config.minimap || controls !== this.config.controls || papers !== JSON.stringify(this.config.papers ?? [])) {
      this.togglePaperMenu(false);
      this.toggleLayoutMenu(false);
      this.buildControls();
    }
    if (tools !== JSON.stringify(this.config.tools ?? []) + this.config.readonly + this.arranges) {
      this.buildTools();
      this.toggleLayoutMenu(false);
      this.buildControls();
    }
    this.drawPaperMenu();
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
    const read: NodeModel[] = [];
    for (const element of this.nodesEl.children) {
      if (element instanceof HTMLElement && element.classList.contains("hakushi-node")) this.readNode(element, read);
    }
    for (const node of read) this.decorate(node);
  }

  // A node's size and handles, read from the page. With `later`, the node is
  // decorated by the caller once all of them are read: a write between two
  // reads lays the page out again, for each node of a large canvas.
  private readNode(element: HTMLElement, later?: NodeModel[]): NodeModel | null {
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
      parent: element.dataset.parent || null,
      group: element.dataset.group === "true",
      label: element.getAttribute("aria-label") || id,
      handles: old && old.el === element ? old.handles : [],
      faint: element.querySelector("[data-hakushi-faint]") !== null,
      measured: false,
      el: element,
    };
    this.nodes.set(id, node);
    if (!old) this.order.push(id);
    // A file's node, which its placeholder waits for.
    const wait = old ? undefined : this.nodeWaits.get(id);
    if (wait) {
      this.nodeWaits.delete(id);
      queueMicrotask(wait);
    }
    // A node in another group: the nodes in it are deeper or shallower too.
    if (old && (old.parent !== node.parent || old.group !== node.group)) this.parentsChanged = true;
    this.measureHandles(node);
    if (later) later.push(node);
    else this.decorate(node);
    this.thumbs(element);
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
    // Groups under their nodes, deeper groups over shallower ones.
    const lifted = this.gesture?.kind === "drag" && this.gesture.moved && this.gesture.origin.has(node.id);
    // Dragged nodes over every other, groups or not, until they land.
    const z = lifted ? String(10_000 + this.depth(node) * 3 + (node.group ? 0 : 1)) : String(this.depth(node) * 3 + (node.group ? 0 : 1) + (this.selected.has(node.id) ? 1 : 0));
    if (element.style.zIndex !== z) element.style.zIndex = z;
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
    // The knob of a node that turns (`data-hakushi-rotate`), when it is the one selected.
    const turns = this.selected.size === 1 && this.selected.has(node.id) && !this.config.readonly && !node.locked && element.querySelector("[data-hakushi-rotate]") !== null;
    const knob = element.querySelector(":scope > .hakushi-rotator");
    if (turns && !knob) element.append(el("span", { class: "hakushi-rotator", "aria-hidden": "true", title: this.messages.t("shapeRotate") }));
    else if (!turns && knob) knob.remove();
  }

  // The corners and the sides of a node that resizes, to drag.
  private addResizers(node: NodeModel) {
    if (node.el.querySelector(":scope > .hakushi-resizer")) return;
    for (const corner of ["nw", "ne", "sw", "se", "n", "e", "s", "w"]) {
      node.el.append(el("span", { class: "hakushi-resizer", "data-corner": corner, "aria-hidden": "true" }));
    }
  }

  // How many groups a node is in.
  private depth(node: NodeModel): number {
    let depth = 0;
    let parent = node.parent;
    while (parent && depth < 50) {
      depth++;
      parent = this.nodes.get(parent)?.parent ?? null;
    }
    return depth;
  }

  /** The nodes of the ids, and the nodes in them, all the way down. */
  private withDescendants(ids: Iterable<string>): Set<string> {
    const all = new Set(ids);
    let grew = true;
    while (grew) {
      grew = false;
      for (const node of this.nodes.values()) {
        if (node.parent && all.has(node.parent) && !all.has(node.id)) {
          all.add(node.id);
          grew = true;
        }
      }
    }
    return all;
  }

  // The innermost group under a point, but those of `except`.
  private groupAt(p: Point, except: Set<string>): NodeModel | null {
    let best: NodeModel | null = null;
    let bestDepth = -1;
    for (const node of this.nodes.values()) {
      if (!node.group || except.has(node.id) || this.gone.has(node.id)) continue;
      if (!contains(this.rect(node), p)) continue;
      const depth = this.depth(node);
      if (depth > bestDepth) {
        best = node;
        bestDepth = depth;
      }
    }
    return best;
  }

  // The place a node shows at: its own, or where a person drags it (on its way there).
  private placeOf(node: NodeModel): Point {
    for (const peer of this.peers.values()) {
      const at = peer.dragging.get(node.id);
      if (at && !(this.gesture?.kind === "drag" && this.gesture.origin.has(node.id))) return this.onTheWay(peer, peer.dragFrom.get(node.id) ?? at, at);
    }
    return { x: node.x, y: node.y };
  }

  // A point on the way from one place to another, now.
  private onTheWay(peer: Peer, from: Point, to: Point): Point {
    const t = peer.duration > 0 ? Math.min(1, (performance.now() - peer.start) / peer.duration) : 1;
    const e = ease(t);
    return { x: from.x + (to.x - from.x) * e, y: from.y + (to.y - from.y) * e };
  }

  private moving(peer: Peer): boolean {
    return peer.duration > 0 && performance.now() - peer.start < peer.duration;
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
    // The page's theme changes (an attribute or class on <html> or <body>,
    // or the system's scheme): the minimap reads its colors again.
    const theme = new MutationObserver(() => this.themeChanged());
    const watched = { attributes: true, attributeFilter: ["class", "style", "data-theme"] };
    theme.observe(document.documentElement, watched);
    if (document.body) theme.observe(document.body, watched);
    this.observers.push(nodes, edges, sizes, notices, theme);
    this.scheme = typeof matchMedia === "function" ? matchMedia("(prefers-color-scheme: dark)") : null;
    this.scheme?.addEventListener("change", this.onScheme);
  }

  private scheme: MediaQueryList | null = null;
  private onScheme = () => this.themeChanged();

  private themeChanged() {
    if (!this.minimap) return;
    this.minimap.refresh();
    this.schedule();
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
      if (target?.closest(".hakushi-resizer, .hakushi-rotator")) continue;
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
      // A selected node that went is no longer selected, for the app too.
      this.reportSelection();
    }
    const read: NodeModel[] = [];
    let added = false;
    for (const element of touched) {
      const fresh = !this.nodes.has(element.dataset.id || "");
      const node = this.readNode(element, read);
      if (node && fresh) {
        this.sizes.observe(element);
        added = true;
      }
    }
    if (added) this.order = [...this.nodesEl.children].map((n) => (n as HTMLElement).dataset.id!).filter((id) => this.nodes.has(id));
    if (this.parentsChanged) {
      this.parentsChanged = false;
      for (const node of this.nodes.values()) this.decorate(node);
    } else {
      for (const node of read) this.decorate(node);
    }
    this.allDirty = true;
    this.layoutVersion++;
    if (this.pendingSelect) this.selectPending();
    // A text drawn with its tool: written at once.
    if (this.editOnArrive && this.nodes.has(this.editOnArrive)) {
      const node = this.nodes.get(this.editOnArrive)!;
      this.editOnArrive = null;
      requestAnimationFrame(() => this.editText(node));
    }
    if (this.styleEl) this.drawStylePanel();
    // A stroke of this person's is a node now: drawn by it.
    if (this.inkPending.some((p) => p.id && this.nodes.has(p.id))) this.inkPending = this.inkPending.filter((p) => !(p.id && this.nodes.has(p.id)));
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
      this.reportSelection();
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
      if (this.tidying) return this.startTidy();
      this.fitted = true;
      this.view = this.config.fit && this.nodes.size ? this.openingView() : { x: 40, y: 40, zoom: 1 };
    }
    if (this.pendingMove && this.size.width > 0) {
      const move = this.pendingMove;
      this.pendingMove = null;
      this.moveView({ ...move, animate: false });
    }
    if (this.viewGlide) this.stepGlide();
    const viewChanged = this.view !== this.drawnView;
    if (viewChanged) {
      // While a pan goes on, the world is a layer of its own, whose pixels
      // move; not while it zooms, which would scale them and blur the text.
      const panned = this.drawnView?.zoom === this.view.zoom;
      clearTimeout(this.panTimer);
      this.world.style.willChange = panned ? "transform" : "";
      if (panned) this.panTimer = window.setTimeout(() => (this.world.style.willChange = ""), 200);
      this.drawnView = this.view;
      // What this canvas shows goes to those who follow this person.
      if (this.docEl) this.sendPeer();
      this.world.style.transform = `translate(${this.view.x}px, ${this.view.y}px) scale(${this.view.zoom})`;
      // The paper moves by less than a period of its pattern (five squares,
      // for graph paper), as a layer: a pan paints none of it again.
      const size = this.config.grid * this.view.zoom;
      const period = size * 5;
      const bg = this.viewportEl.style;
      bg.setProperty("--hakushi-grid-size", `${size}px`);
      bg.setProperty("--hakushi-grid-x", `${((this.view.x % period) + period) % period}px`);
      bg.setProperty("--hakushi-grid-y", `${((this.view.y % period) + period) % period}px`);
      if (this.config.reportView && !this.viewGlide) {
        clearTimeout(this.viewTimer);
        this.viewTimer = window.setTimeout(() => this.reportView(), VIEW_REST);
      }
      const far = this.view.zoom < 0.5 ? "far" : "near";
      if (this.root.dataset.uiZoom !== far) {
        this.root.dataset.uiZoom = far;
        this.thumbs(this.nodesEl);
      }
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
    this.drawInk();
    this.drawPeers();
    this.reportSeen();
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
        // for each node that comes into view. Nor is it news: its place,
        // size and edges are as they were, and a change of the layout here
        // would cull all of them again on the next frame, and the next.
        if (!node.measured) unmeasured.push(node);
      } else {
        this.culled.add(node.id);
        node.el.setAttribute("data-ui-culled", "");
      }
    }
    for (const node of unmeasured) {
      this.measureHandles(node);
      this.touchNode(node.id);
    }
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
      // Written only when they change: a path written again is laid out and painted again.
      if (view.d !== path.d) {
        view.d = path.d;
        view.line.setAttribute("d", path.d);
        view.hit.setAttribute("d", path.d);
      }
      // A selected edge, and the edges of the selected nodes, are drawn
      // above the nodes, in the colour of a selection: where an edge passes
      // under another node, it is seen going to its own end.
      const raised = this.raisedEdge(edge);
      const layer = raised ? this.raisedG : this.edgesG;
      if (view.g.parentNode !== layer) layer.append(view.g);
      toggle(view.g, "data-ui-connected", raised && !this.selectedEdges.has(id));
      const marker = edge.marker === "none" ? "" : `url(#${this.id}-${edge.marker}${raised ? "-on" : ""})`;
      if (view.marker !== marker) {
        view.marker = marker;
        view.line.setAttribute("marker-end", marker);
      }
      toggle(view.g, "data-ui-selected", this.selectedEdges.has(id));
      const g = this.gesture;
      toggle(view.g, "data-ui-gone", this.gone.has(id) || (g?.kind === "connect" && g.reconnect === id));
      toggle(view.g, "data-animated", edge.animated);
      toggle(view.g, "data-ui-faint", !!(this.nodes.get(edge.source)?.faint || this.nodes.get(edge.target)?.faint));
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
      if (!viewChanged) this.showEdge(view, all || intersects(view.box, area) || raised);
    }
    if (viewChanged) {
      for (const [id, view] of this.edgeViews) {
        const edge = this.edges.get(id);
        this.showEdge(view, all || intersects(view.box, area) || (!!edge && this.raisedEdge(edge)));
      }
    }
    this.dirty.clear();
    this.allDirty = false;
  }

  // What this person sees of a shared canvas, for an agent of the room,
  // which reads the graph and not the screen: the nodes on the screen
  // (their boxes, in the canvas's terms) and the nodes each edge there
  // passes under, which hide that part of it ("the line from the note
  // seems to end at the green note; it goes on under it to the card").
  // At most every second, when the layout or the view changed.
  private seenTimer = 0;
  private seenAt = "";
  private sentSeen = "";

  private reportSeen() {
    if (!this.config.live || !this.connected || !this.docEl || this.seenTimer) return;
    const at = `${this.layoutVersion} ${Math.round(this.view.x)} ${Math.round(this.view.y)} ${this.view.zoom.toFixed(3)} ${this.edges.size}`;
    if (at === this.seenAt) return;
    this.seenTimer = window.setTimeout(() => {
      this.seenTimer = 0;
      this.seenAt = at;
      const seen = this.seen();
      const json = JSON.stringify(seen);
      if (json === this.sentSeen) return;
      this.sentSeen = json;
      this.live.push("hakushi:seen", seen);
    }, 1_000);
  }

  private seen(): { nodes: Record<string, number[]>; edges: Record<string, { under: string[] }> } {
    const area = visible(this.view, this.size.width, this.size.height);
    const boxes = new Map<string, Rect>();
    for (const id of this.order) {
      if (boxes.size >= SEEN_MAX) break;
      const node = this.nodes.get(id);
      if (!node) continue;
      const box = this.rect(node);
      if (intersects(box, area)) boxes.set(id, box);
    }
    const nodes: Record<string, number[]> = {};
    for (const [id, box] of boxes) nodes[id] = [Math.round(box.x), Math.round(box.y), Math.round(box.width), Math.round(box.height)];
    const edges: Record<string, { under: string[] }> = {};
    let count = 0;
    for (const [id, view] of this.edgeViews) {
      if (count >= SEEN_MAX) break;
      const edge = this.edges.get(id);
      if (!edge || !view.shown || !intersects(view.box, area)) continue;
      // The nodes over the line (not its ends, nor the groups around them,
      // which are drawn under it): a few points along it, in each box.
      const ends = new Set([edge.source, edge.target, ...this.ancestors(edge.source), ...this.ancestors(edge.target)]);
      const over = [...boxes].filter(([nid, box]) => !ends.has(nid) && !this.nodes.get(nid)?.group && intersects(box, view.box));
      if (over.length === 0) continue;
      const length = view.line.getTotalLength();
      const steps = Math.min(64, Math.max(8, Math.ceil(length / 12)));
      const under = new Set<string>();
      for (let i = 1; i < steps; i++) {
        const p = view.line.getPointAtLength((length * i) / steps);
        for (const [nid, box] of over) if (p.x > box.x + 2 && p.x < box.x + box.width - 2 && p.y > box.y + 2 && p.y < box.y + box.height - 2) under.add(nid);
      }
      if (under.size > 0) {
        edges[id] = { under: [...under] };
        count++;
      }
    }
    return { nodes, edges };
  }

  private ancestors(id: string): string[] {
    const found: string[] = [];
    for (let parent = this.nodes.get(id)?.parent; parent && found.length < 32; parent = this.nodes.get(parent)?.parent) found.push(parent);
    return found;
  }

  /** A selected edge, or an edge of a selected node: drawn above the nodes. */
  private raisedEdge(edge: EdgeModel): boolean {
    return this.selectedEdges.has(edge.id) || this.selected.has(edge.source) || this.selected.has(edge.target);
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
      view = { g, line, hit, label: null, shown: true, box: { x: 0, y: 0, width: 0, height: 0 }, d: "", marker: null };
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
    if (g?.kind === "shape") {
      if (g.tool.mode === "line") {
        this.overlay.append(svg("line", { class: "hakushi-shape-preview", x1: `${g.start.x}`, y1: `${g.start.y}`, x2: `${g.end.x}`, y2: `${g.end.y}`, "vector-effect": "non-scaling-stroke" }));
      } else {
        const b = this.shapeBox(g);
        const shape =
          g.tool.tool === "ellipse"
            ? svg("ellipse", { cx: `${b.x + b.width / 2}`, cy: `${b.y + b.height / 2}`, rx: `${b.width / 2}`, ry: `${b.height / 2}` })
            : g.tool.tool === "diamond"
              ? svg("polygon", { points: `${b.x + b.width / 2},${b.y} ${b.x + b.width},${b.y + b.height / 2} ${b.x + b.width / 2},${b.y + b.height} ${b.x},${b.y + b.height / 2}` })
              : g.tool.tool === "triangle"
                ? svg("polygon", { points: `${b.x + b.width / 2},${b.y} ${b.x + b.width},${b.y + b.height} ${b.x},${b.y + b.height}` })
                : svg("rect", { x: `${b.x}`, y: `${b.y}`, width: `${b.width}`, height: `${b.height}`, rx: g.tool.tool === "text" ? "0" : "6" });
        shape.setAttribute("class", "hakushi-shape-preview");
        shape.setAttribute("vector-effect", "non-scaling-stroke");
        this.overlay.append(shape);
      }
    }
    if (g?.kind === "lasso" && g.points.length > 1) {
      const d = g.points.map((p, i) => `${i === 0 ? "M" : "L"}${round(p.x)} ${round(p.y)}`).join("") + "Z";
      this.overlay.append(svg("path", { class: "hakushi-lasso", d, "vector-effect": "non-scaling-stroke" }));
    }
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
    // The ends of the one selected edge, to drag to other handles.
    if (this.selectedEdges.size === 1 && !this.config.readonly && this.gesture?.kind !== "connect") {
      const id = [...this.selectedEdges][0];
      const edge = this.edges.get(id);
      const geometry = edge && this.geometry(edge);
      if (geometry) {
        for (const [end, p] of [["source", geometry.from], ["target", geometry.to]] as const) {
          this.overlay.append(svg("circle", { class: "hakushi-knob", "data-edge": id, "data-end": end, cx: `${p.x}`, cy: `${p.y}`, r: `${6 / this.view.zoom}` }));
        }
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
      if (this.arranges) {
        group.append(
          button("layout", t("layout"), icons.layout, () => this.layout()),
          this.layoutsButton(button),
          button("undo", t("undo"), icons.undo, () => this.undo()),
          button("redo", t("redo"), icons.redo, () => this.redo()),
        );
      }
      if (this.config.exportable) group.append(button("export", t("export"), icons.download, () => void this.download()));
      // The papers people choose from (the canvas's `papers`), in a menu.
      if ((this.config.papers ?? []).length > 1) {
        const paper = button("paper", t("paper"), icons.paper, () => this.togglePaperMenu());
        paper.setAttribute("aria-haspopup", "menu");
        paper.setAttribute("aria-expanded", "false");
        group.append(paper);
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

  // -- The layouts ---------------------------------------------------------------
  //
  // A menu by the tidy up button of the ways to lay the nodes out. The way
  // chosen is the person's, for this page: the next tidy up (⇧L, the
  // button) lays out that way too.

  private chosenLayout: { algorithm: Algorithm; direction: "right" | "down" } | null = null;
  private layoutMenu: HTMLElement | null = null;

  private static layouts: { key: string; algorithm: Algorithm; direction: "right" | "down" }[] = [
    { key: "layoutRight", algorithm: "layered", direction: "right" },
    { key: "layoutDown", algorithm: "layered", direction: "down" },
    { key: "layoutForce", algorithm: "force", direction: "right" },
    { key: "layoutGrid", algorithm: "grid", direction: "right" },
  ];

  /** The way the next tidy up lays the nodes out: the person's choice, else the canvas's. */
  layoutChoice(): { algorithm: Algorithm; direction: "right" | "down" } {
    return this.chosenLayout ?? { algorithm: this.config.algorithm ?? "layered", direction: this.config.layout ?? "right" };
  }

  private layoutsButton(button: (action: string, label: string, content: string, run: () => void) => HTMLElement) {
    const b = button("layouts", this.messages.t("layouts"), icons.chevron, () => this.toggleLayoutMenu());
    b.classList.add("hakushi-control-more");
    b.setAttribute("aria-haspopup", "menu");
    b.setAttribute("aria-expanded", "false");
    return b;
  }

  private toggleLayoutMenu(open = !this.layoutMenu) {
    const button = this.controlsEl?.querySelector<HTMLElement>('[data-action="layouts"]');
    if (!open) {
      this.layoutMenu?.remove();
      this.layoutMenu = null;
      document.removeEventListener("pointerdown", this.closeLayoutMenu, true);
      button?.setAttribute("aria-expanded", "false");
      return;
    }
    this.togglePaperMenu(false);
    const choice = this.layoutChoice();
    const menu = el("div", { class: "hakushi-paper-menu hakushi-layout-menu", role: "menu", "aria-label": this.messages.t("layouts") });
    for (const way of Canvas.layouts) {
      const checked = way.algorithm === choice.algorithm && (way.algorithm !== "layered" || way.direction === choice.direction);
      const item = el("button", { type: "button", role: "menuitemradio", class: "hakushi-paper-item", "aria-checked": String(checked), tabindex: "-1", "data-layout": way.key }, [
        el("span", {}, [this.messages.t(way.key)]),
      ]);
      item.addEventListener("click", () => {
        this.chosenLayout = { algorithm: way.algorithm, direction: way.direction };
        this.toggleLayoutMenu(false);
        button?.focus();
        void this.layout();
      });
      menu.append(item);
    }
    menu.addEventListener("pointerdown", (event) => event.stopPropagation());
    menu.addEventListener("keydown", (event) => this.menuKey(event, menu, () => this.toggleLayoutMenu(false), button));
    this.layoutMenu = menu;
    this.ui.append(menu);
    button?.setAttribute("aria-expanded", "true");
    document.addEventListener("pointerdown", this.closeLayoutMenu, true);
    menu.querySelector<HTMLElement>('[aria-checked="true"]')?.focus();
  }

  private closeLayoutMenu = (event: Event) => {
    const target = event.target as Element | null;
    if (target?.closest?.(".hakushi-layout-menu") || target?.closest?.('[data-action="layouts"]')) return;
    this.toggleLayoutMenu(false);
  };

  // The keys of a menu: up and down, Home and End, Escape and Tab to close.
  private menuKey(event: KeyboardEvent, menu: HTMLElement, close: () => void, button: HTMLElement | null | undefined) {
    const items = [...menu.querySelectorAll<HTMLElement>(".hakushi-paper-item")];
    const index = items.indexOf(document.activeElement as HTMLElement);
    if (event.key === "Escape" || event.key === "Tab") {
      if (event.key === "Escape") event.preventDefault();
      close();
      if (event.key === "Escape") button?.focus();
    } else if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault();
      items[(index + (event.key === "ArrowDown" ? 1 : -1) + items.length) % items.length]?.focus();
    } else if (event.key === "Home" || event.key === "End") {
      event.preventDefault();
      items[event.key === "Home" ? 0 : items.length - 1]?.focus();
    }
    event.stopPropagation();
  }

  // -- The paper -----------------------------------------------------------------
  //
  // A menu of the papers the canvas offers, and of the sizes of their
  // squares. A paper chosen is a change of the graph's (Hakushi.Paper): it
  // undoes, and on a shared canvas everyone sees it.

  private paperMenu: HTMLElement | null = null;

  private togglePaperMenu(open = !this.paperMenu) {
    const button = this.controlsEl?.querySelector<HTMLElement>('[data-action="paper"]');
    if (!open) {
      this.paperMenu?.remove();
      this.paperMenu = null;
      document.removeEventListener("pointerdown", this.closePaperMenu, true);
      button?.setAttribute("aria-expanded", "false");
      return;
    }
    this.toggleLayoutMenu(false);
    const menu = el("div", { class: "hakushi-paper-menu", role: "menu", "aria-label": this.messages.t("paper") });
    menu.addEventListener("pointerdown", (event) => event.stopPropagation());
    menu.addEventListener("keydown", (event) => this.paperKey(event));
    this.paperMenu = menu;
    this.drawPaperMenu();
    this.ui.append(menu);
    button?.setAttribute("aria-expanded", "true");
    document.addEventListener("pointerdown", this.closePaperMenu, true);
    menu.querySelector<HTMLElement>('[aria-checked="true"]')?.focus();
  }

  // A press anywhere but the menu and its button closes it.
  private closePaperMenu = (event: Event) => {
    const target = event.target as Element | null;
    if (target?.closest?.(".hakushi-paper-menu") || target?.closest?.('[data-action="paper"]')) return;
    this.togglePaperMenu(false);
  };

  private drawPaperMenu() {
    const menu = this.paperMenu;
    if (!menu) return;
    const focused = (document.activeElement as HTMLElement | null)?.dataset?.paperItem;
    const current = this.config.background ?? this.root.dataset.background ?? "dots";
    const grid = this.config.grid;
    const item = (key: string, label: string, checked: boolean, choose: () => void, swatch?: string) => {
      const b = el("button", { type: "button", role: "menuitemradio", class: "hakushi-paper-item", "aria-checked": String(checked), tabindex: "-1", "data-paper-item": key });
      if (swatch !== undefined) b.append(el("span", { class: "hakushi-paper-frame", "aria-hidden": "true" }, [el("span", { class: "hakushi-paper-swatch", "data-background": swatch })]));
      b.append(el("span", {}, [label]));
      b.addEventListener("click", choose);
      return b;
    };
    const papers = el("div", { role: "group", "aria-label": this.messages.t("paper") });
    for (const paper of this.config.papers ?? []) {
      papers.append(item(`paper:${paper.name}`, paper.label, paper.name === current, () => this.choosePaper(paper.name, this.config.grid), paper.name));
    }
    const sizes = el("div", { role: "group", class: "hakushi-paper-sizes", "aria-label": this.messages.t("paperSquares") });
    const names = ["squaresSmall", "squaresMedium", "squaresLarge"];
    (this.config.paperGrids ?? []).forEach((size, i) => {
      sizes.append(item(`grid:${size}`, this.messages.t(names[i] ?? "paperSquares"), size === grid, () => this.choosePaper(this.config.background ?? current, size)));
    });
    menu.replaceChildren(papers, el("div", { class: "hakushi-paper-heading", "aria-hidden": "true" }, [this.messages.t("paperSquares")]), sizes);
    if (focused) menu.querySelector<HTMLElement>(`[data-paper-item="${CSS.escape(focused)}"]`)?.focus();
  }

  private paperKey(event: KeyboardEvent) {
    if (this.paperMenu) this.menuKey(event, this.paperMenu, () => this.togglePaperMenu(false), this.controlsEl?.querySelector<HTMLElement>('[data-action="paper"]'));
  }

  /** Chooses a paper the canvas offers (its name) and the size of its squares: a change, which undoes. */
  choosePaper(background: string, grid: number = this.config.grid) {
    if (this.config.readonly) return;
    const paper = (this.config.papers ?? []).find((p) => p.name === background);
    if (!paper || (background === this.config.background && grid === this.config.grid)) return;
    this.push("hakushi:change", { op: "paper", paper: { background, grid } }, (reply) => {
      if (!reply.error) this.announce(this.messages.t("paperChosen", { name: paper.label }));
    });
  }

  // -- Shapes ------------------------------------------------------------------
  //
  // A kit's tool of the mode "box" draws a node as a box dragged on the
  // paper; one of the mode "line", a line from a point to a point, which
  // is an edge when it goes from a node to another, and a node of the kit's
  // else. A node with text (`data-hakushi-text`) is written in place on a
  // double click; one that turns (`data-hakushi-rotate`) has a knob; a
  // kit's styles (`styles/1`) are a panel beside the selection.

  private editOnArrive: string | null = null;
  private styleEl: HTMLElement | null = null;

  // The box a shape gesture drew: from corner to corner, as wide as high with Shift.
  private shapeBox(g: Extract<Gesture, { kind: "shape" }>): Rect {
    let w = g.end.x - g.start.x;
    let h = g.end.y - g.start.y;
    if (g.square) {
      const side = Math.max(Math.abs(w), Math.abs(h));
      w = Math.sign(w || 1) * side;
      h = Math.sign(h || 1) * side;
    }
    return fromCorners(g.start, { x: g.start.x + w, y: g.start.y + h });
  }

  // The node a line may end on: the one on top under the point, with handles.
  private nodeAt(p: Point, except?: string): NodeModel | null {
    for (let i = this.order.length - 1; i >= 0; i--) {
      const node = this.nodes.get(this.order[i]);
      if (!node || node.id === except || this.gone.has(node.id) || node.group || !node.handles.length) continue;
      if (contains(this.rect(node), p)) return node;
    }
    return null;
  }

  private markLineEnd(end: Point, start: Point) {
    const from = this.nodeAt(start);
    const to = this.nodeAt(end, from?.id);
    for (const e of this.root.querySelectorAll("[data-ui-target]")) if (e !== to?.el) e.removeAttribute("data-ui-target");
    if (from && to) to.el.setAttribute("data-ui-target", "");
  }

  private commitShape(g: Extract<Gesture, { kind: "shape" }>) {
    const tool = `${g.tool.kit}:${g.tool.tool}`;
    const back = () => this.setTool(null);
    if (g.tool.mode === "line") {
      if (Math.hypot(g.end.x - g.start.x, g.end.y - g.start.y) * this.view.zoom < 6) return;
      const from = this.nodeAt(g.start);
      const to = this.nodeAt(g.end, from?.id);
      if (from && to) {
        // From a node to a node: an edge, which follows them.
        this.push("hakushi:change", { op: "connect", edges: [{ source: from.id, sourceHandle: null, target: to.id, targetHandle: null }] }, (reply) => {
          if (!reply.error) this.announce(this.messages.t("connected", { source: from.label, target: to.label }));
        });
      } else {
        this.push("hakushi:draw", { tool, points: [[round(g.start.x), round(g.start.y)], [round(g.end.x), round(g.end.y)]] }, (reply) => {
          if (typeof reply.drawn === "string") this.pendingSelect = [reply.drawn];
          this.selectPending();
        });
      }
      back();
      return;
    }
    const b = this.shapeBox(g);
    const clicked = b.width * this.view.zoom < 6 && b.height * this.view.zoom < 6;
    const box = clicked ? [round(g.start.x), round(g.start.y), 0, 0] : [round(b.x), round(b.y), round(b.width), round(b.height)];
    const group = this.groupAt({ x: b.x + b.width / 2, y: b.y + b.height / 2 }, new Set());
    const text = g.tool.tool === "text";
    this.push("hakushi:draw", { tool, box, parent: group?.id ?? null }, (reply) => {
      if (typeof reply.drawn !== "string") return;
      this.pendingSelect = [reply.drawn];
      if (text) this.editOnArrive = reply.drawn;
      this.selectPending();
    });
    back();
  }

  private startRotate(event: PointerEvent, node: NodeModel) {
    const turning = node.el.querySelector<HTMLElement>("[data-hakushi-rotate]");
    if (!turning) return;
    const at = this.canvasPoint(event);
    const center = this.center(node);
    const base = parseFloat(getComputedStyle(turning).getPropertyValue("--hakushi-rotation")) || 0;
    this.capture(event);
    this.gesture = { kind: "rotate", pointer: event.pointerId, id: node.id, center, from: (Math.atan2(at.y - center.y, at.x - center.x) * 180) / Math.PI, base, deg: base, el: turning };
  }

  /** Writes the text of a node that has one, in place: Escape takes it back, a click elsewhere keeps it. */
  editText(node: NodeModel) {
    const text = node.el.querySelector<HTMLElement>("[data-hakushi-text]");
    if (!text || this.config.readonly) return;
    const turning = node.el.querySelector<HTMLElement>("[data-hakushi-rotate]");
    const rotation = turning ? getComputedStyle(turning).getPropertyValue("--hakushi-rotation").trim() || "0deg" : "0deg";
    const at = this.placeOf(node);
    // A text with a place of its own in its node (an image's caption, under it): there.
    const own = text.hasAttribute("data-hakushi-text-own");
    const box = own ? { x: at.x + text.offsetLeft, y: at.y + text.offsetTop, width: text.offsetWidth, height: Math.max(text.offsetHeight, 24) } : { ...at, width: node.width, height: node.height };
    const editor = el("div", { class: `${text.className} hakushi-text-editor`, contenteditable: "plaintext-only", role: "textbox", "aria-multiline": "true", "aria-label": text.dataset.hakushiTextLabel ?? this.messages.t("shapeTextLabel"), "data-size": text.dataset.size ?? "m", "data-align": text.dataset.align ?? "center" });
    editor.textContent = text.dataset.hakushiText ?? text.textContent ?? "";
    const style = getComputedStyle(text);
    Object.assign(editor.style, { translate: `${box.x}px ${box.y}px`, width: `${box.width}px`, minHeight: `${box.height}px`, rotate: rotation, color: style.color, fontFamily: style.fontFamily, padding: style.padding });
    this.labelsEl.append(editor);
    text.style.visibility = "hidden";
    editor.focus();
    const range = document.createRange();
    range.selectNodeContents(editor);
    getSelection()?.removeAllRanges();
    getSelection()?.addRange(range);
    let done = false;
    const finish = (save: boolean) => {
      if (done) return;
      done = true;
      const value = (editor.innerText ?? "").replace(/\n$/, "");
      // A text longer than the shape: the shape grows with it.
      const needed = Math.ceil(editor.scrollHeight);
      editor.remove();
      text.style.visibility = "";
      this.root.focus({ preventScroll: true });
      if (!save || value === (text.dataset.hakushiText ?? "")) return;
      this.push("hakushi:edit", { node: node.id, action: "text", value }, (reply) => {
        const current = this.nodes.get(node.id);
        if (own || reply.error || !current || needed <= current.height + 1) return;
        this.push("hakushi:change", { op: "move", nodes: [{ id: current.id, x: current.x, y: current.y, width: current.width, height: needed }] });
      });
    };
    editor.addEventListener("keydown", (event) => {
      event.stopPropagation();
      if (event.key === "Escape") finish(false);
      if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) finish(true);
    });
    editor.addEventListener("blur", () => finish(true));
    editor.addEventListener("pointerdown", (event) => event.stopPropagation());
  }

  // The style panel of a kit (`styles/1`), beside the selection, when every
  // selected node is of its types: the choices the nodes have, the one they
  // share pressed.
  private drawStylePanel() {
    const panels = this.config.styles ?? [];
    const ids = [...this.selected];
    const nodes = ids.map((id) => this.nodes.get(id)).filter((n): n is NodeModel => !!n && !this.gone.has(n.id));
    const panel = nodes.length && !this.tool ? panels.find((p) => nodes.every((n) => p.types.includes(n.type))) : undefined;
    if (!panel || this.config.readonly || this.cropping) {
      this.styleEl?.remove();
      this.styleEl = null;
      return;
    }
    // A field of the panel being written in stays as it is, for the same nodes.
    const typing = this.styleEl?.contains(document.activeElement) && document.activeElement instanceof HTMLInputElement;
    if (typing && this.styleEl!.dataset.nodes === ids.join(" ")) return;
    const styles = nodes.map((n) => {
      try {
        return JSON.parse(n.el.querySelector<HTMLElement>("[data-hakushi-style]")?.dataset.hakushiStyle ?? "{}") as Record<string, unknown>;
      } catch {
        return {};
      }
    });
    if (!this.styleEl) {
      this.styleEl = el("div", { class: "hakushi-style-panel", role: "toolbar", "aria-label": this.messages.t("shapeStyle"), "aria-orientation": "vertical" });
      this.styleEl.addEventListener("pointerdown", (event) => event.stopPropagation());
      this.ui.append(this.styleEl);
    }
    this.styleEl.dataset.nodes = ids.join(" ");
    const groups: HTMLElement[] = [];
    for (const group of panel.groups) {
      const values = styles.filter((st) => group.key in st).map((st) => JSON.stringify(st[group.key]));
      if (!values.length) continue;
      const shared = values.every((v) => v === values[0]) ? values[0] : null;
      const row = el("div", { class: "hakushi-style-group", role: "group", "aria-label": group.label, "data-kind": group.kind });
      if (group.kind === "action") {
        // A button of the canvas's own, for one node.
        if (nodes.length !== 1) continue;
        const b = el("button", { type: "button", class: "hakushi-style-option hakushi-style-action", "data-key": group.key, title: group.label });
        b.innerHTML = (icons as Record<string, string>)[group.icon ?? ""] ?? "";
        b.append(el("span", {}, [group.label]));
        b.addEventListener("click", () => this.styleAction(group.key, nodes[0]));
        row.append(b);
        groups.push(row);
        continue;
      }
      row.append(el("span", { class: "hakushi-style-label", "aria-hidden": "true" }, [group.label]));
      if (group.kind === "text") {
        const input = el("input", { type: "text", class: "hakushi-style-text", "data-key": group.key, "aria-label": group.label, placeholder: group.placeholder ?? "" });
        input.value = shared !== null ? String(JSON.parse(shared) ?? "") : "";
        const save = () => {
          const value = input.value;
          if (shared !== null && JSON.stringify(value) === shared) return;
          this.push("hakushi:edit", { nodes: ids, action: "style", style: { [group.key]: value } });
        };
        input.addEventListener("change", save);
        input.addEventListener("keydown", (event) => {
          event.stopPropagation();
          if (event.key === "Enter") {
            save();
            this.root.focus({ preventScroll: true });
          } else if (event.key === "Escape") {
            input.value = shared !== null ? String(JSON.parse(shared) ?? "") : "";
            this.root.focus({ preventScroll: true });
          }
        });
        row.append(input);
        groups.push(row);
        continue;
      }
      const options = el("div", { class: "hakushi-style-options" });
      for (const option of group.options) {
        const b = el("button", { type: "button", class: "hakushi-style-option", "aria-label": `${group.label}: ${option.label}`, title: option.label, "aria-pressed": String(JSON.stringify(option.value) === shared), "data-key": group.key, "data-value": JSON.stringify(option.value) });
        if (group.kind === "color") {
          b.classList.add("hakushi-style-swatch");
          b.dataset.color = String(option.value);
          b.style.setProperty("--hakushi-swatch", option.value === "none" ? "transparent" : `var(--hakushi-shape-${option.value})`);
        } else if (group.kind === "width") {
          b.append(el("span", {}));
          b.style.setProperty("--hakushi-style-width", `${Number(option.value)}px`);
        } else {
          b.textContent = option.label;
        }
        b.addEventListener("click", () => {
          this.push("hakushi:edit", { nodes: ids, action: "style", style: { [group.key]: option.value } });
        });
        options.append(b);
      }
      row.append(options);
      groups.push(row);
    }
    this.styleEl.replaceChildren(...groups);
  }

  // -- Files (a kit that takes them: Hakushi.Kits.Images) ----------------------
  //
  // Files dropped, pasted or picked go to the canvas's LiveView upload (its
  // file input, with LiveView's `track-uploads`), each with a placeholder
  // where it lands: the file, faded, with its progress, which the others
  // see too. The server says how each goes (`hakushi:file`): its progress,
  // then the node it became (selected), or why it did not. An image's
  // address, pasted or dropped, goes the same way, as `hakushi:paste-url`.

  private filePlaces = new Map<string, { box: Rect; progress: number; el: HTMLElement; blob: string | null; name: string }>();
  private filePicker: HTMLInputElement | null = null;
  private fileSeq = 0;
  private pasteTimer = 0;
  private copiedText: string | null = null;

  /** Opens the browser's picker of files, for a canvas that takes them. */
  openPicker() {
    const files = this.config.files;
    if (!files || this.config.readonly) return;
    if (!this.filePicker) {
      const input = el("input", { type: "file", multiple: "", accept: files.accept.join(","), hidden: "", tabindex: "-1", "aria-hidden": "true", class: "hakushi-file-picker" });
      // Its events are not the app's form's.
      input.addEventListener("input", (event) => event.stopPropagation());
      input.addEventListener("change", (event) => {
        event.stopPropagation();
        const chosen = [...(input.files ?? [])];
        input.value = "";
        // In the middle of the view: the pointer was on the bar.
        void this.addFiles(chosen, toCanvas(this.view, this.size.width / 2, this.size.height / 2));
      });
      this.ui.append(input);
      this.filePicker = input;
    }
    this.filePicker.click();
  }

  private takesFile(file: File): boolean {
    const accept = this.config.files?.accept ?? [];
    const dot = file.name.lastIndexOf(".");
    const extension = dot >= 0 ? file.name.slice(dot).toLowerCase() : "";
    const byType: Record<string, string[]> = { "image/png": [".png"], "image/jpeg": [".jpg", ".jpeg"], "image/gif": [".gif"], "image/webp": [".webp"] };
    return accept.includes(extension) || (byType[file.type] ?? []).some((e) => accept.includes(e));
  }

  // The pointer, when it is on the canvas, else the middle of the view.
  private pointerOrCenter(): Point {
    if (this.pointer && contains(visible(this.view, this.size.width, this.size.height), this.pointer)) return this.pointer;
    return toCanvas(this.view, this.size.width / 2, this.size.height / 2);
  }

  /** Uploads image files to the canvas: in a row about `at` (the pointer, or the middle of the view). */
  async addFiles(files: File[], at?: Point): Promise<void> {
    const input = this.root.querySelector<HTMLInputElement>("input[data-hakushi-files]");
    if (!this.config.files || this.config.readonly || !input) return;
    const taken = files.filter((f) => this.takesFile(f));
    if (!taken.length) {
      if (files.length) this.announce(this.messages.t("refusedNotAnImage"));
      return;
    }
    const center = at ?? this.pointerOrCenter();
    const z = this.view.zoom;
    const seen = { width: this.size.width / z, height: this.size.height / z };
    const blobs = taken.map((f) => URL.createObjectURL(f));
    const pixels = await Promise.all(blobs.map((b) => pixelsOf(b)));
    const boxes = rowAt(pixels.map((p) => fitImage(p ?? { width: 4, height: 3 }, seen)), center);
    const group = this.groupAt(center, new Set());
    input.dispatchEvent(new CustomEvent("track-uploads", { bubbles: true, detail: { files: taken } }));
    // LiveView gives each file its entry's ref as it sends the form's change.
    const refOf = (file: File) => (file as File & { _phxRef?: string })._phxRef;
    if (taken.some((f) => refOf(f) === undefined)) await new Promise((resolve) => window.setTimeout(resolve, 0));
    taken.forEach((file, i) => {
      const ref = refOf(file);
      if (ref === undefined) return URL.revokeObjectURL(blobs[i]);
      const box = boxes[i];
      this.showFile(ref, box, file.name, blobs[i]);
      this.push("hakushi:place", { ref, box: [box.x, box.y, box.width, box.height].map(round), parent: group?.id ?? null });
    });
    this.announce(this.messages.t("imageUploading", { name: taken.length === 1 ? taken[0].name : String(taken.length) }));
    this.sendPeer();
  }

  // An image's address: the server fetches it, if the app lets it.
  private pasteUrl(url: string, at?: Point) {
    const ref = `${this.id}-u${++this.fileSeq}`;
    const z = this.view.zoom;
    const [box] = rowAt([fitImage({ width: 400, height: 300 }, { width: this.size.width / z, height: this.size.height / z })], at ?? this.pointerOrCenter());
    const group = this.groupAt({ x: box.x + box.width / 2, y: box.y + box.height / 2 }, new Set());
    this.showFile(ref, box, url, null);
    this.push("hakushi:paste-url", { url, ref, box: [box.x, box.y, box.width, box.height].map(round), parent: group?.id ?? null }, (reply) => {
      if (reply.ok !== true) this.dropFile(ref);
    });
    this.sendPeer();
  }

  private showFile(ref: string, box: Rect, name: string, blob: string | null) {
    const placeholder = el("div", { class: "hakushi-file", "data-ref": ref, role: "img", "aria-label": this.messages.t("imageUploading", { name }) }, [el("div", { class: "hakushi-file-bar" }, [el("span", {})])]);
    if (blob) placeholder.prepend(el("img", { src: blob, alt: "", draggable: "false" }));
    placeFile(placeholder, box, 0);
    this.labelsEl.append(placeholder);
    this.filePlaces.set(ref, { box, progress: 0, el: placeholder, blob, name });
  }

  private dropFile(ref: string) {
    const place = this.filePlaces.get(ref);
    if (!place) return;
    place.el.remove();
    if (place.blob) URL.revokeObjectURL(place.blob);
    this.filePlaces.delete(ref);
    this.sendPeer();
  }

  /** What the server says of a file: its `progress`, the node it became (`id`), or an `error`. */
  fileEvent(payload: Record<string, unknown>) {
    const ref = String(payload.ref);
    const place = this.filePlaces.get(ref);
    if (typeof payload.progress === "number") {
      if (place) {
        place.progress = payload.progress;
        placeFile(place.el, place.box, place.progress);
        this.sendPeer();
      }
      return;
    }
    // The node comes with this event, or just after it: the placeholder
    // stays until it is there.
    if (typeof payload.id === "string") {
      const id = payload.id;
      const done = () => {
        this.dropFile(ref);
        this.pendingSelect = [...(this.pendingSelect ?? []).filter((n) => n !== id), id];
        this.selectPending();
        this.announce(this.messages.t("imageAdded"));
      };
      if (this.nodes.has(id)) done();
      else this.whenNode(id, done);
      return;
    }
    this.dropFile(ref);
  }

  private nodeWaits = new Map<string, () => void>();

  // Once the node is on the canvas (the server's patch after its event).
  private whenNode(id: string, fn: () => void) {
    this.nodeWaits.set(id, fn);
    window.setTimeout(() => {
      const wait = this.nodeWaits.get(id);
      if (wait === fn) {
        this.nodeWaits.delete(id);
        fn();
      }
    }, 2000);
  }

  private dragOver(event: DragEvent) {
    const files = this.config.files;
    if (!files || this.config.readonly || !event.dataTransfer) return;
    const types = [...event.dataTransfer.types];
    if (!types.includes("Files") && !(files.urls && types.includes("text/uri-list"))) return;
    event.preventDefault();
    event.dataTransfer.dropEffect = "copy";
    this.root.setAttribute("data-ui-dropping", "");
  }

  private dropFiles(event: DragEvent) {
    const files = this.config.files;
    this.root.removeAttribute("data-ui-dropping");
    if (!files || this.config.readonly || !event.dataTransfer) return;
    const dropped = [...event.dataTransfer.files];
    const at = this.canvasPoint(event);
    if (dropped.length) {
      event.preventDefault();
      void this.addFiles(dropped, at);
      return;
    }
    const url = files.urls ? imageAddress(event.dataTransfer.getData("text/uri-list").split(/\r?\n/).find((l) => l && !l.startsWith("#")) ?? "") : null;
    if (url) {
      event.preventDefault();
      this.pasteUrl(url, at);
    }
  }

  // Whether the canvas has the keys (its root, or a node), not a field.
  private hasKeys(): boolean {
    const active = document.activeElement;
    return active instanceof HTMLElement && this.root.contains(active) && !editable(active) && !active.closest(".hakushi-style-panel, .hakushi-tools, .hakushi-controls");
  }

  // A paste on a canvas that takes files: the clipboard's images, or an
  // image's address, else the nodes copied here.
  private pasteFrom(event: ClipboardEvent) {
    if (!this.config.files || this.config.readonly || !this.hasKeys()) return;
    clearTimeout(this.pasteTimer);
    event.preventDefault();
    const data = event.clipboardData;
    const files = data ? [...data.files].filter((f) => this.takesFile(f)) : [];
    if (files.length) return void this.addFiles(files);
    const text = data?.getData("text/plain") ?? "";
    const url = this.config.files.urls && text !== this.copiedText ? imageAddress(text) : null;
    if (url) return this.pasteUrl(url);
    this.paste();
  }

  // Nodes copied here: the clipboard says so (their names), and has no image
  // of before that a paste would take for them.
  private copied(event: ClipboardEvent) {
    if (!this.config.files || !this.selected.size || !this.hasKeys() || !event.clipboardData) return;
    const text = [...this.selected].map((id) => this.nodes.get(id)?.label ?? id).join("\n");
    event.clipboardData.setData("text/plain", text);
    this.copiedText = text;
    event.preventDefault();
  }

  // The others' files, as they upload.
  private drawPeerFiles(peer: Peer, color: string) {
    while (peer.fileEls.length > peer.files.length) peer.fileEls.pop()!.remove();
    peer.files.forEach(([x, y, width, height, progress], i) => {
      let placeholder = peer.fileEls[i];
      if (!placeholder) {
        placeholder = el("div", { class: "hakushi-file", "data-peer": "", "aria-hidden": "true" }, [el("div", { class: "hakushi-file-bar" }, [el("span", {})])]);
        this.labelsEl.append(placeholder);
        peer.fileEls.push(placeholder);
      }
      placeholder.style.setProperty("--hakushi-peer", color);
      placeFile(placeholder, { x, y, width, height }, progress);
    });
  }

  // An image's smaller copy (`data-thumb`) while the canvas is zoomed out, its file otherwise.
  private thumbs(scope: Element) {
    const far = this.root.dataset.uiZoom === "far";
    for (const image of scope.querySelectorAll<HTMLImageElement>("img[data-thumb]")) {
      const want = far ? image.dataset.thumb : image.dataset.src;
      if (want && image.getAttribute("src") !== want) image.setAttribute("src", want);
    }
  }

  // A button of a style panel (`kind: "action"`): the canvas's own actions.
  private styleAction(key: string, node: NodeModel) {
    if (key === "crop") this.startCrop(node);
  }

  // -- Cropping an image in place ----------------------------------------------
  //
  // The whole file, faded, around the node, and the part it shows in a box
  // whose corners and sides are dragged, and which is dragged as a whole.
  // Enter (or a press elsewhere) keeps it, as one change of the node's crop
  // and box; Escape leaves it as it was.

  private cropping: { node: NodeModel; full: Rect; box: Rect; start: Rect; el: HTMLElement; frame: HTMLElement; view: HTMLImageElement; drag: { pointer: number; handle: string; from: Point; rect: Rect } | null } | null = null;

  /** Crops an image node in place (its `data-hakushi-crop`). */
  startCrop(node: NodeModel) {
    const figure = node.el.querySelector<HTMLElement>("[data-hakushi-crop]");
    const src = figure?.querySelector<HTMLImageElement>("img")?.dataset.src;
    if (!figure || !src || this.config.readonly || node.locked) return;
    this.finishCrop(false);
    let crop: Crop;
    try {
      crop = JSON.parse(figure.dataset.hakushiCrop ?? "[0,0,1,1]") as Crop;
    } catch {
      crop = [0, 0, 1, 1];
    }
    const at = this.placeOf(node);
    const box = { x: at.x, y: at.y, width: node.width, height: node.height };
    const full = fullOf(box, crop);
    const view = el("img", { src, alt: "", draggable: "false" });
    const frame = el("div", { class: "hakushi-crop-box", "data-handle": "move" }, [el("div", { class: "hakushi-crop-view" }, [view])]);
    for (const handle of ["nw", "n", "ne", "e", "se", "s", "sw", "w"]) frame.append(el("span", { class: "hakushi-crop-handle", "data-handle": handle }));
    const overlay = el("div", { class: "hakushi-crop", role: "dialog", "aria-label": this.messages.t("imageCrop") }, [el("img", { class: "hakushi-crop-ghost", src, alt: "", draggable: "false" }), frame]);
    Object.assign(overlay.style, { translate: `${full.x}px ${full.y}px`, width: `${full.width}px`, height: `${full.height}px` });
    this.labelsEl.append(overlay);
    node.el.setAttribute("data-ui-cropping", "");
    this.cropping = { node, full, box, start: box, el: overlay, frame, view, drag: null };
    this.drawCrop();
    overlay.addEventListener("pointerdown", (event) => this.cropDown(event));
    overlay.addEventListener("pointermove", (event) => this.cropMove(event));
    overlay.addEventListener("pointerup", (event) => this.cropUp(event));
    overlay.addEventListener("pointercancel", (event) => this.cropUp(event));
    this.drawStylePanel();
    this.root.focus({ preventScroll: true });
    this.announce(this.messages.t("imageCropHint"));
  }

  private drawCrop() {
    const c = this.cropping;
    if (!c) return;
    const { full, box } = c;
    Object.assign(c.frame.style, { left: `${box.x - full.x}px`, top: `${box.y - full.y}px`, width: `${box.width}px`, height: `${box.height}px` });
    Object.assign(c.view.style, { left: `${full.x - box.x}px`, top: `${full.y - box.y}px`, width: `${full.width}px`, height: `${full.height}px` });
  }

  private cropDown(event: PointerEvent) {
    const c = this.cropping;
    event.stopPropagation();
    if (!c || event.button !== 0) return;
    const handle = (event.target as Element).closest<HTMLElement>("[data-handle]")?.dataset.handle;
    if (!handle) return;
    event.preventDefault();
    c.el.setPointerCapture(event.pointerId);
    c.drag = { pointer: event.pointerId, handle, from: { x: event.clientX, y: event.clientY }, rect: c.box };
  }

  private cropMove(event: PointerEvent) {
    const c = this.cropping;
    if (!c?.drag || c.drag.pointer !== event.pointerId) return;
    const z = this.view.zoom;
    c.box = dragCrop(c.full, c.drag.rect, c.drag.handle, (event.clientX - c.drag.from.x) / z, (event.clientY - c.drag.from.y) / z);
    this.drawCrop();
  }

  private cropUp(event: PointerEvent) {
    const c = this.cropping;
    if (!c?.drag || c.drag.pointer !== event.pointerId) return;
    c.drag = null;
  }

  private finishCrop(keep: boolean) {
    const c = this.cropping;
    if (!c) return;
    this.cropping = null;
    c.el.remove();
    c.node.el.removeAttribute("data-ui-cropping");
    this.drawStylePanel();
    const { box, start, full, node } = c;
    const same = Math.abs(box.x - start.x) < 0.5 && Math.abs(box.y - start.y) < 0.5 && Math.abs(box.width - start.width) < 0.5 && Math.abs(box.height - start.height) < 0.5;
    if (!keep || same) return;
    this.push("hakushi:edit", { node: node.id, action: "crop", crop: cropOf(full, box), box: [box.x, box.y, box.width, box.height].map(round) });
  }

  // -- The tools of the kits ---------------------------------------------------
  //
  // A bar of the kits' tools (Hakushi.Kit's `tools/1`), over the canvas:
  // the pointer, which selects and drags as usual, then each tool, and the
  // colours and widths of a drawing tool. A drawing tool's line (ink) is
  // smoothed as it comes, goes to the others as it is drawn, and becomes a
  // node of the kit's when the pen lifts.

  private buildTools() {
    this.toolsEl?.remove();
    this.toolsEl = null;
    const tools = this.config.readonly ? [] : (this.config.tools ?? []);
    if (this.tool && !tools.some((t) => t.kit === this.tool!.kit && t.tool === this.tool!.tool)) this.tool = null;
    this.root.toggleAttribute("data-ui-tool", false);
    if (!tools.length) return;
    const t = (key: string, values: Record<string, string | number> = {}) => this.messages.t(key, values);
    const bar = el("div", { class: "hakushi-tools", role: "toolbar", "aria-label": t("inkTools") });
    const button = (name: string, label: string, icon: string, key: string | null) => {
      const b = el("button", { type: "button", class: "hakushi-control hakushi-tool", "data-tool": name, "aria-label": label, title: key ? `${label} (${key.toUpperCase()})` : label, "aria-pressed": "false" });
      b.innerHTML = (icons as Record<string, string>)[icon] ?? icons.pointer;
      b.addEventListener("click", (event) => {
        event.stopPropagation();
        this.setTool(name === "pointer" ? null : name);
      });
      return b;
    };
    bar.append(button("pointer", t("inkSelect"), "pointer", "v"));
    for (const tool of tools) bar.append(button(`${tool.kit}:${tool.tool}`, tool.label, tool.icon, tool.key));
    bar.append(el("div", { class: "hakushi-tool-options", role: "group" }));
    bar.addEventListener("pointerdown", (event) => event.stopPropagation());
    this.toolsEl = bar;
    this.ui.append(bar);
    this.showTool();
  }

  /** Chooses a tool of the kits by its name (`"ink:pen"`), or the pointer (`null`). */
  setTool(name: string | null) {
    const tool = name ? (this.config.tools ?? []).find((t) => `${t.kit}:${t.tool}` === name) : undefined;
    if (this.config.readonly || (name && !tool)) return;
    // A picker of files: it opens, and the tool stays as it was.
    if (tool?.mode === "pick") return this.openPicker();
    if (this.gesture) this.cancelGesture();
    this.tool = tool ?? null;
    this.showTool();
    this.announce(tool ? tool.label : this.messages.t("inkSelect"));
  }

  /** The tool chosen (`"ink:pen"`), or `null` for the pointer. */
  getTool(): string | null {
    return this.tool ? `${this.tool.kit}:${this.tool.tool}` : null;
  }

  private showTool() {
    this.drawStylePanel();
    const name = this.getTool() ?? "pointer";
    if (this.tool) this.root.dataset.uiTool = this.tool.mode;
    else delete this.root.dataset.uiTool;
    const bar = this.toolsEl;
    if (!bar) return;
    for (const b of bar.querySelectorAll<HTMLElement>(".hakushi-tool")) b.setAttribute("aria-pressed", String(b.dataset.tool === name));
    // The colours and widths of a drawing tool.
    const options = bar.querySelector<HTMLElement>(".hakushi-tool-options")!;
    options.replaceChildren();
    const tool = this.tool;
    if (tool?.mode !== "draw") {
      options.hidden = true;
      return;
    }
    options.hidden = false;
    const prefs = this.inkPrefsOf(tool);
    for (const color of tool.colors ?? []) {
      const label = this.messages.t(`color${color[0].toUpperCase()}${color.slice(1)}`);
      const b = el("button", { type: "button", class: "hakushi-control hakushi-swatch", "data-color": color, "data-tool": tool.tool, "aria-label": label, title: label, "aria-pressed": String(color === prefs.color) });
      b.addEventListener("click", () => this.setInk(tool, { color }));
      options.append(b);
    }
    for (const size of tool.sizes ?? []) {
      const label = this.messages.t("inkSize", { n: size });
      const b = el("button", { type: "button", class: "hakushi-control hakushi-width", "data-color": prefs.color, "data-tool": tool.tool, "aria-label": label, title: label, "aria-pressed": String(size === prefs.size) }, [el("span", {})]);
      b.style.setProperty("--hakushi-ink-width", `${Math.min(18, Math.max(3, size * (tool.flat ? 0.6 : 1.2)))}px`);
      b.addEventListener("click", () => this.setInk(tool, { size }));
      options.append(b);
    }
  }

  private inkPrefsOf(tool: Tool): { color: string; size: number } {
    const key = `${tool.kit}:${tool.tool}`;
    let prefs = this.inkPrefs.get(key);
    if (!prefs) this.inkPrefs.set(key, (prefs = { color: tool.color ?? tool.colors?.[0] ?? "ink", size: tool.size ?? tool.sizes?.[0] ?? 4 }));
    return prefs;
  }

  private setInk(tool: Tool, change: { color?: string; size?: number }) {
    Object.assign(this.inkPrefsOf(tool), change);
    this.showTool();
  }

  private flat(stroke: InkStroke): boolean {
    const tool = (this.config.tools ?? []).find((t) => `${t.kit}:${t.tool}` === stroke.tool);
    return tool ? tool.flat === true : stroke.tool.endsWith("highlighter");
  }

  // The points of a move (each of those the browser gathered since the
  // last, for a smooth line), a little behind the pointer, with the pen's
  // pressure (a mouse's and a finger's is flat).
  private addInkPoints(event: PointerEvent) {
    const g = this.gesture;
    if (g?.kind !== "ink") return;
    const events = typeof event.getCoalescedEvents === "function" ? event.getCoalescedEvents() : [];
    const flat = g.tool.flat === true;
    for (const e of events.length ? events : [event]) {
      const p = this.canvasPoint(e);
      const pressure = !flat && e.pointerType === "pen" && e.pressure > 0 ? e.pressure : FLAT;
      const points = g.stroke.points;
      const last = points[points.length - 1];
      if (last && Math.hypot(p.x - last[0], p.y - last[1]) * this.view.zoom < 0.75) continue;
      points.push(streamline(last, [p.x, p.y, pressure]));
    }
  }

  // A line drawn: simplified, to the server, which makes a node of it;
  // drawn here until the node comes.
  private commitInk(stroke: InkStroke) {
    if (!stroke.points.length) return;
    const points = simplify(stroke.points, INK_TOLERANCE / this.view.zoom).map(([x, y, p]): InkPoint => [round(x), round(y), Math.round(p * 100) / 100]);
    const done: InkStroke = { ...stroke, points };
    const pending = { key: `pending-${this.inkSeq++}`, stroke: done, id: null as string | null };
    this.inkPending.push(pending);
    const box = inkBox(points, stroke.size, this.flat(stroke));
    const group = this.groupAt({ x: box.x + box.width / 2, y: box.y + box.height / 2 }, new Set());
    this.push("hakushi:draw", { tool: stroke.tool, points, color: stroke.color, size: stroke.size, parent: group?.id ?? null }, (reply) => {
      if (typeof reply.drawn === "string" && !this.nodes.has(reply.drawn)) {
        pending.id = reply.drawn;
        this.announce(this.messages.t("drawn"));
      } else {
        this.inkPending = this.inkPending.filter((p) => p !== pending);
      }
      this.schedule();
    });
  }

  // A line as it goes to the others: its points, fewer when there are many.
  private inkToSend(stroke: InkStroke): InkStroke {
    let points = stroke.points;
    for (let tolerance = 0.5; points.length > INK_SENT_MAX; tolerance *= 2) points = simplify(stroke.points, tolerance / this.view.zoom);
    return { ...stroke, points: points.map(([x, y, p]): InkPoint => [round(x), round(y), Math.round(p * 100) / 100]) };
  }

  // The nodes an eraser takes that it passed over, from one point to the
  // next: hidden now, deleted when it lifts.
  private eraseAlong(from: Point, to: Point) {
    const g = this.gesture;
    if (g?.kind !== "erase") return;
    const types = new Set(g.tool.types ?? []);
    const reach = 6 / this.view.zoom;
    const steps = Math.max(1, Math.ceil((Math.hypot(to.x - from.x, to.y - from.y) * this.view.zoom) / 4));
    const candidates = [...this.nodes.values()].filter((n) => types.has(n.type) && !this.gone.has(n.id) && !n.locked && intersects(grow(fromCorners(from, to), reach), this.rect(n)));
    for (const node of candidates) {
      const at = this.placeOf(node);
      const aim = node.el.querySelector<SVGGeometryElement>(".hakushi-ink-aim");
      for (let i = 0; i <= steps; i++) {
        const p = { x: from.x + ((to.x - from.x) * i) / steps, y: from.y + ((to.y - from.y) * i) / steps };
        const hit = aim ? hitsStroke(aim, p.x - at.x, p.y - at.y, reach) : contains(grow(this.rect(node), reach), p);
        if (hit) {
          g.hit.add(node.id);
          this.gone.add(node.id);
          this.decorate(node);
          this.touchNode(node.id);
          break;
        }
      }
    }
  }

  private unerase(ids: Set<string>) {
    for (const id of ids) this.gone.delete(id);
    this.refresh(ids);
  }

  private commitErase(ids: Set<string>) {
    const nodes = [...ids].filter((id) => this.nodes.has(id));
    if (!nodes.length) return;
    this.push("hakushi:change", { op: "delete", nodes, edges: [] }, (reply) => {
      if (reply.error) this.unerase(ids);
      else this.announce(this.messages.count("deleted", nodes.length));
    });
  }

  // What a lasso encloses: a node by its middle, a stroke by most of its line.
  private selectLassoed(points: Point[], base: Set<string>) {
    const ids = new Set(base);
    if (points.length >= 3) {
      for (const node of this.nodes.values()) {
        if (this.gone.has(node.id)) continue;
        const aim = node.el.querySelector<SVGGeometryElement>(".hakushi-ink-aim");
        if (aim && !node.el.hasAttribute("data-ui-culled")) {
          const at = this.placeOf(node);
          const length = aim.getTotalLength();
          const samples = 12;
          let within = 0;
          for (let i = 0; i <= samples; i++) {
            const p = aim.getPointAtLength((length * i) / samples);
            if (inside(points, { x: p.x + at.x, y: p.y + at.y })) within++;
          }
          if (within / (samples + 1) >= 0.6) ids.add(node.id);
        } else if (inside(points, this.center(node))) {
          ids.add(node.id);
        }
      }
    }
    this.selectedEdges.clear();
    this.setSelection(ids);
    this.selectionChanged();
  }

  // The lines being drawn: this person's, theirs until they are nodes, and
  // the others' (in the colour of their ink, under their cursor).
  private drawInk() {
    const want = new Map<string, InkStroke>();
    const g = this.gesture;
    if (g?.kind === "ink" && g.stroke.points.length) want.set("self", g.stroke);
    for (const p of this.inkPending) want.set(p.key, p.stroke);
    for (const [id, peer] of this.peers) if (peer.ink && this.people.has(id)) want.set(`peer:${id}`, peer.ink);
    for (const [key, drawn] of this.inkPaths) {
      if (!want.has(key)) {
        drawn.path.remove();
        this.inkPaths.delete(key);
      }
    }
    for (const [key, stroke] of want) {
      let drawn = this.inkPaths.get(key);
      if (!drawn) {
        drawn = { path: svg("path", {}), stroke, length: -1 };
        this.inkPaths.set(key, drawn);
        this.inkG.append(drawn.path);
      }
      if (drawn.stroke === stroke && drawn.length === stroke.points.length) continue;
      drawn.stroke = stroke;
      drawn.length = stroke.points.length;
      const [, tool] = stroke.tool.split(":");
      drawn.path.setAttribute("data-tool", tool ?? stroke.tool);
      drawn.path.setAttribute("data-color", stroke.color);
      drawn.path.setAttribute("d", outline(stroke.points, stroke.size, this.flat(stroke)));
    }
  }

  // -- The view ----------------------------------------------------------------

  private measureRoot() {
    const rect = this.root.getBoundingClientRect();
    this.bounds = rect;
    const changed = rect.width !== this.size.width || rect.height !== this.size.height;
    const resized = changed && this.size.width > 0 && rect.width > 0;
    this.size = { width: rect.width, height: rect.height };
    // A canvas that changes its box (an embed going full screen and back)
    // shows all of its nodes again.
    if (resized && this.config.refit && this.nodes.size) this.view = this.fitView();
    if (changed) this.schedule();
  }

  private fitView(ids?: Iterable<string>): View {
    const list = ids ? [...ids].map((id) => this.nodes.get(id)).filter((n): n is NodeModel => !!n) : [...this.nodes.values()];
    return fit(union(list.map((n) => this.rect(n))), this.size.width, this.size.height, 48, this.config.minZoom, this.config.maxZoom);
  }

  // The view it opens on: all of its nodes; or, when it should be read and
  // they are too many to read at once, the most joined node and its
  // neighbours, at a zoom people read.
  private openingView(): View {
    const all = this.fitView();
    if (this.config.fit !== "readable" || all.zoom >= READABLE_ZOOM) return all;
    let heart: string | null = null;
    let most = -1;
    for (const id of this.order) {
      const count = this.byNode.get(id)?.size ?? 0;
      if (count > most) {
        most = count;
        heart = id;
      }
    }
    const near = new Set([heart!]);
    for (const e of this.byNode.get(heart!) ?? []) {
      const edge = this.edges.get(e);
      if (edge) near.add(edge.source).add(edge.target);
    }
    const focus = union([...near].map((id) => this.nodes.get(id)).filter((n): n is NodeModel => !!n).map((n) => this.rect(n)));
    const zoom = clamp(Math.max(READABLE_ZOOM, this.fitView(near).zoom), this.config.minZoom, this.config.maxZoom);
    return readableView(all, focus, this.size.width, this.size.height, zoom);
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

  /**
   * A move of the view the app sent (`Hakushi.Live.fit/2` and `focus/3`):
   * to `nodes`, a `box` of the canvas, or every node; or `focus` on nodes,
   * at the view's zoom unless they do not fit (or at `zoom`), and selected
   * unless `select` is false.
   */
  moveView(payload: Record<string, unknown>) {
    if (!this.fitted || this.size.width <= 0) {
      this.pendingMove = payload;
      this.schedule();
      return;
    }
    const padding = typeof payload.padding === "number" ? payload.padding : 48;
    const known = (list: unknown): string[] => (Array.isArray(list) ? list.filter((id): id is string => typeof id === "string" && this.nodes.has(id)) : []);
    const { width, height } = this.size;
    const { minZoom, maxZoom } = this.config;
    // The zoom that shows a box whole, with the padding around it.
    const zoomFor = (box: Rect) => clamp(Math.min((width - padding * 2) / Math.max(box.width, 1), (height - padding * 2) / Math.max(box.height, 1)), minZoom, maxZoom);
    let to: View;
    if (Array.isArray(payload.focus)) {
      const ids = known(payload.focus);
      if (!ids.length) return;
      const box = union(ids.map((id) => this.rect(this.nodes.get(id)!)))!;
      const zoom = typeof payload.zoom === "number" ? clamp(payload.zoom, minZoom, maxZoom) : Math.min(this.view.zoom, zoomFor(box));
      to = centerOn({ x: 0, y: 0, zoom }, box.x + box.width / 2, box.y + box.height / 2, width, height);
      if (payload.select !== false) this.selectFor({ nodes: ids, edges: [] });
    } else if (Array.isArray(payload.box) && payload.box.length === 4 && payload.box.every((n) => typeof n === "number")) {
      const [x, y, w, h] = payload.box as number[];
      const box = { x, y, width: w, height: h };
      to = centerOn({ x: 0, y: 0, zoom: zoomFor(box) }, x + w / 2, y + h / 2, width, height);
    } else {
      const ids = Array.isArray(payload.nodes) ? known(payload.nodes) : [...this.nodes.keys()];
      if (!ids.length) return;
      to = fit(union(ids.map((id) => this.rect(this.nodes.get(id)!))), width, height, padding, minZoom, maxZoom);
    }
    this.glideTo(to, payload.animate !== false);
  }

  // The view on its way to another, or there at once (without motion).
  private glideTo(to: View, animate: boolean) {
    const from = this.view;
    const distance = Math.hypot(to.x - from.x, to.y - from.y) + Math.abs(Math.log(to.zoom / from.zoom)) * this.size.width;
    if (!animate || reducedMotion() || distance < 1) {
      this.viewGlide = null;
      this.view = to;
    } else {
      this.viewGlide = { from, to, start: performance.now(), duration: Math.min(GLIDE_MAX, 160 + distance / 4), last: from };
    }
    this.schedule();
  }

  // A frame of the way: the middle of the screen goes straight from one
  // point of the canvas to the other, and the zoom by equal factors.
  private stepGlide() {
    const glide = this.viewGlide!;
    // The person panned or zoomed on the way: theirs is the view.
    if (this.view !== glide.last) {
      this.viewGlide = null;
      return;
    }
    const t = Math.min(1, (performance.now() - glide.start) / glide.duration);
    if (t >= 1) {
      this.viewGlide = null;
      this.view = glide.to;
      return;
    }
    const e = ease(t);
    const { width, height } = this.size;
    const middle = (v: View) => toCanvas(v, width / 2, height / 2);
    const a = middle(glide.from);
    const b = middle(glide.to);
    const zoom = glide.from.zoom * (glide.to.zoom / glide.from.zoom) ** e;
    this.view = centerOn({ x: 0, y: 0, zoom }, a.x + (b.x - a.x) * e, a.y + (b.y - a.y) * e, width, height);
    glide.last = this.view;
    this.schedule();
  }

  // Where the view came to rest, for the app (`on_viewport`): the part of
  // the canvas on the screen, and the zoom.
  private reportView() {
    if (!this.config.reportView || this.size.width <= 0 || !this.connected) return;
    const area = visible(this.view, this.size.width, this.size.height);
    const box = [area.x, area.y, area.width, area.height].map((n) => Math.round(n * 10) / 10);
    const zoom = Math.round(this.view.zoom * 1000) / 1000;
    const key = `${box.join(",")} ${zoom}`;
    if (key === this.reportedView) return;
    this.reportedView = key;
    this.live.push("hakushi:viewport", { box, zoom });
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
    on(this.root, "dragover", (e) => this.dragOver(e));
    on(this.root, "dragleave", (e) => {
      if (!this.root.contains(e.relatedTarget as Node | null)) this.root.removeAttribute("data-ui-dropping");
    });
    on(this.root, "drop", (e) => this.dropFiles(e));
    on(document, "paste", (e) => this.pasteFrom(e as ClipboardEvent));
    on(document, "copy", (e) => this.copied(e as ClipboardEvent));
    on(document, "cut", (e) => this.copied(e as ClipboardEvent));
  }

  private pointerDown(event: PointerEvent) {
    const target = event.target as Element;
    // A press away from a crop keeps it.
    if (this.cropping && !target.closest(".hakushi-crop")) this.finishCrop(true);
    this.root.removeAttribute("data-ui-keyboard");
    if (target.closest(".hakushi-controls, .hakushi-tools, .hakushi-paper-menu, .hakushi-minimap, .hakushi-edge-input, [data-hakushi-people], .hakushi-following")) return;
    if (event.pointerType === "pen") this.penSeen = true;
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

    // A tool of a kit: it draws, erases or lassoes over anything on the
    // canvas. Once a pen is used, a finger pans and only the pen draws.
    if (this.tool && !this.config.readonly && !(this.tool.mode === "lasso" && node && this.selected.has(node.id))) {
      event.preventDefault();
      this.root.focus({ preventScroll: true });
      if (event.pointerType === "touch" && this.penSeen) return this.startPan(event);
      this.capture(event);
      if (this.tool.mode === "draw") {
        const prefs = this.inkPrefsOf(this.tool);
        const stroke: InkStroke = { tool: `${this.tool.kit}:${this.tool.tool}`, color: prefs.color, size: prefs.size, points: [] };
        this.gesture = { kind: "ink", pointer: event.pointerId, tool: this.tool, stroke, pen: event.pointerType === "pen" };
        this.addInkPoints(event);
      } else if (this.tool.mode === "erase") {
        this.gesture = { kind: "erase", pointer: event.pointerId, tool: this.tool, last: at, hit: new Set() };
        this.eraseAlong(at, at);
      } else if (this.tool.mode === "box" || this.tool.mode === "line") {
        const start = this.config.snap && this.tool.mode === "box" ? { x: snapToGrid(at.x, this.config.grid), y: snapToGrid(at.y, this.config.grid) } : at;
        this.gesture = { kind: "shape", pointer: event.pointerId, tool: this.tool, start, end: start, square: event.shiftKey };
      } else {
        const base = event.shiftKey ? new Set(this.selected) : new Set<string>();
        if (!event.shiftKey) this.select([]);
        this.gesture = { kind: "lasso", pointer: event.pointerId, points: [at], base };
      }
      this.schedule();
      return;
    }

    // The ends of the selected edge come first, over the handles they sit on.
    const knob = this.knobAt(event);
    if (knob && !this.config.readonly) {
      event.preventDefault();
      this.startReconnect(event, knob.edge, knob.end, at);
      return;
    }
    if (handleEl && node && !this.config.readonly && !node.locked) {
      event.preventDefault();
      this.startConnect(event, node, handleEl, at);
      return;
    }
    const rotator = target.closest<HTMLElement>(".hakushi-rotator");
    if (rotator && node && !this.config.readonly) {
      event.preventDefault();
      this.startRotate(event, node);
      return;
    }
    const resizer = target.closest<HTMLElement>(".hakushi-resizer");
    if (resizer && node) {
      event.preventDefault();
      this.capture(event);
      this.gesture = { kind: "resize", pointer: event.pointerId, id: node.id, corner: resizer.dataset.corner!, start: at, rect: this.rect(node), aspect: aspectOf(node.el) };
      return;
    }
    const grips = node?.el.querySelectorAll("[data-hakushi-drag]");
    const onGrip = !grips || grips.length === 0 || target.closest("[data-hakushi-drag]") !== null;
    // Inside a group, off the part it is dragged by: the paper of the group,
    // where a drag draws a box over its nodes.
    if (node && !(node.group && !onGrip)) {
      if (interactive(target, node.el)) return;
      if (event.shiftKey || event.metaKey || event.ctrlKey) {
        this.toggleSelect(node.id);
      } else if (!this.selected.has(node.id)) {
        this.select([node.id]);
      }
      if (!onGrip || !this.arranges) return;
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
    // A box drawn in a group selects in it: not the group, nor those around it.
    const within = new Set<string>();
    for (let g = node?.group ? node : undefined; g; g = g.parent ? this.nodes.get(g.parent) : undefined) within.add(g.id);
    this.capture(event);
    this.gesture = { kind: "box", pointer: event.pointerId, start: at, end: at, base, within };
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
    const chosen = [...this.selected].filter((id) => !this.nodes.get(id)?.locked);
    if (!chosen.includes(primary)) return;
    // The nodes in a dragged group go with it.
    const ids = [...this.withDescendants(chosen)].filter((id) => !this.nodes.get(id)?.locked);
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

  // An end of the one selected edge within reach of the pointer.
  private knobAt(event: PointerEvent): { edge: string; end: "source" | "target" } | null {
    if (this.selectedEdges.size !== 1) return null;
    const id = [...this.selectedEdges][0];
    const edge = this.edges.get(id);
    const geometry = edge && this.geometry(edge);
    if (!geometry) return null;
    const p = this.local(event);
    for (const [end, at] of [["target", geometry.to], ["source", geometry.from]] as const) {
      const screen = { x: at.x * this.view.zoom + this.view.x, y: at.y * this.view.zoom + this.view.y };
      if (Math.hypot(screen.x - p.x, screen.y - p.y) <= 10) return { edge: id, end };
    }
    return null;
  }

  // The end of a selected edge, dragged: the other end stays, and the
  // edge is drawn from it as a new one would be.
  private startReconnect(event: PointerEvent, id: string, end: "source" | "target", at: Point) {
    const edge = this.edges.get(id);
    if (!edge) return;
    const fixed = end === "target" ? { node: edge.source, handle: edge.sourceHandle } : { node: edge.target, handle: edge.targetHandle };
    const fixedNode = this.nodes.get(fixed.node);
    if (!fixedNode) return;
    const fixedHandle = this.handleOf(fixedNode, fixed.handle, end === "target" ? "source" : "target");
    this.capture(event);
    this.gesture = { kind: "connect", pointer: event.pointerId, from: fixed, fromHandle: fixedHandle, reverse: end === "source", at, target: null, reconnect: id };
    this.dirty.add(id);
    this.markTargets();
    this.schedule();
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
        for (const node of this.nodes.values()) if (!g.within.has(node.id) && intersects(box, this.rect(node))) ids.add(node.id);
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
        if (!g.moved) {
          g.moved = true;
          for (const id of g.origin.keys()) {
            const n = this.nodes.get(id);
            if (n) this.decorate(n);
          }
        }
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
        this.markDropTarget(g);
        this.sendPeer();
        this.schedule();
        return;
      }
      case "resize": {
        const node = this.nodes.get(g.id);
        if (!node) return;
        const dx = at.x - g.start.x;
        const dy = at.y - g.start.y;
        if (g.aspect && !event.shiftKey) {
          const r = aspectResize(g.rect, g.corner, dx, dy, g.aspect);
          Object.assign(node, { x: round(r.x), y: round(r.y), width: round(r.width), height: round(r.height), fixed: true });
          this.decorate(node);
          this.measureHandles(node);
          this.touchNode(node.id);
          this.schedule();
          return;
        }
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
      case "ink": {
        if (event.pointerId !== g.pointer) return;
        this.addInkPoints(event);
        this.sendPeer();
        this.schedule();
        return;
      }
      case "erase": {
        if (event.pointerId !== g.pointer) return;
        this.eraseAlong(g.last, at);
        g.last = at;
        this.sendPeer();
        this.schedule();
        return;
      }
      case "shape": {
        if (event.pointerId !== g.pointer) return;
        g.end = this.config.snap && g.tool.mode === "box" ? { x: snapToGrid(at.x, this.config.grid), y: snapToGrid(at.y, this.config.grid) } : at;
        g.square = event.shiftKey;
        if (g.tool.mode === "line") this.markLineEnd(g.end, g.start);
        this.schedule();
        return;
      }
      case "rotate": {
        if (event.pointerId !== g.pointer) return;
        const angle = (Math.atan2(at.y - g.center.y, at.x - g.center.x) * 180) / Math.PI;
        let deg = g.base + angle - g.from;
        if (event.shiftKey) deg = Math.round(deg / 15) * 15;
        g.deg = ((Math.round(deg) % 360) + 360) % 360;
        g.el.style.setProperty("--hakushi-rotation", `${g.deg}deg`);
        return;
      }
      case "lasso": {
        if (event.pointerId !== g.pointer) return;
        const last = g.points[g.points.length - 1];
        if (Math.hypot(at.x - last.x, at.y - last.y) * this.view.zoom >= 2) g.points.push(at);
        this.sendPeer();
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
        for (const id of g.origin.keys()) {
          const n = this.nodes.get(id);
          if (n) this.decorate(n);
        }
        this.root.querySelectorAll("[data-ui-drop-target]").forEach((e) => e.removeAttribute("data-ui-drop-target"));
        // Arranged only, a node stays in its group.
        if (g.moved && !cancelled) this.commitMove(g.origin, this.config.readonly ? new Map() : this.dropParents(g.origin));
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
        if (g.reconnect) this.dirty.add(g.reconnect);
        if (!cancelled && g.target) this.commitConnect(g);
        break;
      case "ink":
        if (!cancelled) this.commitInk(g.stroke);
        break;
      case "erase":
        if (cancelled) this.unerase(g.hit);
        else this.commitErase(g.hit);
        break;
      case "lasso":
        if (!cancelled) this.selectLassoed(g.points, g.base);
        break;
      case "shape":
        this.root.querySelectorAll("[data-ui-target]").forEach((e) => e.removeAttribute("data-ui-target"));
        if (!cancelled) this.commitShape(g);
        break;
      case "rotate":
        if (cancelled || g.deg === g.base) g.el.style.removeProperty("--hakushi-rotation");
        else
          this.push("hakushi:edit", { node: g.id, action: "rotate", value: g.deg }, (reply) => {
            if (reply.error || reply.ok === false) g.el.style.removeProperty("--hakushi-rotation");
          });
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
    if (g.kind === "connect") {
      this.unmarkTargets();
      if (g.reconnect) this.dirty.add(g.reconnect);
    }
    if (g.kind === "box") this.boxEl.hidden = true;
    if (g.kind === "erase") this.unerase(g.hit);
    if (g.kind === "rotate") g.el.style.removeProperty("--hakushi-rotation");
    if (g.kind === "shape") this.root.querySelectorAll("[data-ui-target]").forEach((e) => e.removeAttribute("data-ui-target"));
    if (g.kind === "ink" || g.kind === "erase" || g.kind === "lasso") this.sendPeer();
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
    // A canvas in a page that scrolls (an embed) leaves the wheel to the
    // page, and zooms with ⌘, Ctrl or a pinch.
    if (this.config.wheel === "scroll" && !event.ctrlKey && !event.metaKey) return;
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
    // A tool draws, and makes nothing of a double click.
    if (this.tool) return;
    const target = event.target as Element;
    // The text of a node that has one (`data-hakushi-text`), written in place.
    // The canvas has the pointer (a press captures it): what is under it.
    const under = document.elementFromPoint(event.clientX, event.clientY) ?? target;
    const textNode = under.closest<HTMLElement>(".hakushi-node");
    const textNodeModel = textNode && this.nodesEl.contains(textNode) ? this.nodes.get(textNode.dataset.id || "") : undefined;
    if (textNodeModel && !this.config.readonly && !textNodeModel.locked && textNode!.querySelector("[data-hakushi-text]") && !interactive(under, textNode!)) {
      event.preventDefault();
      this.editText(textNodeModel);
      return;
    }
    const edgeId = target.closest<SVGGElement>(".hakushi-edge")?.dataset.edge ?? target.closest<HTMLElement>(".hakushi-edge-label")?.dataset.edge;
    if (edgeId && !this.config.readonly) {
      this.editLabel(edgeId);
      return;
    }
    const nodeEl = target.closest<HTMLElement>(".hakushi-node");
    const group = nodeEl && this.nodes.get(nodeEl.dataset.id || "")?.group;
    // On the paper, or on a group's inside.
    if ((nodeEl && (!group || interactive(target, nodeEl) || target.closest("[data-hakushi-drag]"))) || target.closest(".hakushi-controls, .hakushi-tools, .hakushi-minimap, [data-hakushi-people], .hakushi-following")) return;
    if (this.config.readonly || !this.config.newNode) return;
    const at = this.canvasPoint(event);
    this.drop(null, this.config.snap ? { x: snapToGrid(at.x, this.config.grid), y: snapToGrid(at.y, this.config.grid) } : at);
  }

  // -- Connecting --------------------------------------------------------------

  // The handles an edge from the gesture's end may end on.
  private validTargets(g: Extract<Gesture, { kind: "connect" }>): { end: End; handle: Handle | null }[] {
    const out: { end: End; handle: Handle | null }[] = [];
    const want = g.reverse ? "source" : "target";
    const edges = g.reconnect ? [...this.edges.values()].filter((e) => e.id !== g.reconnect) : [...this.edges.values()];
    for (const node of this.nodes.values()) {
      if (this.gone.has(node.id)) continue;
      const handles = node.handles.filter((h) => h.kind === "both" || h.kind === want);
      const candidates: (Handle | null)[] = handles.length ? handles : node.handles.length ? [] : [null];
      for (const handle of candidates) {
        const end = { node: node.id, handle: handle?.id ?? null };
        const ok = g.reverse
          ? check(this.config.rules, edges, end, handle, g.from, g.fromHandle)
          : check(this.config.rules, edges, g.from, g.fromHandle, end, handle);
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
    if (g.reconnect) {
      const id = g.reconnect;
      this.push("hakushi:change", { op: "reconnect", edges: [{ id, source: source.node, sourceHandle: source.handle, target: target.node, targetHandle: target.handle }] }, () => {
        this.dirty.add(id);
        this.schedule();
      });
      return;
    }
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
      // The app made another change of it (on_change): what this canvas
      // showed of it goes, and the server's shows.
      if (reply.rewritten === true && event === "hakushi:change") this.resync(payload as { nodes?: unknown[]; edges?: unknown[] });
      onReply?.(reply);
      if (Array.isArray(reply.select)) {
        // The new nodes may come after the reply: they are selected as
        // they come.
        this.pendingSelect = reply.select as string[];
        this.selectPending();
      }
    });
  }

  // The nodes and edges of a change, as the server has them: their places,
  // read again from their elements; those hidden on their way out, back.
  private resync(change: { nodes?: unknown[]; edges?: unknown[] }) {
    const idOf = (item: unknown): string | null => (typeof item === "string" ? item : typeof (item as { id?: unknown })?.id === "string" ? (item as { id: string }).id : null);
    const nodes = (change.nodes ?? []).map(idOf).filter((id): id is string => id !== null);
    const edges = (change.edges ?? []).map(idOf).filter((id): id is string => id !== null);
    const gone = new Set([...this.withDescendants(nodes), ...edges]);
    for (const id of [...gone]) for (const e of this.byNode.get(id) ?? []) gone.add(e);
    for (const id of gone) this.gone.delete(id);
    for (const id of this.withDescendants(nodes)) {
      const node = this.nodes.get(id);
      if (node?.el.isConnected) this.readNode(node.el);
    }
    this.pending = null;
    this.refresh(gone);
  }

  private selectPending() {
    const ids = this.pendingSelect;
    if (!ids || !ids.every((id) => this.nodes.has(id))) return;
    this.pendingSelect = null;
    this.select(ids);
    if (ids.length && !ids.some((id) => this.isOnScreen(id))) this.revealNodes(ids);
  }

  // The groups the dragged nodes land in: for each node whose group is
  // not dragged with it, the innermost group under its middle, if that is
  // not the group it is in.
  private dropParents(origin: Map<string, Point>): Map<string, string | null> {
    const parents = new Map<string, string | null>();
    const dragged = new Set(origin.keys());
    for (const id of dragged) {
      const node = this.nodes.get(id);
      if (!node || (node.parent && dragged.has(node.parent))) continue;
      const target = this.groupAt(this.center(node), dragged);
      const parent = target?.id ?? null;
      if (parent !== node.parent) parents.set(id, parent);
    }
    return parents;
  }

  private markDropTarget(g: Extract<Gesture, { kind: "drag" }>) {
    if (this.config.readonly) return;
    const primary = this.nodes.get(g.primary);
    const target = primary && !(primary.parent && g.origin.has(primary.parent)) ? this.groupAt(this.center(primary), new Set(g.origin.keys())) : null;
    for (const el of this.root.querySelectorAll("[data-ui-drop-target]")) if (el !== target?.el) el.removeAttribute("data-ui-drop-target");
    if (target && target.id !== primary?.parent) target.el.setAttribute("data-ui-drop-target", "");
    else target?.el.removeAttribute("data-ui-drop-target");
  }

  private commitMove(origin: Map<string, Point>, parents: Map<string, string | null> = new Map(), said?: string) {
    const places = [...origin.keys()].map((id) => {
      const node = this.nodes.get(id)!;
      return parents.has(id) ? { id, x: node.x, y: node.y, parent: parents.get(id) } : { id, x: node.x, y: node.y };
    });
    if (!parents.size && places.every((p) => p.x === origin.get(p.id)!.x && p.y === origin.get(p.id)!.y)) return;
    const name = this.nodes.get(places[0].id)?.label ?? places[0].id;
    this.push("hakushi:change", { op: "move", nodes: places }, (reply) => {
      if (reply.error) this.revert(origin);
      else this.announce(said ?? (places.length === 1 ? this.messages.t("movedOne", { name }) : this.messages.count("moved", places.length)));
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
    // The nodes in a deleted group go with it, and the edges of all.
    const hide = new Set([...this.withDescendants(nodes), ...edges]);
    for (const id of [...hide]) for (const e of this.byNode.get(id) ?? []) hide.add(e);
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
    if (this.arranges) this.push("hakushi:undo", {}, (reply) => reply.error && this.announce(String(reply.error)));
  }

  redo() {
    if (this.arranges) this.push("hakushi:redo", {}, (reply) => reply.error && this.announce(String(reply.error)));
  }

  /** A new node at a point of the canvas: for an item, or a double click (`item` null). */
  drop(item: string | null, at?: Point) {
    if (this.config.readonly || !this.config.newNode) return;
    const p = at ?? toCanvas(this.view, this.size.width / 2, this.size.height / 2);
    // Dropped in a group, the new node is in it.
    const group = this.groupAt(p, new Set());
    this.push("hakushi:drop", { item, x: round(p.x), y: round(p.y), parent: group?.id ?? null });
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

  /**
   * A selection the app sent (`Hakushi.Live.select/3`): the nodes and edges
   * the canvas has, which the app does not hear of again; with `reveal`,
   * brought into view.
   */
  selectFor(payload: Record<string, unknown>) {
    const ids = (list: unknown, has: (id: string) => boolean): string[] => (Array.isArray(list) ? list.filter((id): id is string => typeof id === "string" && has(id)) : []);
    const nodes = ids(payload.nodes, (id) => this.nodes.has(id));
    const edges = ids(payload.edges, (id) => this.edges.has(id));
    this.selectedEdges = new Set(edges);
    this.setSelection(new Set(nodes));
    this.reportedSelection = selectionKey(nodes, edges);
    this.selectionChanged();
    if (payload.reveal === true && nodes.length && !nodes.some((id) => this.isOnScreen(id))) this.revealNodes(nodes);
  }

  // What the person selected, for the app (`on_select`), when it is not
  // what the app heard last.
  private reportSelection() {
    if (!this.config.reportSelect) return;
    const nodes = [...this.selected];
    const edges = [...this.selectedEdges];
    const key = selectionKey(nodes, edges);
    if (key === this.reportedSelection) return;
    this.reportedSelection = key;
    this.live.push("hakushi:select", { nodes, edges });
  }

  private selectionChanged() {
    this.allDirty = true;
    this.reportSelection();
    this.drawStylePanel();
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
    node.el.setAttribute("aria-description", [this.near(node), this.describe(node)].filter(Boolean).join(". "));
    if (!this.selected.has(node.id)) this.select([node.id]);
    this.revealNodes([node.id]);
  }

  // Where a node is that says so (a drawing: "Near Release"), by the
  // nearest node of another kind, for screen readers.
  private near(node: NodeModel): string {
    if (!node.el.querySelector("[data-hakushi-near]")) return "";
    const box = this.rect(node);
    const c = this.center(node);
    let best: { node: NodeModel; gap: number; d: number } | null = null;
    for (const other of this.nodes.values()) {
      if (other.id === node.id || this.gone.has(other.id) || other.el.querySelector("[data-hakushi-near]")) continue;
      const r = this.rect(other);
      const gap = Math.hypot(Math.max(0, r.x - (box.x + box.width), box.x - (r.x + r.width)), Math.max(0, r.y - (box.y + box.height), box.y - (r.y + r.height)));
      const o = this.center(other);
      const d = Math.hypot(o.x - c.x, o.y - c.y);
      if (!best || gap < best.gap || (gap === best.gap && d < best.d)) best = { node: other, gap, d };
    }
    return best ? this.messages.t("near", { name: best.node.label }) : "";
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
    if (this.cropping && (event.key === "Enter" || event.key === "Escape")) {
      event.preventDefault();
      return this.finishCrop(event.key === "Enter");
    }
    if (event.key === "Tab" || event.key.startsWith("Arrow")) this.root.setAttribute("data-ui-keyboard", "");
    const target = event.target as HTMLElement;
    // The buttons of the controls are the canvas's: its keys work there, but
    // Enter and Space, which press them, and Tab.
    if (target.closest(".hakushi-controls, .hakushi-tools, .hakushi-style-panel")) {
      if (event.key === "Enter" || event.key === " " || event.key === "Tab") return;
    } else if (editable(target) || (target !== this.root && !target.classList.contains("hakushi-node") && interactive(target, this.root))) {
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
      else if (this.tool) this.setTool(null);
      else this.select([]);
      return;
    }
    // The tools of the kits, by their letters, and V for the pointer. Tools
    // of two kits with one letter: the letter again takes the next.
    if (!mod && !event.altKey && !event.shiftKey && this.toolsEl && key.length === 1) {
      const letter = key.toLowerCase();
      const tools = (this.config.tools ?? []).filter((t) => t.key === letter);
      if (tools.length || letter === "v") {
        event.preventDefault();
        const at = this.tool ? tools.indexOf(this.tool) : -1;
        const tool = tools[(at + 1) % Math.max(tools.length, 1)];
        return this.setTool(tool ? `${tool.kit}:${tool.tool}` : null);
      }
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
      // A canvas that takes files: what the clipboard has comes with the
      // paste event (pasteFrom), and the nodes copied here unless it has a
      // file or an image's address.
      if (this.config.files) {
        clearTimeout(this.pasteTimer);
        this.pasteTimer = window.setTimeout(() => this.paste(), 50);
        return;
      }
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
    if (key === "L" && event.shiftKey && !mod) {
      event.preventDefault();
      return void this.layout();
    }
    if ((key === "c" || key === "C") && !mod && !event.altKey && !event.shiftKey) {
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
      if (this.selected.size && this.arranges) return this.nudgeBy(key, event.shiftKey);
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
    for (const id of this.withDescendants(this.selected)) {
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
    const peer: Peer = this.peers.get(id) ?? { cursor: null, view: null, selected: [], dragging: new Map(), seen: 0, el: null, from: null, dragFrom: new Map(), start: 0, duration: 0, ink: null, files: [], fileEls: [] };
    // Their page's session (Issho's pointers), not their canvas's: only whether those draw them here.
    if (!("cursor" in payload)) {
      peer.paged = payload.paged === true;
      peer.seen = Date.now();
      this.peers.set(id, peer);
      this.schedule();
      return;
    }
    // `viewport`, not `view`: a person's `view` is Issho's, what their page shows.
    const view = payload.viewport as [number, number, number, number] | null | undefined;
    peer.view = Array.isArray(view) && view.length === 4 && view[2] > 0 && view[3] > 0 ? view : null;
    const cursor = payload.cursor as [number, number] | null;
    const dragging = new Map(((payload.dragging as [string, number, number][]) ?? []).map(([n, x, y]) => [n, { x, y }]));
    // From where the cursor and the nodes are drawn now, to where they go.
    const here = peer.cursor && peer.from ? this.onTheWay(peer, peer.from, peer.cursor) : peer.cursor;
    const dragFrom = new Map<string, Point>();
    for (const [n, to] of dragging) {
      const before = peer.dragging.get(n);
      const node = this.nodes.get(n);
      const from = before ? this.onTheWay(peer, peer.dragFrom.get(n) ?? before, before) : node ? { x: node.x, y: node.y } : to;
      dragFrom.set(n, from);
    }
    peer.cursor = cursor ? { x: cursor[0], y: cursor[1] } : null;
    peer.from = here && peer.cursor ? here : peer.cursor;
    peer.dragFrom = dragFrom;
    const far = Math.max(
      peer.from && peer.cursor ? Math.hypot(peer.cursor.x - peer.from.x, peer.cursor.y - peer.from.y) : 0,
      ...[...dragging].map(([n, to]) => Math.hypot(to.x - dragFrom.get(n)!.x, to.y - dragFrom.get(n)!.y)),
    ) * this.view.zoom;
    peer.start = performance.now();
    peer.duration = far < 1 || reducedMotion() ? 0 : Math.min(GLIDE_MAX, Math.max(60, far * 0.8));
    const before = new Set([...peer.selected, ...peer.dragging.keys()]);
    const draggedBefore = new Set(peer.dragging.keys());
    peer.selected = (payload.selected as string[]) ?? [];
    peer.dragging = dragging;
    peer.ink = readInk(payload.ink);
    peer.files = ((payload.files as unknown[]) ?? []).filter((f): f is number[] => Array.isArray(f) && f.length === 5 && f.every((n) => typeof n === "number"));
    peer.seen = Date.now();
    this.peers.set(id, peer);
    if (id === this.followKey) {
      this.showFollowed(peer);
      this.drawFollowing();
    }
    for (const n of new Set([...before, ...peer.selected, ...peer.dragging.keys()])) {
      const node = this.nodes.get(n);
      if (!node) continue;
      this.decorate(node);
      // Only a node they drag (or let go) moves: one they have selected is
      // drawn in their colour, and the layout is as it was.
      if (draggedBefore.has(n) || dragging.has(n)) this.touchNode(n);
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
    for (const f of peer.fileEls) f.remove();
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
    // On a page with Issho's pointers of this canvas's room, they draw
    // whom they know here (the people of that page of the room); the
    // canvas draws the others (on another page, in an embed of it).
    const page = this.docEl !== null && document.querySelector(`.issho-pointers[data-room="${CSS.escape(this.room)}"]`) !== null;
    for (const [id, peer] of this.peers) {
      // On their way: drawn again at the next frame, with the nodes they drag.
      if (this.moving(peer)) {
        for (const n of peer.dragging.keys()) {
          const node = this.nodes.get(n);
          if (node) {
            this.decorate(node);
            this.touchNode(n);
          }
        }
        this.schedule();
      }
      const person = this.people.get(id);
      this.drawPeerFiles(peer, person?.color ?? "");
      if (!peer.cursor || !person || (page && peer.paged)) {
        if (peer.el) peer.el.hidden = true;
        continue;
      }
      if (!peer.el) {
        peer.el = el("div", { class: "hakushi-cursor" }, [el("span", {}, [person.name ?? person.id])]);
        peer.el.style.setProperty("--hakushi-peer", person.color);
        this.cursorsEl.append(peer.el);
      }
      peer.el.hidden = false;
      const at = peer.from ? this.onTheWay(peer, peer.from, peer.cursor) : peer.cursor;
      peer.el.style.translate = `${at.x * this.view.zoom + this.view.x}px ${at.y * this.view.zoom + this.view.y}px`;
    }
  }

  // The person's cursor, selection and drag, for the others: at most every PEER_INTERVAL.
  private sendPeer() {
    if (!this.config.live || !this.connected) return;
    const active = activeIn.get(this.room);
    if (active && active !== this && active.root.isConnected) return;
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
    const z = this.view.zoom;
    this.live.push("hakushi:peer", {
      cursor: this.pointer ? [round(this.pointer.x), round(this.pointer.y)] : null,
      selected: [...this.selected],
      dragging,
      viewport: this.size.width > 0 ? [round(-this.view.x / z), round(-this.view.y / z), round(this.size.width / z), round(this.size.height / z)] : null,
      ink: g?.kind === "ink" ? this.inkToSend(g.stroke) : null,
      files: [...this.filePlaces.values()].map((f) => [round(f.box.x), round(f.box.y), round(f.box.width), round(f.box.height), f.progress]),
    });
  }

  private peerQueued = false;

  // -- Layout ------------------------------------------------------------------

  /**
   * Lays the nodes out (`algorithm` and `direction`, the way the person
   * chose in the menu, else the canvas's `layout`, unless given): the
   * selected nodes when two or more are, else every node. A group is laid out as one box, with what is in
   * it; locked nodes stay. The nodes glide to their places, and the change
   * is one move, which undoes at once.
   */
  async layout(options: { direction?: "right" | "down"; algorithm?: Algorithm } = {}): Promise<void> {
    if (!this.arranges || this.gesture) return;
    const plan = this.planLayout(this.selected.size >= 2 ? [...this.selected] : [...this.order], options);
    if (!plan) return;
    await this.glide(plan.origin, plan.target);
    this.commitMove(plan.origin, new Map(), this.messages.t("laidOut", { n: plan.count }));
  }

  // Where a layout puts the chosen nodes: those of no group among them (a
  // group moves with what is in it), and not the locked ones.
  private planLayout(
    chosen: string[],
    options: { direction?: "right" | "down"; algorithm?: Algorithm },
  ): { origin: Map<string, Point>; target: Map<string, Point>; count: number } | null {
    const set = new Set(chosen);
    const top = (id: string): string => {
      let node = this.nodes.get(id);
      while (node?.parent && set.has(node.parent)) node = this.nodes.get(node.parent);
      return node?.id ?? id;
    };
    const boxes = chosen
      .map((id) => this.nodes.get(id)!)
      .filter((n) => n && top(n.id) === n.id && !n.locked && !this.gone.has(n.id))
      .map((n) => ({ id: n.id, width: n.width, height: n.height }));
    if (boxes.length < 2) return null;
    const laid = new Set(boxes.map((b) => b.id));
    const edges = [...this.edges.values()]
      .map((e) => ({ source: top(e.source), target: top(e.target) }))
      .filter((e) => laid.has(e.source) && laid.has(e.target));

    const choice = this.layoutChoice();
    const places = place(boxes, edges, {
      algorithm: options.algorithm ?? choice.algorithm,
      direction: options.direction ?? choice.direction,
      aspect: this.size.width > 0 && this.size.height > 0 ? this.size.width / this.size.height : 1.6,
    });
    // In place: the laid out nodes keep the top left corner they had.
    const before = union(boxes.map((b) => this.rect(this.nodes.get(b.id)!)))!;
    const after = union(boxes.map((b) => ({ ...places.get(b.id)!, width: b.width, height: b.height })))!;
    const shift = { x: before.x - after.x, y: before.y - after.y };

    const origin = new Map<string, Point>();
    const target = new Map<string, Point>();
    for (const b of boxes) {
      const node = this.nodes.get(b.id)!;
      const p = places.get(b.id)!;
      const to = { x: round(p.x + shift.x), y: round(p.y + shift.y) };
      const dx = to.x - node.x;
      const dy = to.y - node.y;
      for (const id of this.withDescendants([b.id])) {
        const n = this.nodes.get(id);
        if (!n || n.locked) continue;
        origin.set(id, { x: n.x, y: n.y });
        target.set(id, { x: round(n.x + dx), y: round(n.y + dy) });
      }
    }
    return { origin, target, count: boxes.length };
  }

  // -- Tidy as it opens -----------------------------------------------------------
  //
  // A canvas with `tidy` lays its nodes out before anyone sees them: the
  // server draws it with its nodes hidden (data-tidy) and a spinner, and
  // the first frame with a size measures the nodes, lays them out at once,
  // and shows them, fitted. The places are a move, as a tidy up's, on a
  // canvas whose nodes people move; on a read-only one they are this
  // page's only. A shared canvas keeps the room's places.

  private tidying = false;
  private tidyStarted = false;

  private startTidy() {
    if (this.tidyStarted) return;
    this.tidyStarted = true;
    // A frame for the spinner to show, then the work.
    requestAnimationFrame(() =>
      setTimeout(() => {
        try {
          this.tidyNow();
        } finally {
          this.tidying = false;
          this.root.setAttribute("data-ui-tidied", "");
          this.schedule();
        }
      }),
    );
  }

  private tidyNow() {
    // Their sizes now, as drawn: the canvas may have been hidden when it read them.
    for (const node of this.nodes.values()) {
      if (node.fixed) continue;
      node.width = node.el.offsetWidth || node.width;
      node.height = node.el.offsetHeight || node.height;
    }
    const plan = this.planLayout([...this.order], {});
    if (!plan) return;
    for (const [id, to] of plan.target) {
      const node = this.nodes.get(id);
      if (!node) continue;
      node.x = to.x;
      node.y = to.y;
      node.el.style.translate = `${node.x}px ${node.y}px`;
      this.decorate(node);
      this.touchNode(id);
    }
    // Not undone, nor taken back if the server refuses it: the pile it
    // opened as is no place to go back to.
    if (this.arranges) {
      const nodes = [...plan.target].map(([id, p]) => ({ id, x: p.x, y: p.y }));
      this.push("hakushi:change", { op: "move", nodes, opened: true });
    }
  }

  // The nodes from their places to others, in a quarter of a second (at
  // once with reduced motion).
  private glide(origin: Map<string, Point>, target: Map<string, Point>): Promise<void> {
    const set = (t: number) => {
      const k = t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
      for (const [id, from] of origin) {
        const node = this.nodes.get(id);
        const to = target.get(id)!;
        if (!node) continue;
        node.x = t >= 1 ? to.x : from.x + (to.x - from.x) * k;
        node.y = t >= 1 ? to.y : from.y + (to.y - from.y) * k;
        node.el.style.translate = `${node.x}px ${node.y}px`;
        this.touchNode(id);
      }
      this.schedule();
    };
    if (prefersReducedMotion()) {
      set(1);
      return Promise.resolve();
    }
    return new Promise((done) => {
      const start = performance.now();
      const step = (now: number) => {
        const t = Math.min(1, (now - start) / 250);
        set(t);
        if (t < 1) requestAnimationFrame(step);
        else done();
      };
      requestAnimationFrame(step);
    });
  }

  // -- Export --------------------------------------------------------------------

  /** The whole canvas as an image (a PNG, unless `format: "svg"`): every node and edge, not only those on the screen. */
  async exportImage(options: Partial<ExportOptions> = {}): Promise<Blob> {
    this.drawAllEdges();
    const boxes = [...this.nodes.values()].filter((n) => !this.gone.has(n.id)).map((n) => this.rect(n));
    for (const view of this.edgeViews.values()) boxes.push(grow(view.box, -80));
    const box = union(boxes) ?? { x: 0, y: 0, width: 1, height: 1 };
    return exportImage(this.root, this.world, box, options);
  }

  /** Downloads the canvas as an image, named after the canvas. */
  async download(options: Partial<ExportOptions> = {}): Promise<void> {
    const format = options.format ?? "png";
    let blob: Blob;
    try {
      blob = await this.exportImage({ ...options, format });
    } catch {
      // A browser that will not draw the canvas's SVG to a PNG (a node with
      // an image of another origin): the SVG itself.
      blob = await this.exportImage({ ...options, format: "svg" });
    }
    const a = el("a", { href: URL.createObjectURL(blob), download: `${options.filename ?? this.id}.${blob.type === "image/svg+xml" ? "svg" : "png"}` });
    document.body.append(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 10_000);
  }

  // Every edge's path, the culled ones too, for an export.
  private drawAllEdges() {
    this.allDirty = true;
    this.drawEdges(false);
    for (const view of this.edgeViews.values()) this.showEdge(view, true);
    this.culledView = null;
  }

  destroy() {
    this.togglePaperMenu(false);
    this.toggleLayoutMenu(false);
    clearTimeout(this.panTimer);
    for (const o of this.observers) o.disconnect();
    this.scheme?.removeEventListener("change", this.onScheme);
    for (const cleanup of this.cleanups) cleanup();
    cancelAnimationFrame(this.frame);
    clearTimeout(this.noticeTimer);
    clearTimeout(this.peerTimer);
    clearTimeout(this.pasteTimer);
    for (const f of this.filePlaces.values()) if (f.blob) URL.revokeObjectURL(f.blob);
  }
}

// A placeholder of a file, at its box, with its progress (0 to 100).
function placeFile(element: HTMLElement, box: Rect, progress: number) {
  Object.assign(element.style, { translate: `${box.x}px ${box.y}px`, width: `${box.width}px`, height: `${box.height}px` });
  const bar = element.querySelector<HTMLElement>(".hakushi-file-bar > span");
  if (bar) bar.style.width = `${Math.max(0, Math.min(100, progress))}%`;
}

// The aspect ratio an image keeps (`data-hakushi-aspect`), or null.
function aspectOf(element: HTMLElement): number | null {
  const value = Number(element.querySelector("[data-hakushi-aspect]")?.getAttribute("data-hakushi-aspect"));
  return Number.isFinite(value) && value > 0 ? value : null;
}

// The width and height of an image file, from the browser's own decoding, or null.
function pixelsOf(url: string): Promise<{ width: number; height: number } | null> {
  return new Promise((resolve) => {
    const image = new Image();
    image.onload = () => resolve(image.naturalWidth > 0 ? { width: image.naturalWidth, height: image.naturalHeight } : null);
    image.onerror = () => resolve(null);
    image.src = url;
  });
}

// A line drawn by someone, as it comes: checked, as the server checked it.
function readInk(value: unknown): InkStroke | null {
  const ink = value as Partial<InkStroke> | null | undefined;
  if (!ink || typeof ink.tool !== "string" || typeof ink.color !== "string" || typeof ink.size !== "number" || !Array.isArray(ink.points)) return null;
  const points = ink.points.filter((p): p is InkPoint => Array.isArray(p) && p.length === 3 && p.every((n) => typeof n === "number"));
  return points.length ? { tool: ink.tool, color: ink.color, size: ink.size, points } : null;
}

// Whether a point (of the stroke's box) is on a stroke's line, or near it.
function hitsStroke(aim: SVGGeometryElement, x: number, y: number, reach: number): boolean {
  const svgEl = aim.ownerSVGElement;
  try {
    const point = svgEl ? svgEl.createSVGPoint() : new DOMPoint(x, y);
    point.x = x;
    point.y = y;
    return aim.isPointInStroke(point);
  } catch {
    // An engine that cannot tell (a hidden element): the line's points.
  }
  const length = aim.getTotalLength();
  const steps = Math.min(400, Math.max(1, Math.ceil(length / 3)));
  for (let i = 0; i <= steps; i++) {
    const p = aim.getPointAtLength((length * i) / steps);
    if (Math.hypot(p.x - x, p.y - y) <= reach) return true;
  }
  return false;
}

// A selection, the same whatever the order of its ids.
function selectionKey(nodes: string[], edges: string[]): string {
  return JSON.stringify([[...nodes].sort(), [...edges].sort()]);
}

function toggle(element: Element, name: string, on: boolean) {
  if (on && !element.hasAttribute(name)) element.setAttribute(name, "");
  else if (!on && element.hasAttribute(name)) element.removeAttribute(name);
}

function round(n: number): number {
  return Math.round(n * 100) / 100;
}

// WebKit (Safari, and WebKit on Linux), not the browsers built on Chromium,
// whose user agents say AppleWebKit too.
function webkit(): boolean {
  const agent = typeof navigator === "undefined" ? "" : navigator.userAgent;
  return /AppleWebKit/.test(agent) && !/Chrome|Chromium|CriOS|Edg|OPR/.test(agent);
}

function reducedMotion(): boolean {
  return typeof matchMedia === "function" && matchMedia("(prefers-reduced-motion: reduce)").matches;
}

// Following is Issho's, a room's, kept by the page (Issho's contract, with
// no import of it): the root element's `data-issho-following`, a JSON object
// of room to the key of the one followed, and the `issho:following` event.
function followingIn(room: string): string | null {
  try {
    return (JSON.parse(document.documentElement.dataset.isshoFollowing ?? "{}") as Record<string, string>)[room] ?? null;
  } catch {
    return null;
  }
}

function followIn(room: string, key: string | null): void {
  if (followingIn(room) === key) return;
  let all: Record<string, string> = {};
  try {
    all = JSON.parse(document.documentElement.dataset.isshoFollowing ?? "{}") as Record<string, string>;
  } catch {
    all = {};
  }
  if (key) all[room] = key;
  else delete all[room];
  if (Object.keys(all).length > 0) document.documentElement.dataset.isshoFollowing = JSON.stringify(all);
  else delete document.documentElement.dataset.isshoFollowing;
  document.dispatchEvent(new CustomEvent("issho:following", { detail: { room, key } }));
}
