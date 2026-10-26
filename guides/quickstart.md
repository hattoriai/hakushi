# Quickstart

A canvas in a LiveView, its graph from your database, and each change
saved back. Nothing here needs Issho: this is the whole canvas, for one
person at a time.

## Install

Follow the README's [Install](../README.md#install): the dependency, the
hook in the `LiveSocket`, and the style sheet. Then import the components
in the `html_helpers` of your web module:

```elixir
import Hakushi.Components
```

## A canvas

```elixir
defmodule MyAppWeb.FlowLive do
  use MyAppWeb, :live_view

  alias Hakushi.Graph

  def mount(%{"id" => id}, _session, socket) do
    flow = Flows.get!(id)
    {:ok, assign(socket, flow: flow, graph: flow.graph)}
  end

  def render(assigns) do
    ~H"""
    <.canvas id="flow" graph={@graph} on_change={&save(&1, &2, @flow)} class="h-[calc(100vh-4rem)]">
      <:node type="step" :let={node}>
        <div class="rounded-lg border bg-white px-4 py-3 shadow-sm">
          <.handle kind={:target} side={:left} />
          {node.data["title"]}
          <.handle kind={:source} side={:right} />
        </div>
      </:node>
    </.canvas>
    """
  end

  defp save(_change, %{result: graph}, flow) do
    Flows.update_graph(flow, graph)
  end
end
```

The canvas fills its box: give it a height. It opens on all of its
nodes (`fit`), on dotted paper (`background`).

## The graph in one column

`Hakushi.Graph.Type` keeps a whole canvas in one column of a table, as a
map (`jsonb` on PostgreSQL):

```elixir
schema "flows" do
  field :name, :string
  field :graph, Hakushi.Graph.Type, default: Hakushi.Graph.new()
end
```

```elixir
# the migration
add :graph, :map, null: false, default: %{}
```

```elixir
def update_graph(flow, graph) do
  flow |> Ecto.Changeset.change(graph: graph) |> Repo.update()
end
```

`on_change` returns `:ok`, `{:ok, anything}` (as `Repo.update/1` does),
`{:error, reason}` with the words to show, or `{:error, changeset}`,
whose first error is shown. A change that `on_change` refuses does not
happen: the browser takes it back. See [Changes](changes.md).

A canvas whose nodes are rows of their own (the tables of a schema, the
steps of a workflow with their settings) keeps them in its own tables,
makes its graph of them in `mount`, and changes the rows in `on_change`
by the kind of change.

## New nodes

People make nodes by dragging an item onto the canvas, by pressing
Enter on it, or by a double click on the paper. The canvas asks
`new_node` for the node:

```heex
<.canvas_item for="flow" item="email">Email</.canvas_item>

<.canvas id="flow" graph={@graph} on_change={...} new_node={&new_step/2}>
```

```elixir
defp new_step(kind, {x, y}),
  do: %{type: "step", x: x, y: y, data: %{"kind" => kind || "note", "title" => "New step"}}
```

A node without an id gets one. `new_node` returning `nil` makes none.

## Next

* [Nodes](nodes.md) and [Edges](edges.md): what the canvas draws.
* [Testing](testing.md): the canvas in `Phoenix.LiveViewTest`.

## Next: collaboration (optional)

For several people on one canvas at once, add Issho, an optional
dependency. See [Collaboration](collaboration.md).
