import { expect, test, type Page } from "@playwright/test";
import { node, openCanvas, place } from "./support";

// An agent on a canvas, over MCP (the dev app's /mcp, called through Sake's client): the person sees
// its pointer with its name, sees it drag a table, add one and join two, through the canvas's rules.
async function agent(page: Page, tool: string, args: Record<string, unknown>): Promise<unknown> {
  const response = await page.request.post("/dev/agent", { data: { tool, arguments: args } });
  const reply = (await response.json()) as { result?: unknown; error?: string };
  if (reply.error) throw new Error(`${tool}: ${reply.error}`);
  return reply.result;
}

test("an agent works on a canvas as a person does, and the person sees it", async ({ page }) => {
  const room = await openCanvas(page, "/", undefined, "&as=ada");
  const canvas = `atelier:schema:${room}`;

  const read = (await agent(page, "read_canvas", { canvas })) as { nodes: { id: string; x: number; y: number }[] };
  expect(read.nodes.map((n) => n.id)).toContain("invoices");

  // Its pointer, with its name.
  await agent(page, "point_at", { canvas, node: "invoices", select: ["invoices"] });
  await expect(page.locator("#schema .hakushi-cursor")).toContainText("Claude Code");

  // It drags a table: only where it lands is sent, and Ada's canvas shows
  // it moving on its way there; then it lands. What the node shows is
  // recorded as it changes (not frame by frame, which a busy browser skips):
  // "moving" before it is where it lands, and, when the browser drew frames
  // on the way, a place between.
  await node(page, "invoices").evaluate((el) => {
    const log: { moving: boolean; x: number; frame: number }[] = ((window as unknown as { log: unknown[] }).log = []);
    let frame = 0;
    const tick = () => {
      frame++;
      requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
    const record = () =>
      log.push({ moving: el.dataset.uiPeerName === "Claude Code is moving this", x: Number(el.style.translate.split("px")[0]), frame });
    record();
    new MutationObserver(record).observe(el, { attributes: true, attributeFilter: ["style", "data-ui-peer-name"] });
  });
  type Entry = { moving: boolean; x: number; frame: number };
  const log = () => page.evaluate(() => (window as unknown as { log: Entry[] }).log);
  const from = (await log())[0].x;
  await agent(page, "move_node", { canvas, node: "invoices", x: 900, y: 520 });
  await expect.poll(() => place(page, "invoices")).toEqual({ x: 900, y: 520 });
  const entries = await log();
  const landed = entries.findIndex((e) => e.x === 900);
  const moving = entries.findIndex((e) => e.moving);
  expect(moving).toBeGreaterThanOrEqual(0);
  expect(moving).toBeLessThan(landed);
  const between = entries.slice(moving, landed);
  if (between.length > 0 && between[between.length - 1].frame - between[0].frame >= 5)
    expect(between.some((e) => e.x > Math.min(from, 900) + 5 && e.x < Math.max(from, 900) - 5)).toBe(true);

  // It adds a table, as the canvas's other tables are.
  const added = (await agent(page, "add_node", {
    canvas, x: 40, y: 600, type: "table",
    data: { name: "refunds", color: "#be185d", rows: 0, columns: [{ name: "id", type: "uuid", key: "pk" }, { name: "invoice_id", type: "uuid", key: "fk" }] },
  })) as { id: string };
  await expect(node(page, added.id)).toContainText("refunds");

  // The canvas's rules decide what may be joined, for an agent as for anyone.
  await expect(agent(page, "connect_nodes", { canvas, source: added.id, source_handle: "invoice_id", target: "invoices", target_handle: "total" })).rejects.toThrow(/uuid/);
  const edges = await page.locator("#schema-edge-data > i").count();
  await agent(page, "connect_nodes", { canvas, source: added.id, source_handle: "invoice_id", target: "invoices", target_handle: "id" });
  await expect(page.locator("#schema-edge-data > i")).toHaveCount(edges + 1);

  // It renames it.
  await agent(page, "update_node", { canvas, node: added.id, data: { name: "credit_notes" } });
  await expect(node(page, added.id)).toContainText("credit_notes");
});
