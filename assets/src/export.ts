// The canvas as an image: the nodes as they are drawn (their HTML, with the
// page's style sheets) and the edges, in an SVG; a PNG is that SVG drawn
// on a <canvas>.

import type { Rect } from "./types";

export interface ExportOptions {
  format: "png" | "svg";
  /** The space around the nodes, in pixels. */
  padding: number;
  /** The pixels of the PNG for each pixel of the canvas at 100%. */
  scale: number;
  /** The paper's colour behind the nodes, or none (`transparent: true`). */
  transparent: boolean;
  /** The name of the file, without its extension (`download`). */
  filename: string;
  /** Whether the image has the canvas's paper (its pattern) behind the nodes; it has none unless asked. */
  paper: boolean;
}

const XHTML = "http://www.w3.org/1999/xhtml";
const SVG = "http://www.w3.org/2000/svg";
// The largest side of a PNG that browsers draw.
const MAX_SIDE = 16_384;

export async function exportImage(root: HTMLElement, world: HTMLElement, box: Rect, options: Partial<ExportOptions> = {}): Promise<Blob> {
  const padding = options.padding ?? 32;
  const width = Math.ceil(box.width + padding * 2);
  const height = Math.ceil(box.height + padding * 2);
  const svgText = await serialize(root, world, box, padding, width, height, options.transparent ?? false, options.paper ?? false);

  if ((options.format ?? "png") === "svg") return new Blob([svgText], { type: "image/svg+xml" });

  const scale = Math.min(options.scale ?? 2, MAX_SIDE / Math.max(width, height));
  const image = new Image();
  image.decoding = "sync";
  // A data URL: Chromium taints a canvas with an SVG of a blob URL that has
  // a foreignObject, and not with one of a data URL.
  const url = `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svgText)}`;
  try {
    await new Promise<void>((resolve, reject) => {
      image.onload = () => resolve();
      image.onerror = () => reject(new Error("the browser could not draw the canvas"));
      image.src = url;
    });
    const canvas = document.createElement("canvas");
    canvas.width = Math.round(width * scale);
    canvas.height = Math.round(height * scale);
    const ctx = canvas.getContext("2d")!;
    ctx.scale(scale, scale);
    ctx.drawImage(image, 0, 0);
    return await new Promise<Blob>((resolve, reject) => canvas.toBlob((blob) => (blob ? resolve(blob) : reject(new Error("no PNG"))), "image/png"));
  } finally {
    image.src = "";
  }
}

async function serialize(root: HTMLElement, world: HTMLElement, box: Rect, padding: number, width: number, height: number, transparent: boolean, paper: boolean): Promise<string> {
  const style = getComputedStyle(root);
  const clone = world.cloneNode(true) as HTMLElement;
  clone.removeAttribute("id");
  clone.style.transform = `translate(${padding - box.x}px, ${padding - box.y}px)`;
  // Every node, as it is drawn, without the marks of the moment.
  for (const el of clone.querySelectorAll("[data-ui-culled], [data-ui-selected], [data-ui-peer], [data-ui-drop-target], [data-ui-valid], [data-ui-target]")) {
    for (const name of ["data-ui-culled", "data-ui-selected", "data-ui-peer", "data-ui-drop-target", "data-ui-valid", "data-ui-target"]) el.removeAttribute(name);
  }
  clone.querySelectorAll(".hakushi-resizer, .hakushi-overlay, .hakushi-ink-live, .hakushi-edge-input").forEach((el) => el.remove());
  clone.querySelectorAll<SVGGElement>(".hakushi-edge").forEach((g) => (g.style.display = ""));
  // The edges raised above the nodes (of a selection) go back under them, as they are drawn.
  const lines = clone.querySelector(".hakushi-edges:not(.hakushi-edges-raised) .hakushi-edge-lines");
  clone.querySelectorAll<SVGGElement>(".hakushi-edges-raised .hakushi-edge").forEach((g) => {
    g.removeAttribute("data-ui-connected");
    const marker = g.querySelector(".hakushi-edge-line");
    const end = marker?.getAttribute("marker-end");
    if (end) marker!.setAttribute("marker-end", end.replace(/-on\)$/, ")"));
    lines?.append(g);
  });
  clone.querySelectorAll<HTMLElement>(".hakushi-edge-label").forEach((l) => (l.style.display = ""));

  // The custom properties of the canvas, as they are on it: its theme.
  const vars: string[] = [];
  for (let i = 0; i < style.length; i++) {
    const name = style[i];
    if (name.startsWith("--")) vars.push(`${name}: ${style.getPropertyValue(name)};`);
  }

  const wrapper = document.createElementNS(XHTML, "div") as HTMLElement;
  wrapper.setAttribute("class", `${root.className} hakushi-export`);
  // The paper, when asked: its pattern at 100%, where it is under the nodes.
  const background = paper ? (root.dataset.background ?? "none") : "none";
  wrapper.setAttribute("data-background", background);
  wrapper.setAttribute(
    "style",
    `${vars.join(" ")} position: relative; width: ${width}px; height: ${height}px; overflow: hidden; ` +
      `font-family: ${style.fontFamily}; font-size: ${style.fontSize}; color: ${style.color}; ` +
      `background: ${transparent ? "transparent" : style.backgroundColor};`,
  );
  if (background !== "none") {
    const grid = Number(JSON.parse(root.querySelector<HTMLElement>(".hakushi-hook")?.dataset.config ?? "{}").grid) || 20;
    const at = `${padding - box.x}px ${padding - box.y}px`;
    const pattern = document.createElementNS(XHTML, "div") as HTMLElement;
    pattern.setAttribute("class", "hakushi-background");
    pattern.setAttribute("style", `--hakushi-grid-size: ${grid}px; inset: 0; translate: none; background-position: ${at}; mask-position: ${at}; -webkit-mask-position: ${at};`);
    wrapper.append(pattern);
  }
  wrapper.append(clone);

  const css = await styleSheets();
  const html = new XMLSerializer().serializeToString(wrapper);
  return (
    `<svg xmlns="${SVG}" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">` +
    `<foreignObject x="0" y="0" width="${width}" height="${height}">` +
    `<style xmlns="${XHTML}">${escapeCss(css)}</style>` +
    html +
    `</foreignObject></svg>`
  );
}

// The rules of the page's style sheets that it can read (not those of
// another origin), and its fonts as data, so that the image has them.
async function styleSheets(): Promise<string> {
  const parts: string[] = [];
  for (const sheet of document.styleSheets) {
    let rules: CSSRuleList;
    try {
      rules = sheet.cssRules;
    } catch {
      continue;
    }
    for (const rule of rules) {
      if (rule instanceof CSSFontFaceRule) parts.push(await inlineFont(rule, sheet.href));
      else parts.push(rule.cssText);
    }
  }
  return parts.join("\n");
}

async function inlineFont(rule: CSSFontFaceRule, base: string | null): Promise<string> {
  const text = rule.cssText;
  const urls = [...text.matchAll(/url\(\s*["']?([^"')]+)["']?\s*\)/g)].map((m) => m[1]);
  let out = text;
  for (const url of urls) {
    if (url.startsWith("data:")) continue;
    try {
      const response = await fetch(new URL(url, base ?? location.href));
      const blob = await response.blob();
      const data = await new Promise<string>((resolve) => {
        const reader = new FileReader();
        reader.onload = () => resolve(String(reader.result));
        reader.readAsDataURL(blob);
      });
      out = out.split(url).join(data);
    } catch {
      // A font that cannot be read: the image uses the next font of the stack.
    }
  }
  return out;
}

function escapeCss(css: string): string {
  return css.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}
