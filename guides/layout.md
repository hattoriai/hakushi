# Layout and export

## Tidy up

The tidy up button of the controls, or ⇧L, lays the nodes out. There are
three ways:

* **Layers** (`:right`, the default, as a workflow reads, or `:down`, as
  an org chart does): each node after the nodes its edges come from, the
  nodes of a layer ordered to cross as few edges as they can, and each one
  level with its neighbours. A layer far too long for the screen (a table
  that hundreds of others refer to) wraps in columns.
* **Spread out** (`:force`): the edges pull their nodes together and every
  node pushes the others away, by its size, so that joined nodes end up
  near each other and the rest spread around them; then no two overlap.
  For graphs that do not flow: a schema with a few central tables, a
  network, a mind map.
* **Grid** (`:grid`): rows and columns, in the nodes' order.

```heex
<.canvas id="flow" graph={@graph} layout={:down}>
<.canvas id="schema" graph={@graph} kits={[Hakushi.Kits.Schema]} layout={:force}>
```

`layout` is the canvas's way: `:right`, `:down`, `:force` or `:grid`
(`:layered` is `:right`, and `{:layered, :down}` is `:down`); the default
is a kit's (`c:Hakushi.Kit.canvas/0`), else `:right`. People choose
another in the menu by the tidy up button: it lays out that way at once,
and the next tidy up (⇧L) goes that way too, while the page is open.

* With two or more nodes selected, it lays out those, and the others
  stay.
* A group is laid out as one box, with what is in it; locked nodes stay.
* The parts of a canvas that no edge joins are laid out apart, then
  packed in rows, the largest first, in a box of about the screen's
  shape; the nodes that no edge joins go together in a grid.
* The nodes glide to their places (at once with reduced motion), and
  keep the top left corner they had.

The new places are one `:move` change, as a drag's: the server checks it,
`on_change` saves it, everyone on a shared canvas sees it, and ⌘Z undoes
it in one step. On a read-only canvas, only the app lays out
(`Hakushi.Live.layout/2`), and the places are the page's.

The app can tidy up too, from the canvas's LiveView:

```elixir
Hakushi.Live.layout("flow", direction: :down)
Hakushi.Live.layout("schema", algorithm: :force)
```

The layout runs in the person's browser, which knows the size of each
node as it is drawn. Two thousand nodes lay out in about a second
spread out, and in a fraction of that in layers or a grid.

## ELK

[ELK](https://eclipse.dev/elk/) (the Eclipse Layout Kernel) lays out
what the canvas's own layers do not: groups in groups, each laid out
inside, and edges routed along the axes, apart from each other, through
the handles they meet. For a system's map, a cluster of services, a
diagram of nested parts.

It is a module of its own, `hakushi/elk`, because it is large (about
450 KB gzipped, eight times the canvas): only an app that imports it
takes its size. Register it once, before the `LiveSocket` connects:

```js
import { Hakushi, registerLayout } from "hakushi"
import { elk } from "hakushi/elk"

registerLayout("elk", elk())
```

Then name it, as a canvas's `layout` or the app's tidy up:

```heex
<.canvas id="system" graph={@graph} layout={:elk} readonly tidy fit={:readable}>
```

```elixir
Hakushi.Live.layout("system", algorithm: :elk, direction: :down)
```

The tidy up's menu has it too ("Nested") once it is registered.

* Every node in a group is laid out in the group, and each group gets a
  size around its nodes, with its title (the part it is dragged by,
  `data-hakushi-drag`) above them. The sizes are part of the move, as a
  resize's.
* The edges go the way ELK routed them while their two nodes stay where
  ELK put them; moved, they go their own way again. The routes are this
  page's, not the graph's.
* An edge's handle is a port: it starts and ends there, square to its
  side.
* `elk(options)` takes ELK's options
  ([the reference](https://eclipse.dev/elk/reference/options.html)) over
  `defaults`: `elk({"elk.spacing.nodeNode": "48"})`.
* A layout that fails (an error of ELK's) is a layout in layers, with a
  warning in the console. So is `layout={:elk}` before the app registers
  it.

ELK is under the Eclipse Public License 2.0; `hakushi/elk` has it as it
is (see `NOTICE`).

`registerLayout(name, engine)` takes an engine of the app's too: a
function of the nodes (their sizes and groups), the edges (and their
ports) and the way, to the places, the sizes of the groups and the
points of the edges (see `EngineInput` and `EngineResult` in the
types). The server names ELK only (`:elk`).

## A graph with no places of its own

A graph made from data, as a schema read from a database, has no places
for its nodes, and is often too large to see whole. Three attributes make
it a diagram people read and arrange, and do not edit:

```heex
<.canvas
  id="database"
  graph={@graph}
  kits={[Hakushi.Kits.Schema]}
  readonly={:arrange}
  tidy
  fit={:readable}
  layout={:force}
/>
```

* `tidy` lays the nodes out as the canvas opens, before people see them:
  the server draws the canvas with its nodes hidden and a spinner, and
  the browser measures them, lays them out in the canvas's `layout`, and
  shows them in place. Give the nodes any place (`x: 0, y: 0`). The places
  go to the server as the person's move, which no undo takes back to the
  pile the canvas opened as; on a read-only canvas they are the page's
  only (a patch of a node, as a mark, keeps them), and a shared canvas
  keeps the room's places and does not tidy.
* `fit={:readable}` opens on all of the nodes when they fit at 60% or
  more, else at a zoom people read, on the most joined node and its
  neighbours (the heart of the graph). The minimap shows where that is in
  the whole, and the fit button still shows all of it.
* `readonly={:arrange}` lets people move the nodes, tidy them up and undo
  that, and nothing else: no edits of a node's content (a kit draws it
  read-only), no new or deleted nodes or edges, no resize, no move into or
  out of a group. The server takes only those moves. Keep them in the
  socket's assigns and save nothing (a reload lays the graph out again),
  or save them in `on_change`. On a shared canvas, an arranging person's
  moves are the room's, unless the room lets them only read.

## Export

The download button of the controls saves the canvas as a PNG: every node
and edge, not only those on the screen, at twice its size, on the paper's
colour. `export={false}` takes the button away.

From the LiveView, in the person's browser:

```elixir
Hakushi.Live.export("flow", format: :svg, filename: "invoice-flow")
```

And from your own JavaScript, as a `Blob`:

```js
import { canvasOf } from "hakushi"

const blob = await canvasOf(document.getElementById("flow")).exportImage({ format: "png", scale: 2, padding: 32, transparent: false })
```

The image is the nodes as the page draws them (your HEEx, with the
page's style sheets) and the edges, without the handles. Fonts of the
page's own origin are put in the image; a font, a style sheet or an
image of another origin may not be, and a browser that will not draw
such an image to a PNG gives the SVG instead (see
[Known limits](limits.md)).

## Lining up and spacing out

The selected nodes line up by their left sides, middles or right sides,
or their tops, middles or bottoms, on the box around them all (Alt and a
letter, see [Navigation](navigation.md), or the menu's
`:align_left`… items, `Hakushi.Menu`); three or more space out, with
equal gaps between them, the first and the last staying where they are.
A node in a group moves with it, a locked one stays, and the new places
are one move: checked, shared, and undone with ⌘Z.

From the LiveView, as the tidy up's `Hakushi.Live.layout/2`, the
person's browser does it (it has the nodes' sizes):

```elixir
Hakushi.Live.align("schema", :top, nodes: ["users", "orders"])
Hakushi.Live.distribute("schema", :horizontal)
```

Without `nodes`, it is the person's selection.
