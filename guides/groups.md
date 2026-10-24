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
with what is in it.
