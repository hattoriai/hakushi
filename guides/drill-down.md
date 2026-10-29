# Drill-down

A node that holds a canvas of its own: a step that is a flow, a table
whose columns are a diagram, a frame of a board. People open it, see
what is in it, and go back up.

## Opening a node

The nodes of a slot that `opens` open with a double click (a group's by
the part it is dragged by: its inside is paper), with ⌘↓ (Ctrl+↓) on the
focused or selected node, or with an `opener/1` in them. The view goes
into the node, and then the canvas calls `on_open` with its id, in the
LiveView's process: the app shows what is in it.

```heex
<.canvas id="flow" graph={@graph} on_open={&send(self(), {:open, &1.node})}>
  <:node type="subflow" opens :let={node}>
    <div class="step">{node.data.title} <.opener /></div>
  </:node>
</.canvas>
```

```elixir
def handle_info({:open, id}, socket),
  do: {:noreply, push_patch(socket, to: ~p"/flows/#{socket.assigns.flow}/steps/#{id}")}
```

A canvas of another graph is best a canvas of another id (`id={"step-" <>
@step.id}`): it opens on all of its nodes, as a canvas does.

## Going back up

`on_up` makes ⌘↑ go up, out of the canvas; `canvas_path/1` shows where
the canvas is among canvases, the ones before it as links:

```heex
<.canvas_path>
  <:step patch={~p"/flows/#{@flow}"}>{@flow.name}</:step>
  <:step>{@step.title}</:step>
</.canvas_path>

<.canvas id={"step-" <> @step.id} graph={@inside} on_up={fn _ -> send(self(), :up) end} />
```

## A group as a canvas of its own

A group (a frame) opens as a canvas of its inside: `Hakushi.Graph.subgraph/2`
is the graph of the nodes in it, from its top left corner, and
`Hakushi.Graph.put_subgraph/3` puts it back, as it changed, with the
edges from the inside to the outside that still have both ends.

```elixir
inside = Hakushi.Graph.subgraph(board, "signage")

def on_inside(_change, %{result: inside}, board_id, frame_id) do
  Boards.update_graph(board_id, &Hakushi.Graph.put_subgraph(&1, frame_id, inside))
end
```

When the canvas the group is in is shared, its room has the graph: send
each change of the inside there, as a change of that graph
(`Hakushi.Change.lift/2`):

```elixir
Hakushi.Issho.change(MyApp.Issho, "board:#{id}", Hakushi.Change.lift(change, frame))
```

`notify` hears `{:opened, id}` and `:up` too.
