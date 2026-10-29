# Nodes

A node is a `Hakushi.Node`: an id, a type, a place (`x`, `y`), a size or
none, and `data` of yours. The canvas draws it with the `:node` slot of
its type.

```heex
<.canvas id="schema" graph={@graph}>
  <:node type="table" :let={node}>
    <.table_node table={node.data} />
  </:node>
  <:node type="note" resizable :let={node}>
    <div class="note">{node.data.text}</div>
  </:node>
  <:node :let={node}>
    <div class="box">{node.id}</div>
  </:node>
</.canvas>
```

A `:node` slot without a `type` draws every other type. A canvas without
a `:node` slot draws each node as a box with its label, a handle on each
side.

## Drawn on the server, once

The slot renders on the server, as any HEEx: your components, your
icons, Tailwind classes, a form. The canvas sends the nodes as a
LiveView stream, so a node is sent when it is new and when it changes,
and not otherwise: a canvas of thousands of nodes sends the node that
moved.

A node draws from the node, not from the LiveView's other assigns. A
change of its `data` (an `:update` change, or a new `graph`) draws it
again; a change of an assign that the slot reads does not.

## Size

A node is as large as what the slot draws, unless it has a `width` and a
`height`, which the canvas gives it. People resize the nodes of a
`resizable` slot by their corners, when they are selected; the change is
a `:move` with the new size.

## Moving

People drag a node by any part of it but its fields, buttons, links and
the elements with `data-hakushi-nodrag`. To drag a node by one part only
(its title bar), mark that part:

```heex
<header data-hakushi-drag>{node.data.title}</header>
```

A `locked` node does not move, resize or go: in the browser, and on the
server, which refuses a change that would.

## Dragged out onto the page

A part of a node that names something (a table, a column, a step) can
drag out of the canvas onto the page, as the browser drags text: mark it
with `data-hakushi-out`, its text, and `draggable="true"`.

```heex
<span data-hakushi-out={node.data.name} draggable="true">{node.data.name}</span>
```

Dropped in a field or an editor (a textarea, CodeMirror, Monaco), its
text goes in where it lands, with nothing of yours. Dropped on an element
of the page with `data-hakushi-drop`, the LiveView hears it as that event,
with the canvas, the node and the text, and the element's `phx-value-*`;
a `phx-target` sends it to a component:

```heex
<div data-hakushi-drop="describe" phx-value-panel="side">Drop a table here</div>
```

```elixir
def handle_event("describe", %{"canvas" => "db", "node" => id, "text" => name}, socket) do
  {:noreply, assign(socket, :described, describe(name))}
end
```

The drop target is marked `data-hakushi-over` while a drag is over it, to
style. A press on such a part does not move the node or pan, and a click
on it selects the node. A canvas's `drag_out` makes the kits' parts drag
out: the Schema kit's tables by their icons, and columns by their names. A drag out is
the browser's drag, with a pointer: give the keyboard another way, such
as an item of the canvas's menu (`Hakushi.Menu`). In the browser, the
canvas's `"out"` event hears each drag (see [JavaScript](javascript.md)).

## Handles

A handle is where edges start (`kind={:source}`), end
(`kind={:target}`), or both (the default). It sits on a `side` of its
nearest positioned ancestor: the node, or an element of it with
`position: relative`, such as a row.

```heex
<div :for={column <- node.data.columns} class="relative">
  <.handle id={column.name} side={:left} type={column.type} accepts={[column.type]} />
  {column.name}
  <.handle id={column.name} side={:right} type={column.type} accepts={[column.type]} />
</div>
```

The edges name the handles by `id` (`source_handle`, `target_handle`).
A node may have several handles with one id, on different sides: an edge
meets the one nearest its other end, so a line takes the short way
whichever side the other node is on.

An edge with no handle id meets the node's first handle of its kind, or
the middle of the side that faces the other node when the node has none.

`type`, `accepts` and `max` are the handle's rules: see [Edges](edges.md).

## Groups

A `:node` slot with `group` draws nodes that hold others, as frames do:
see [Groups](groups.md).

## The label

Screen readers name each node by `node_label`, a function of the node:
the default is its data's `label` or `name`, or its id.

```heex
<.canvas id="schema" graph={@graph} node_label={&"Table #{&1.data.name}"}>
```
