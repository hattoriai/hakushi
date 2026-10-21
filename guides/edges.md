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
| `path` | `"bezier"` (the default), `"smooth"` (steps with round corners), `"step"` (square corners), `"straight"` |
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

## Selecting and deleting

A click on an edge or its label selects it; Shift adds it. Delete
deletes the selected edges and nodes; the edges of a deleted node go with
it.
