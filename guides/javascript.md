# JavaScript

The canvas works without any JavaScript of yours. A page's own script
can read a canvas, hear what happens on it, and give it tools of its
own: what the pointer does with them happens in the browser, and their
changes go to the server as a person's do.

```js
import { Hakushi, canvasOf, registerTool } from "hakushi"
```

## A canvas, from the page

`canvasOf(element)` is the canvas of an element (`.hakushi`, the
element with the canvas's id), or `undefined`:

```js
const canvas = canvasOf(document.getElementById("flow"))

canvas.getNodes()       // [{id, type, x, y, width, height, parent, locked, selected}]
canvas.getEdges()       // [{id, source, sourceHandle, target, targetHandle, label, selected}]
canvas.getSelection()   // ["send-receipt"]
canvas.getView()        // {x, y, zoom}
canvas.nodesAt({x: 120, y: 40})          // the nodes under a point of the canvas, the topmost first
canvas.toCanvas(event.clientX, event.clientY)  // the point of the canvas under a point of the page
canvas.select(["a", "b"])
canvas.setView({zoom: 1})
canvas.fitAll()
```

`canvas.on(event, fn)` hears it, and gives the function that stops:

| Event | Gives |
| --- | --- |
| `"select"` | `{nodes, edges}`, the ids selected |
| `"view"` | `{x, y, zoom}`, as the view moves |
| `"change"` | `{change, ok, error, rewritten}`, a change of the person's as the server answered it |
| `"tool"` | the tool chosen (`"ink:pen"`, `"app:ruler"`), or `null` for the pointer |
| `"out"` | `{node, text, dropped}`, a part of a node dragged out onto the page (`data-hakushi-out`), and whether something took it |

```js
const stop = canvas.on("select", ({nodes}) => panel.show(nodes))
```

The server hears the selection and the view too (`on_select`,
`on_viewport`, see [Navigation](navigation.md)): listen here for what
the page shows at once, without a round trip.

## Tools of your own

`registerTool` adds a tool: a button of the canvas's bar of tools (and a
letter), and what the pointer does with it. A canvas offers the tools
its `client_tools` names:

```heex
<.canvas id="board" graph={@graph} client_tools={["ruler", "stamp"]} />
```

```js
registerTool({
  name: "stamp",
  label: "Stamp a note",
  key: "s",
  icon: '<svg viewBox="0 0 24 24" …>…</svg>',
  up(ctx, event, at) {
    ctx.drop("note", at)
  }
})
```

A tool has a `name` (a-z, 0-9 and -), a `label`, and optionally an
`icon` (an SVG of 24 by 24, `stroke="currentColor"`), a `key`, a
`cursor`, and `readonly: true` for a tool that changes nothing, which a
read-only canvas offers too. Its handlers get a context, the event and
the point of the canvas: `down`, `move` and `up` while the pointer is
pressed (the tool has it: no pan, no selection), `cancel` when the
press is cancelled (Escape, a second finger), and `chosen` and
`dropped` as people choose it and another.

The context has:

| | |
| --- | --- |
| `ctx.canvas` | the canvas, as above |
| `ctx.layer`, `ctx.svg(tag, attrs)` | an SVG group above the nodes, in the canvas's terms, for what the tool draws as it works; emptied when another tool is chosen |
| `ctx.nodesAt(point)`, `ctx.select(ids)` | the nodes under a point, and the selection |
| `ctx.move(places)`, `ctx.connect(source, target)`, `ctx.remove(nodes, edges)` | changes, as a person's: the server checks them (`on_change`), everyone sees them on a shared canvas, and undo takes them back; each a promise of the server's reply |
| `ctx.drop(item, at)` | a new node at a point, the canvas's `new_node` for `item`, as a drop |
| `ctx.pushEvent(event, payload, onReply)` | an event to the canvas's LiveView (`handle_event/3`) |
| `ctx.announce(text)` | words for screen readers |

A ruler, which draws as it goes and changes nothing:

```js
registerTool({
  name: "ruler",
  label: "Ruler",
  readonly: true,
  down(ctx, _event, at) {
    ctx.layer.replaceChildren()
    this.from = at
    this.line = ctx.svg("line", {x1: at.x, y1: at.y, x2: at.x, y2: at.y, class: "ruler"})
    ctx.layer.append(this.line)
  },
  move(_ctx, _event, at) {
    this.line.setAttribute("x2", at.x)
    this.line.setAttribute("y2", at.y)
  },
  up(ctx, _event, at) {
    ctx.announce(`${Math.round(Math.hypot(at.x - this.from.x, at.y - this.from.y))} pixels`)
  }
})
```

Register the tools before the LiveSocket connects, or after: a canvas
that has come takes a tool registered later. The types (`ClientTool`,
`ToolContext`, `CanvasEvents`, `NodeInfo`) come with the package.
