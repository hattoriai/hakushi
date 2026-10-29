// Out of the canvas: an element of a node marked `data-hakushi-out` (and
// `draggable`) dragged onto the page, as the browser drags. Its text goes
// into a field or an editor it is dropped on, as dragged text does; a drop
// target of the page (`data-hakushi-drop`) hears it as an event of the
// LiveView, or of its `phx-target`.

/** The type of the transfer that says what was dragged out, and from where. */
export const OUT_TYPE = "application/x-hakushi";

export interface OutPayload {
  canvas: string;
  node: string;
  text: string;
}

/** How a canvas sends a drop target's event: to `target` (a `phx-target`), else to its LiveView. */
export type OutSender = (target: string | null, event: string, payload: Record<string, unknown>) => void;

const senders = new Map<string, OutSender>();
let listening = false;
let over: Element | null = null;

/** The text, and what it is, in a drag's transfer. */
export function fillTransfer(transfer: DataTransfer, payload: OutPayload): void {
  transfer.setData("text/plain", payload.text);
  transfer.setData(OUT_TYPE, JSON.stringify(payload));
  transfer.effectAllowed = "copy";
}

/** What a drag's transfer says was dragged out of a canvas, or null. */
export function readTransfer(transfer: DataTransfer | null): OutPayload | null {
  if (!transfer || !isOut(transfer)) return null;
  try {
    const payload = JSON.parse(transfer.getData(OUT_TYPE)) as OutPayload;
    return typeof payload?.canvas === "string" && typeof payload.node === "string" && typeof payload.text === "string" ? payload : null;
  } catch {
    return null;
  }
}

/** Whether a drag comes out of a canvas (its data is read only on the drop; its types, all along). */
export function isOut(transfer: DataTransfer | null): boolean {
  return !!transfer && [...transfer.types].includes(OUT_TYPE);
}

/**
 * A canvas's way to send the events of the drop targets its drags reach;
 * the drop targets of the page are listened to from the first canvas on.
 * Gives the function that stops it.
 */
export function registerSender(canvas: string, send: OutSender): () => void {
  senders.set(canvas, send);
  if (!listening && typeof document !== "undefined") {
    listening = true;
    document.addEventListener("dragover", dragOver);
    document.addEventListener("dragleave", dragLeave);
    document.addEventListener("drop", drop);
    document.addEventListener("dragend", () => setOver(null));
  }
  return () => {
    if (senders.get(canvas) === send) senders.delete(canvas);
  };
}

/** The values of a drop target's `phx-value-*`, as a click's are. */
export function phxValues(el: Element): Record<string, string> {
  const values: Record<string, string> = {};
  for (const attr of el.attributes) if (attr.name.startsWith("phx-value-")) values[attr.name.slice(10)] = attr.value;
  return values;
}

function targetOf(event: DragEvent): HTMLElement | null {
  return (event.target as Element | null)?.closest?.<HTMLElement>("[data-hakushi-drop]") ?? null;
}

function setOver(el: Element | null) {
  if (over === el) return;
  over?.removeAttribute("data-hakushi-over");
  over = el;
  over?.setAttribute("data-hakushi-over", "");
}

function dragOver(event: DragEvent) {
  const target = targetOf(event);
  if (!target || !isOut(event.dataTransfer)) return setOver(null);
  event.preventDefault();
  event.dataTransfer!.dropEffect = "copy";
  setOver(target);
}

function dragLeave(event: DragEvent) {
  if (over && !over.contains(event.relatedTarget as Node | null)) setOver(null);
}

function drop(event: DragEvent) {
  const target = targetOf(event);
  setOver(null);
  const payload = target && readTransfer(event.dataTransfer);
  if (!target || !payload) return;
  event.preventDefault();
  const send = senders.get(payload.canvas);
  const name = target.dataset.hakushiDrop;
  if (!send || !name) return;
  send(target.getAttribute("phx-target"), name, { ...phxValues(target), canvas: payload.canvas, node: payload.node, text: payload.text });
}
