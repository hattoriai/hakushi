# Groups

A group is a node that holds others: a frame of a moodboard, a lane of a
workflow, the schema of a database. Its nodes move with it, go with it
when it is deleted, and are drawn over it.

```heex
<.canvas id="board" graph={@graph} on_change={...}>
  <:node type="frame" group resizable :let={node}>
    <div class="frame"><span data-hakushi-drag>{node.data.title}</span></div>
  </:node>
  <:node type="note" :let={node}>...</:node>
</.canvas>
```

`group` on a `:node` slot makes its nodes groups; for a kit's types, its
`c:Hakushi.Kit.group?/1` does, as `resizable?/1` does for `resizable`:

```elixir
@impl true
def group?(type), do: type == "roadmap-lane"
```

An app's `:node` slot for the type wins over the kit. A node is in a
group by its `parent`:

```elixir
Hakushi.Graph.new(
  nodes: [
    %{id: "signage", type: "frame", x: 0, y: 0, width: 400, height: 300, data: %{title: "Signage"}},
    %{id: "a", type: "note", x: 20, y: 40, parent: "signage", data: %{text: "Numbers you read from the quay"}}
  ]
)
```

A node's `x` and `y` are its place on the canvas, in a group or not: a
group's nodes keep their places when the group's data changes, and
`Hakushi.Graph` moves them with it.

## What people do

* **Drop in.** A node dragged and dropped on a group goes in it: the
  innermost group under its middle, which shows as it passes over.
* **Drag out.** A node dragged off its group, and dropped on the paper,
  comes out of it (or goes into the group it is dropped on).
* **Move.** A group dragged moves its nodes, and the groups in it with
  theirs. Give a group a part to drag it by (`data-hakushi-drag`, its
  title), so that a drag on its inside draws a box to select its nodes.
* **Resize.** A `resizable` group resizes by its corners; its nodes stay
  where they are.
* **Delete.** A deleted group takes its nodes, and their edges. One undo
  brings them all back.
* **Copy.** A copied group copies its nodes, in the copy.

Groups go in groups, as deep as you like: a group is drawn over the
groups it is in, and under its nodes.

## On the server

A drop is a `:move` change whose place has a `:parent` (the group, or
`nil` for none), so that the move and the new group are one change, and
one undo. `Hakushi.Graph.apply/2`:

* moves a group's nodes with it, unless the change places them itself,
  and lists them in the change it gives back;
* deletes a group's nodes with it, and lists them;
* refuses a group in itself, or in a group inside it (`:nested`), and a
  `parent` it does not have (`:dangling`).

`Hakushi.Graph.children/2` and `descendants/2` give the nodes in a
group. `on_change` sees the change as any other, and may refuse it: a
step that must stay in its lane.

The layout ([Layout and export](layout.md)) lays out a group as one box,
with what is in it. ELK (`layout={:elk}`) lays out what is in each group
too, and sizes the groups around their nodes.

## Folding a group

A folded group shows as its title: the nodes in it go, and their edges
go to it. For a large diagram that people open a part of at a time: a
cluster folded to one box, opened to its services, and a service to its
workloads.

`Hakushi.Graph.fold/2` is the graph as it shows with some groups folded.
Keep the whole graph and the folded ids in the socket's assigns, and show
the folded graph:

```elixir
def mount(_params, _session, socket) do
  graph = Systems.graph()
  folded = MapSet.new(Systems.groups(graph))
  {:ok, assign(socket, graph: graph, folded: folded)}
end

def handle_event("fold", %{"id" => id}, socket) do
  folded = socket.assigns.folded
  folded = if id in folded, do: MapSet.delete(folded, id), else: MapSet.put(folded, id)
  Hakushi.Live.layout("system")
  {:noreply, assign(socket, folded: folded)}
end
```

```heex
<.canvas id="system" graph={Hakushi.Graph.fold(@graph, @folded)} layout={:elk} readonly tidy>
  <:node type="group" group :let={node}>
    <div class="group">
      <header data-hakushi-drag>
        <button
          type="button"
          phx-click="fold"
          phx-value-id={node.id}
          aria-expanded={to_string(!node.folded)}
        >
          {node.data.name}
        </button>
      </header>
    </div>
  </:node>
</.canvas>
```

* A button in a node is the app's: a click on it does not select or drag
  the node.
* A folded group has `node.folded`, for its slot: the slot reads it, and
  not the socket's `@folded`, because the canvas draws a node again only
  when the node changes. It has no size of its own: its slot draws it as
  small as it is folded (`data-folded` is on its element, for CSS).
* The edges keep their ids. Two edges into a folded group are two lines,
  which ELK routes apart, and `Hakushi.Live.mark_edges/3` still marks
  them. The end that moved has no handle, and the edge no points.
* An edge between two nodes of one folded group goes, with them.
* The places of the nodes that come back are the whole graph's: lay the
  canvas out again (`Hakushi.Live.layout/2`, as above). On a read-only
  canvas the layout is the page's.
* On a canvas people edit, apply each change to the whole graph, not
  the folded one: a folded group that moves moves its nodes with it.
