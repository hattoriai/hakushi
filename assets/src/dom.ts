// Small helpers for the DOM.

export function el<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  attrs: Record<string, string> = {},
  children: (Node | string)[] = [],
): HTMLElementTagNameMap[K] {
  const element = document.createElement(tag);
  for (const [name, value] of Object.entries(attrs)) element.setAttribute(name, value);
  for (const child of children) element.append(child);
  return element;
}

const SVG = "http://www.w3.org/2000/svg";

export function svg<K extends keyof SVGElementTagNameMap>(tag: K, attrs: Record<string, string> = {}): SVGElementTagNameMap[K] {
  const element = document.createElementNS(SVG, tag);
  for (const [name, value] of Object.entries(attrs)) element.setAttribute(name, value);
  return element;
}

/** Whether keys typed at an element are its own: a text field, a select, an editable element. */
export function editable(target: EventTarget | null): boolean {
  if (!(target instanceof HTMLElement)) return false;
  if (target.isContentEditable) return true;
  if (target instanceof HTMLTextAreaElement || target instanceof HTMLSelectElement) return true;
  if (target instanceof HTMLInputElement) {
    return !["button", "checkbox", "radio", "range", "color", "file", "submit", "reset", "image"].includes(target.type);
  }
  return false;
}

/** Whether a pointer down on an element is the element's own (a button, a link, a field). */
export function interactive(target: Element, within: Element): boolean {
  const hit = target.closest("input, textarea, select, button, a[href], label, summary, [contenteditable], [data-hakushi-nodrag]");
  return hit !== null && within.contains(hit);
}

export function numberAttr(element: Element, name: string): number | null {
  const value = element.getAttribute(name);
  if (value === null || value === "") return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

/** Whether the platform's command key is ⌘ (Apple devices) rather than Ctrl. */
export function isApple(): boolean {
  const platform = (navigator as Navigator & { userAgentData?: { platform?: string } }).userAgentData?.platform ?? navigator.platform ?? "";
  return /mac|iphone|ipad|ipod/i.test(platform);
}

export function prefersReducedMotion(): boolean {
  return typeof matchMedia === "function" && matchMedia("(prefers-reduced-motion: reduce)").matches;
}
