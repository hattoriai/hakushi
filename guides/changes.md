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
`result` after it, `by`, who made it, and the `canvas`'s id. On a canvas
alone, `by` is the canvas's `user`. (`user`, the change's `by`, is there
too, as in 0.2, and goes in a later version.) It returns:

* `:ok`, or `{:ok, anything}`: the change happens;
* `{:ok, %Hakushi.Change{}}`: another change happens in its place (see
  below);
* `{:error, reason}`: it does not, and `reason` (a string) is shown;
* `{:error, changeset}`: it does not, and the changeset's first error is
  shown.

### Another change in its place

`on_change` may give back another change, to happen in place of the one
it was given: a move put on the app's own grid, a node kept inside its
frame, a label trimmed, a delete that takes more with it. That change
goes the same way: the graph, the rules, and `on_change` again, which
saves it when it takes it as it is (`:ok`, or the same change back).

```elixir
def change(%Hakushi.Change{op: :move, nodes: places} = change, %{result: graph}, flow) do
  on_grid = Enum.map(places, &%{&1 | x: round(&1.x / 20) * 20, y: round(&1.y / 20) * 20})

  if on_grid == places,
    do: Flows.save_graph(flow, graph),
    else: {:ok, %{change | nodes: on_grid}}
end
```

The person sees the change that happened, not theirs: the node goes from
where they let it go to where the app put it. Their undo takes back
what happened. A change the rules refuse is refused, with its reason,
and the person's does not happen either. `on_change` gives back another
change five times at most; after that nothing happens, and the canvas
logs the last one.

The change given back keeps the person's `by`, and has one `op`, as any
change: a move may become another move, a delete a delete of more nodes.
On a shared canvas, it is the change everyone sees, whoever made the
first: a person, an agent, or the app (`Hakushi.Issho.change/4`).

### On a shared canvas, with Issho

On a shared canvas, `by` is an `Issho.Identity`, the same in every
component's callback: a person (`key` is your actor's, `"user:4"`), an
agent (and whom it acts for, `on_behalf_of`) or your server
(`kind: :service`, from `Hakushi.Issho.change/4`).

`on_change` runs once for each change, in the room (see
[Collaboration](collaboration.md)), not once for each person.

## Hearing of the changes

`on_change` is where the app checks and saves a change. A process that
only needs to hear of them (to keep its own copy of the graph, run a
flow again, index it, or hand the canvas's news to a parent LiveView)
takes `notify`:

```heex
<.canvas id="flow" graph={@graph} on_change={&Flows.change(&1, &2, @flow)} notify={self()} />
```

```elixir
def handle_info({Hakushi, "flow", {:changed, _change, graph}}, socket),
  do: {:noreply, assign(socket, :graph, graph)}

def handle_info({Hakushi, "flow", {:selected, %{nodes: nodes}}}, socket),
  do: {:noreply, assign(socket, :selected, nodes)}

def handle_info({Hakushi, "flow", _event}, socket), do: {:noreply, socket}
```

`notify` is a pid, or a name (`MyApp.FlowRunner`, `{:global, name}`,
`{:via, Registry, key}`): a canvas inside a LiveView of its own tells the
LiveView around it (give it the parent's pid), and a process that runs a
flow hears each change of its canvas. Nothing is sent when no process
has the name. It gets `{Hakushi, id, event}`, where `id` is the canvas's
and `event` is one of:

| `event` | when |
| --- | --- |
| `{:changed, change, graph}` | a change applied: the change as it applied (a delete lists its edges) and the graph after it |
| `{:selected, selection}` | the person selected other nodes or edges, as `on_select` hears it |
| `{:viewport, viewport}` | their view came to rest, as `on_viewport` hears it |

Every change that applied is news: the person's, an undo, the app's own
(`Hakushi.Live.change/2`). On a shared canvas, each canvas that notifies
hears everyone's, once the room has them; `on_change` still runs once
for each change, in the room. A change refused is not news, nor a new
`graph` the app gives the canvas, which it has already.

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

Or give the canvas a new `graph`: without `issho`, it shows what changed
from the graph it had.

The app's changes go the same way as a person's, `on_change` included,
and people cannot undo them.

### From anywhere, with Issho

From anywhere (a job, another LiveView), for a shared canvas:
`Hakushi.Issho.change(MyApp.Issho, topic, change)`.

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
