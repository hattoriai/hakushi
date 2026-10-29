# Edges

An edge is a `Hakushi.Edge`: from a handle of one node (`source`,
`source_handle`) to a handle of another (`target`, `target_handle`).

```elixir
%{source: "orders", source_handle: "user_id", target: "users", target_handle: "id",
  path: "smooth", label: "belongs to", marker: "arrow"}
```

## How it is drawn

| | |
| --- | --- |
| `path` | `"bezier"` (the default), `"smooth"` (steps with round corners), `"step"` (square corners), `"straight"`, `"routed"` (steps with round corners around the nodes in the way) |
| `marker` | the end at the target: `"arrow"` (the default), `"dot"`, `"none"` |
| `label` | a text on its middle; people set it with a double click on the edge |
| `animated` | a dashed line that flows from the source to the target (still with reduced motion) |

An edge leaves and arrives square to the sides of its handles.

## Drawing an edge

A person drags from a handle. While they drag, the handles the edge may
end on show, and the others fade; the edge snaps to the nearest one
within reach, or to the nearest valid handle of the node under the
pointer. Dragged from a target, the edge is drawn backwards: it starts
at the handle it ends on.

From the keyboard: focus a node, press C, choose its other end with the
arrows (the valid ends in turn, the nearest first), and press Enter. See
[Navigation](navigation.md).

The new edge goes to the server, which checks it again (below) and asks
`on_change`; until it answers, the edge shows as a dashed line.

## What connects to what

The rules of the canvas (`Hakushi.Rules`), the same in the browser and on
the server:

```heex
<.canvas id="flow" graph={@graph} rules={[cycles: false]}>
```

* `loops`: an edge from a node to itself (`false` unless set).
* `duplicates`: a second edge between the same handles, in the same
  direction (`false` unless set).
* `cycles`: an edge that closes a cycle (`true` unless set). A workflow
  sets it to `false`.

The handles add their own, in the browser:

* a handle with `accepts` takes edges from handles whose `type` is in
  it: a column of `uuid` from a column of `uuid`;
* a handle with `max` takes no more edges than that: a condition's "Yes"
  goes one way.

The server does not know the handles (they are in the HEEx of each
node). Check what an edge means for your app in `on_change`, where you
have your data:

```elixir
def change(%Hakushi.Change{op: :connect, edges: [edge]}, %{graph: graph}) do
  if column_type(graph, edge.source, edge.source_handle) == column_type(graph, edge.target, edge.target_handle),
    do: :ok,
    else: {:error, "These columns are not of one type."}
end
```

## Moving an end

A selected edge shows its two ends: drag one to another handle (or
node), and the edge goes there, by the same rules as a new edge, which
the handles it may end on show. The edge keeps its id, its label and its
data. On the server it is a `:reconnect` change, which the rules check
with the edge's new ends and `on_change` sees; ⌘Z puts it back.

## A label of your own

An edge's `label` is a text on its middle, which people set with a
double click. An `:edge_label` slot draws each edge's label instead, in
your own HEEx, from the edge (`:let`): a badge of its `data`, an icon, a
button. It is rendered on the server, as a node is, and the canvas puts
it on the middle of its edge, wherever the edge goes; a click on it
selects the edge, and its fields and buttons are theirs. An edge whose
slot draws nothing has no label.

```heex
<.canvas id="flow" graph={@graph}>
  <:edge_label :let={edge}>
    <span :if={edge.label} class="way">
      {edge.label}
      <button type="button" phx-click="remove_way" phx-value-edge={edge.id}>×</button>
    </span>
  </:edge_label>
</.canvas>
```

The label has no frame of Hakushi's: give it your own look. A label is
drawn again when its edge changes, as a node is when it does.

## Bending an edge

A selected edge shows a point between each two of the points it goes
through (its ends first): drag one out of the line, and the edge goes
through it. Drag a point to move it, and a double click takes it away.
Each is a change (an `:update` of the edge's `points`), which the server
checks, and undo takes back.

An edge's `points` are `[x, y]` each, in the canvas's terms, in the
order it goes through them. Its `path` draws the way through them: a
straight line from point to point, steps along the axes by each
(`"step"`, and `"smooth"` with round corners), or a curve through them
that leaves and arrives square to its ends (`"bezier"`).

```elixir
Hakushi.Change.update(edges: [%{id: "e1", points: [[240, 80], [240, 300]]}])
```

The points stay where they are when the nodes move: they are places of
the canvas, not of its nodes.

## Routing around the nodes

An edge with `path: "routed"` goes along the axes, with round corners,
and around the nodes in its way: the shortest way that keeps clear of
them, with the fewest corners it can. With nothing in its way it is a
`"smooth"` edge. It goes around them again as they move: a node dragged
onto its line, it goes around the node while it is dragged.

```elixir
%{source: "receipt", target: "close", path: "routed"}
```

It goes around the nodes near its ends (within 160 pixels of the box
between them, the 48 nearest), its own two ones too, but not the groups,
which are drawn under the edges, nor the groups its ends are in. With no
way around them, it goes as a `"smooth"` edge. When people bend it (its
`points`), it goes through them as a `"smooth"` edge does: the points
are theirs to place. Its way is the browser's: the server keeps no
corners, and two browsers draw the same way for the same nodes.

## Selecting and deleting

A click on an edge or its label selects it; Shift adds it. Delete
deletes the selected edges and nodes; the edges of a deleted node go with
it.

## Reading the graph along its edges

`Hakushi.Graph` reads the graph from source to target, for the app that
runs what the canvas draws, checks it, or shows a part of it:

| | |
| --- | --- |
| `successors/2`, `predecessors/2` | the nodes an edge goes to from a node, or comes from |
| `downstream/2`, `upstream/2` | every node the edges lead to from a node, or from which they lead to it, however far |
| `roots/1`, `leaves/1` | the nodes no edge goes to (where a flow starts), and those no edge leaves |
| `topological_sort/1` | every node after the nodes its edges come from (the order a flow runs in), or the cycle that has no such order |
| `cycle/1` | a cycle, or `nil` |
| `path/4`, `edges_along/3` | the shortest way from a node to another, and its edges (`directed: false` goes either way) |
| `components/1` | the parts of the graph that edges join |

They are pure, and where there is a choice they keep the graph's order.

```elixir
{:ok, order} = Hakushi.Graph.topological_sort(graph)
for id <- order, do: run_step(Hakushi.Graph.node(graph, id))
```

A canvas whose `rules` have `cycles: false` never has a cycle (see
`Hakushi.Rules`); `on_change` may check more, with these, on the
`result`:

```elixir
def change(%Hakushi.Change{op: :connect}, %{result: graph}, _flow) do
  if Hakushi.Graph.roots(graph) |> length() > 1,
    do: {:error, "A flow has one start."},
    else: :ok
end
```
