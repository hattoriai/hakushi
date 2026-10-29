# Navigation

How people move about a canvas, and change it, with a mouse, a trackpad,
a touch screen and the keyboard. (⌘ is Ctrl outside Apple's systems.)

## The view

| | |
| --- | --- |
| Pan | the wheel or two fingers on a trackpad; Space and a drag; the middle button and a drag; one finger on a touch screen; the arrow keys with nothing selected |
| Zoom | ⌘ (or Ctrl) and the wheel, at the pointer; a pinch on a trackpad or a touch screen; + and -; the controls |
| Fit | ⇧1, or the fit button: every node on the screen, at 100% at most |
| 100% | ⇧0, ⌘0, or a click on the zoom in the controls |
| Overview | a click or a drag on the minimap moves the view there |
| Into a node | a double click, ⌘↓ or its opener, on a node that opens: what is in it (see [Drill-down](drill-down.md)) |
| Up | ⌘↑, on a canvas the app opened from another |

`wheel={:zoom}` makes the wheel zoom, as a map does. `wheel={:scroll}`
leaves the wheel to the page, for a canvas in a page that scrolls: ⌘ or
Ctrl and the wheel, or a pinch, zoom, and a drag pans (see
[In a page](embedding.md)).

## Selecting

A click on a node or an edge selects it. Shift, ⌘ or Ctrl and a click
adds it or takes it away. A drag on the paper draws a box that selects
what it touches (Shift keeps the selection). ⌘A selects every node, and
Escape nothing.

## Changing

| | |
| --- | --- |
| Move | drag a node (and every selected node with it); the helper lines line it up with the nodes near it, and Alt drags without them; the arrow keys move the selection by one (ten with Shift, a square of the grid on a canvas that snaps) |
| Connect | drag from a handle to a handle; or C, then the arrows, then Enter |
| Move an end | select an edge, and drag one of its ends to another handle |
| Bend an edge | select it, and drag a point out of its line; drag a point to move it, and double-click it to take it away |
| Group | drop a node on a group to put it in; drag it off to take it out |
| Tidy up | ⇧L, or the button of the controls: the selection when two or more nodes are selected, else every node |
| Line up | Alt and A, H or D: the left sides, the middles or the right sides of the selected nodes; Alt and W, V or S: their tops, middles or bottoms (⌥ on a Mac); or the menu |
| Space out | Alt+Shift+H across, Alt+Shift+V down: equal gaps between three or more selected nodes; or the menu |
| Download | the button of the controls: the canvas as a PNG |
| Resize | the corners of a selected node of a `resizable` slot |
| Delete | Delete or Backspace |
| Copy, cut, paste | ⌘C, ⌘X, ⌘V (at the pointer, or next to what it copies) |
| Duplicate | ⌘D |
| Undo, redo | ⌘Z, ⇧⌘Z or ⌘Y |
| Label an edge | a double click on it, then Enter (or Escape) |
| A new node | drag an item onto the canvas, or Enter on it; a double click on the paper |

## The keyboard alone

The canvas is one stop of Tab. From there:

* Tab and Shift+Tab go from node to node, in their order, and on past
  the last one out of the canvas; the focused node is selected and comes
  into view;
* Alt and an arrow go to the nearest node that way;
* Enter goes into the node, to its first field or button, and Escape
  back out to the node;
* C starts an edge from the focused node: the arrows (or Tab) go through
  the nodes it may end on, nearest first, Enter makes it, Escape does
  not.

## The menu

A canvas with `menu` opens its own menu on a right click, in place of
the browser's: on a node (selected with it), an edge, or the paper. The
menu key, or Shift+F10, opens the menu of the focused node or of what
is selected; the arrows go through its items, Enter chooses one, and
Escape closes it.

```heex
<.canvas id="flow" graph={@graph} menu={&menu/1} on_menu={&send(self(), {:menu, &1, &2})}>
```

```elixir
def menu(%{kind: :node, nodes: [_one]}),
  do: [%{id: "inspect", label: "Inspect", icon: "table"}, :separator, :copy, :duplicate, :delete]

def menu(target), do: Hakushi.Menu.defaults(target)

def handle_info({:menu, "inspect", %{nodes: [id]}}, socket),
  do: {:noreply, assign(socket, :inspected, id)}
```

`menu` gives the items for a target (what is under the pointer, what is
selected, and where): the canvas's own actions, as atoms, which it runs
itself (`:copy`, `:paste`, `:delete`, `:fit`, `:tidy`…), and items of
the app's own, maps with an `id` and a `label`, whose choice calls
`on_menu`. `menu={true}` gives Hakushi's own items. A person who may not
change the canvas is not offered the actions that change it. See
`Hakushi.Menu`.

## The app and the view

What the person selects and sees is theirs, in their browser. The app
hears of it, and moves it, when it asks to.

`on_select` is called when the person selects other nodes or edges (a
click, Shift, a box, ⌘A, Escape, a node deleted), and `on_viewport`
when their view comes to rest after a pan or a zoom. Both are called in
the LiveView's process, so the simplest is a message to itself:

```heex
<.canvas
  id="schema"
  graph={@graph}
  on_select={&send(self(), {:selected, &1})}
  on_viewport={&send(self(), {:viewport, &1})}
>
```

```elixir
def handle_info({:selected, %{nodes: [id]}}, socket),
  do: {:noreply, assign(socket, :inspected, id)}

def handle_info({:selected, _selection}, socket),
  do: {:noreply, assign(socket, :inspected, nil)}

def handle_info({:viewport, viewport}, socket),
  do: {:noreply, assign(socket, :viewport, viewport)}
```

A selection is a map of the `canvas`, and the ids of the `nodes` and the
`edges` selected. A viewport is a map of the `canvas`, the part of the
canvas on the screen (`x`, `y`, `width`, `height`, in the canvas's
terms) and the `zoom`. A canvas without them (or `notify`, which hears
them too: see [Changes](changes.md#hearing-of-the-changes)) sends
neither, and on a shared canvas each person's are their own.

From the LiveView, `Hakushi.Live` moves the view and the selection:

| | |
| --- | --- |
| `fit(canvas)` | every node, as the fit button does |
| `fit(canvas, nodes: ids)` | those nodes |
| `fit(canvas, box: {x, y, width, height})` | that part of the canvas: an `on_viewport`'s, to come back to it |
| `focus(canvas, ids)` | those nodes in the middle, at the zoom of the view unless they do not fit, and selected (`select: false` leaves the selection; `zoom: 1.5` at that zoom) |
| `select(canvas, ids)` | those nodes selected, and `edges: ids`; `reveal: true` brings them into view |

The view glides there (`animate: false` jumps, as reduced motion does),
and a pan or a zoom on the way stops it. A selection of the app is not
news to it: `select/3` and `focus/3` do not call `on_select`.

```elixir
# A search: the first table whose name has the words, in the middle.
def handle_event("find", %{"name" => name}, socket) do
  with %{id: id} <- Enum.find(Hakushi.Graph.nodes(socket.assigns.graph), &(&1.data.name =~ name)),
       do: Hakushi.Live.focus("schema", id)

  {:noreply, socket}
end
```
