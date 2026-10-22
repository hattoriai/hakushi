# Changes

Every change to a canvas goes one way, whoever makes it:

1. the canvas applies it to its graph (`Hakushi.Graph.apply/2`), which
   refuses a change to a node or an edge it does not have, a second node
   with one id, or a change to a locked node;
2. it checks the rules of the edges (`Hakushi.Rules`);
3. it asks the app (`on_change`), which checks it in its own terms and
   saves it;
4. only then does it show the change: to the person, and on a shared
   canvas to everyone.

A change refused at any step does not happen. The browser takes back
what the person did (the node goes back where it was, the dashed edge
goes, the deleted nodes come back), and the canvas shows the reason for
a few seconds.

## The changes

A `Hakushi.Change` has an `op`:

| `op` | What the person did | `nodes` and `edges` |
| --- | --- | --- |
| `:move` | dragged, resized, moved with the arrow keys, tidied up, dropped into or out of a group | maps of `:id`, `:x`, `:y`, `:width` and `:height` for a resize, `:parent` for a drop; the nodes in a moved group are in it too |
| `:connect` | drew an edge | `Hakushi.Edge`s |
| `:reconnect` | dragged an end of an edge to another handle | maps of `:id` and the new `:source`, `:source_handle`, `:target`, `:target_handle` |
| `:add` | dropped an item, double-clicked, pasted, duplicated, undid a delete | `Hakushi.Node`s, and `Hakushi.Edge`s between them |
| `:update` | set an edge's label (and the app's own changes of data) | maps of `:id` and the keys that change |
| `:delete` | pressed Delete | ids; the nodes in deleted groups are in `nodes` too, and the edges of all of them in `edges` |

A change's `by` is the person (the canvas's `user`), or `nil` for the
app's own: it says whose undo list the change is on. Who made it, for
your checks and your records, is `on_change`'s `by` (below).

## `on_change`

```elixir
<.canvas id="flow" graph={@graph} on_change={&Flows.change(&1, &2, @flow)}>
```

```elixir
def change(change, %{graph: before, result: graph, by: by, canvas: _id}, flow) do
  cond do
    not can_edit?(flow, by) -> {:error, "You can look at this flow, not change it."}
    change.op == :delete and "start" in change.nodes -> {:error, "A flow keeps its start."}
    true -> save_graph(flow, graph)
  end
end
```

It gets the change, and a map with the `graph` before the change, the
`result` after it, `by`, who made it, and the `canvas`'s id. On a shared
canvas, `by` is an `Issho.Identity`, the same in every component's
callback: a person (`key` is your actor's, `"user:4"`), an agent (and
whom it acts for, `on_behalf_of`) or your server (`kind: :service`, from
`Hakushi.Issho.change/4`). On a canvas alone, it is the canvas's `user`.
(`user`, the change's `by`, is there too, as in 0.2, and goes in a later
version.) It returns:

* `:ok`, or `{:ok, anything}`: the change happens;
* `{:error, reason}`: it does not, and `reason` (a string) is shown;
* `{:error, changeset}`: it does not, and the changeset's first error is
  shown.

On a shared canvas, `on_change` runs once for each change, in the room
(see [Collaboration](collaboration.md)), not once for each person.

## What the browser may send

The browser sends moves, edges, ends of edges, deletes and labels, which the server
checks as above. Nothing else comes from it: a paste copies nodes the
server has (the browser names them by id), a dropped item is the node
your `new_node` makes, an undo is a change the server kept. So the
`data` of a node always comes from your server.

## The app's own changes

From the canvas's LiveView, `Hakushi.Live.change/2`:

```elixir
def handle_event("rename", %{"id" => id, "title" => title}, socket) do
  node = Hakushi.Graph.node(socket.assigns.graph, id)
  data = Map.put(node.data, "title", title)
  Hakushi.Live.change("flow", Hakushi.Change.update(nodes: [%{id: id, data: data}]))
  {:noreply, socket}
end
```

From anywhere (a job, another LiveView), for a shared canvas:
`Hakushi.Issho.change(MyApp.Issho, topic, change)`.

Or give the canvas a new `graph`: without `issho`, it shows what changed
from the graph it had.

The app's changes go the same way as a person's, `on_change` included,
and people cannot undo them.

## Undo and redo

⌘Z undoes the person's own last change, and ⇧⌘Z (or ⌘Y) does it again,
up to a hundred. The server keeps them, and each undo is a new change,
checked again: on a shared canvas, an undo of a move that someone else's
change has made impossible is refused, with the reason.

## The graph

`Hakushi.Graph` is the canvas's data, and functions of it:
`Hakushi.Graph.new/1`, `nodes/1`, `edges/1`, `node/2`, `edges_of/2`,
`children/2`, `descendants/2`, `bounds/1`, `apply/2` and `diff/2`, and
`dump/1` and `load/1` for JSON.
