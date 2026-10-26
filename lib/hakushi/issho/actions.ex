if Code.ensure_loaded?(Issho.Action) do
  defmodule Hakushi.Issho.Actions do
    @moduledoc """
    A shared canvas's commands as Issho's actions (`Issho.Action`): one
    for a person's canvas and an agent's tool alike. Adding a node,
    connecting two, changing one and deleting are each one action, which
    the canvas runs when a person drops, draws, connects, edits or
    deletes, and an agent runs as its tool (`add_node`, `connect_nodes`,
    `update_node`, `delete_items`): the same change, as whoever makes it,
    under the room's policy and the canvas's rules, heard as
    `"action.done"`. An agent's pointer goes there first, seen
    (`c:Issho.Action.gesture/2`), and a pause on its way changes nothing.

    Moving and resizing (a drag), an edge's ends and label, and the paper
    are not actions: they change the document as a keystroke does a text.
    """

    alias Hakushi.{Change, Graph}
    alias Hakushi.Issho.Tools.Canvas, as: Shared

    @doc "Every action of a shared canvas."
    @spec all() :: [module()]
    def all, do: [__MODULE__.AddNode, __MODULE__.Connect, __MODULE__.Update, __MODULE__.Delete]

    @doc false
    # A person's change on their canvas, in the room: the action it is, or
    # the document's transaction when it is no command (a move).
    @spec commit(String.t(), String.t(), Change.t()) :: {:ok, term()} | {:error, term()}
    def commit(room, canvas, %Change{op: :add, nodes: [node], edges: []}) do
      act(room, __MODULE__.AddNode, %{
        canvas: canvas,
        id: node.id,
        type: node.type,
        x: node.x,
        y: node.y,
        width: node.width,
        height: node.height,
        data: node.data,
        parent: node.parent
      })
    end

    def commit(room, canvas, %Change{op: :connect, edges: edges}) do
      each(edges, fn edge ->
        act(room, __MODULE__.Connect, %{
          canvas: canvas,
          edge: edge.id,
          source: edge.source,
          target: edge.target,
          source_handle: edge.source_handle,
          target_handle: edge.target_handle,
          label: edge.label
        })
      end)
    end

    def commit(room, canvas, %Change{op: :update, nodes: [_ | _] = nodes, edges: []}) do
      each(nodes, fn update ->
        act(
          room,
          __MODULE__.Update,
          update
          |> Map.take([:data, :type, :locked, :x, :y, :width, :height])
          |> Map.merge(%{canvas: canvas, node: update.id})
        )
      end)
    end

    def commit(room, canvas, %Change{op: :delete, nodes: nodes, edges: edges}),
      do: act(room, __MODULE__.Delete, %{canvas: canvas, nodes: nodes, edges: edges})

    def commit(room, canvas, %Change{} = change), do: Issho.Live.transact(room, canvas, [change])

    defp act(_room, action, args) do
      args = Map.reject(args, fn {_key, value} -> is_nil(value) end)

      case Issho.Live.act(action, args) do
        {:ok, receipt} -> {:ok, receipt}
        {:error, {:invalid, text}} -> {:error, text}
        {:error, reason} -> {:error, reason}
      end
    end

    defp each(items, fun) do
      Enum.reduce_while(items, {:ok, nil}, fn item, _acc ->
        case fun.(item) do
          {:ok, receipt} -> {:cont, {:ok, receipt}}
          error -> {:halt, error}
        end
      end)
    end

    @doc false
    # The canvas of an invocation, as whoever runs it reads it.
    def canvas(invocation, canvas) do
      case Issho.Action.read(invocation, canvas) do
        {:ok, %{"state" => %Graph{} = graph}} ->
          {:ok,
           %Shared{
             ctx: nil,
             participant: invocation.participant,
             canvas: canvas,
             graph: graph
           }}

        {:ok, _other} ->
          {:error, "That is not a canvas."}

        {:error, :no_documents} ->
          {:error, "No one has this canvas open: open it in a browser first."}

        {:error, _reason} = error ->
          error
      end
    end

    @doc false
    # The change, as whoever runs the invocation.
    def change(invocation, canvas, %Change{} = change) do
      who = %{id: invocation.by.key, name: invocation.by.name}
      Issho.Action.transact(invocation, canvas, [%{change | by: who}])
    end

    @doc false
    def room(%{canvas: canvas}), do: Issho.Policy.room(canvas)

    @doc false
    # A node of the canvas, or why not.
    def node(invocation, canvas, id) do
      with {:ok, shared} <- canvas(invocation, canvas),
           {:ok, node} <- Shared.node(shared, id),
           do: {:ok, shared, node}
    end
  end

  defmodule Hakushi.Issho.Actions.AddNode do
    @moduledoc false
    use Issho.Action,
      name: "add_node",
      description: """
      Adds a node at a place of the canvas, as a person drops one: its type
      (one the canvas draws), and its data, in the shape the canvas's other
      nodes of that type have. Your pointer goes there first.
      """

    arg :canvas, :string, required: true
    arg :x, :number, required: true
    arg :y, :number, required: true
    arg :type, :string, description: "The node's type (\"default\" unless given)"
    arg :data, :any, description: "The node's data"
    arg :parent, :string, description: "The group it goes in"
    arg :width, :number, min: 1
    arg :height, :number, min: 1
    arg :id, :string, max_length: 64, description: "Its id: a new one unless given"

    alias Hakushi.{Canvas, Change}
    alias Hakushi.Issho.Actions
    alias Hakushi.Issho.Tools.Canvas, as: Shared

    @impl Issho.Action
    def target(args), do: Actions.room(args)

    @impl Issho.Action
    def gesture(%{canvas: canvas, x: x, y: y}, invocation) do
      with {:ok, shared} <- Actions.canvas(invocation, canvas),
           do: Shared.glide(shared, {x + 20, y + 20})
    end

    @impl Issho.Action
    def run(args, invocation) do
      with {:ok, shared} <- Actions.canvas(invocation, args.canvas),
           node = node(shared, args, invocation),
           {:ok, _receipt} <- Actions.change(invocation, args.canvas, Change.add([node])) do
        if invocation.participant, do: Shared.aware(shared, %{"selected" => [node.id]})
        {:ok, node.id}
      end
    end

    # The node: what an agent gives as data takes the shape of the canvas's own.
    defp node(shared, args, invocation) do
      type = args[:type] || "default"

      data =
        if invocation.participant,
          do: Shared.data(shared, type, args[:data] || %{}),
          else: args[:data] || %{}

      %{id: args[:id] || Canvas.new_id(), type: type, x: args.x, y: args.y, data: data}
      |> Map.merge(Map.take(args, [:parent, :width, :height]))
    end

    @impl Issho.Action
    def summary(id), do: %{"id" => id}

    @impl Issho.Action
    def event(_args, id), do: %{node: id}
  end

  defmodule Hakushi.Issho.Actions.Connect do
    @moduledoc false
    use Issho.Action,
      name: "connect_nodes",
      description: """
      Draws an edge from a node to another, from a handle to a handle when
      the nodes have them (a table's columns): the canvas's rules decide if
      they may be joined, and say why not.
      """

    arg :canvas, :string, required: true
    arg :source, :string, required: true
    arg :target, :string, required: true
    arg :source_handle, :string
    arg :target_handle, :string
    arg :label, :string
    arg :edge, :string, max_length: 64, description: "The edge's id: a new one unless given"

    alias Hakushi.{Canvas, Change}
    alias Hakushi.Issho.Actions
    alias Hakushi.Issho.Tools.Canvas, as: Shared

    @impl Issho.Action
    def target(args), do: Actions.room(args)

    @impl Issho.Action
    def gesture(%{canvas: canvas, source: source, target: target}, invocation) do
      with {:ok, shared, from} <- Actions.node(invocation, canvas, source),
           {:ok, to} <- Shared.node(shared, target),
           :ok <- Shared.glide(shared, Shared.on(from)),
           do: Shared.glide(shared, Shared.on(to))
    end

    @impl Issho.Action
    def run(args, invocation) do
      edge =
        %{id: args[:edge] || Canvas.new_id(), source: args.source, target: args.target}
        |> Map.merge(Map.take(args, [:source_handle, :target_handle, :label]))

      with {:ok, _receipt} <- Actions.change(invocation, args.canvas, Change.connect(edge)),
           do: {:ok, edge.id}
    end

    @impl Issho.Action
    def summary(id), do: %{"id" => id}

    @impl Issho.Action
    def event(%{source: source, target: target}, id),
      do: %{edge: id, source: source, target: target}
  end

  defmodule Hakushi.Issho.Actions.Update do
    @moduledoc false
    use Issho.Action,
      name: "update_node",
      description: """
      Changes a node's data (the keys you give, the others as they are), or
      its type, or locks it; or its place and size (x, y, width, height).
      """,
      annotations: [idempotent: true]

    arg :canvas, :string, required: true
    arg :node, :string, required: true
    arg :data, :any, description: "The keys of its data that change"
    arg :type, :string
    arg :locked, :boolean
    arg :x, :number
    arg :y, :number
    arg :width, :number, min: 1
    arg :height, :number, min: 1

    alias Hakushi.Change
    alias Hakushi.Issho.Actions
    alias Hakushi.Issho.Tools.Canvas, as: Shared

    @impl Issho.Action
    def target(args), do: Actions.room(args)

    @impl Issho.Action
    def gesture(%{canvas: canvas, node: id}, invocation) do
      with {:ok, shared, node} <- Actions.node(invocation, canvas, id),
           do: Shared.glide(shared, Shared.on(node), %{"selected" => [id]})
    end

    @impl Issho.Action
    def run(%{canvas: canvas, node: id} = args, invocation) do
      with {:ok, _shared, node} <- Actions.node(invocation, canvas, id),
           {:ok, _receipt} <-
             Actions.change(invocation, canvas, Change.update(nodes: [update(node, args)])),
           do: {:ok, id}
    end

    defp update(node, args) do
      %{id: node.id}
      |> then(
        &if(is_map(args[:data]),
          do: Map.put(&1, :data, Map.merge(node.data, Shared.data_like(node.data, args.data))),
          else: &1
        )
      )
      |> Map.merge(Map.take(args, [:type, :locked, :x, :y, :width, :height]))
    end

    @impl Issho.Action
    def summary(id), do: %{"updated" => id}

    @impl Issho.Action
    def event(_args, id), do: %{node: id}
  end

  defmodule Hakushi.Issho.Actions.Delete do
    @moduledoc false
    use Issho.Action,
      name: "delete_items",
      description: "Deletes nodes (with the nodes in them, and their edges) and edges, by id.",
      annotations: [destructive: true]

    arg :canvas, :string, required: true
    arg :nodes, {:array, :string}
    arg :edges, {:array, :string}

    alias Hakushi.Change
    alias Hakushi.Issho.Actions
    alias Hakushi.Issho.Tools.Canvas, as: Shared

    @impl Issho.Action
    def target(args), do: Actions.room(args)

    @impl Issho.Action
    def authorize(args, _who) do
      if (args[:nodes] || []) ++ (args[:edges] || []) == [],
        do: {:error, "Say which nodes or edges."},
        else: :ok
    end

    @impl Issho.Action
    def gesture(%{canvas: canvas} = args, invocation) do
      with {:ok, shared} <- Actions.canvas(invocation, canvas),
           do: Shared.aware(shared, %{"selected" => args[:nodes] || []})
    end

    @impl Issho.Action
    def run(%{canvas: canvas} = args, invocation) do
      nodes = args[:nodes] || []
      edges = args[:edges] || []

      with {:ok, _receipt} <-
             Actions.change(invocation, canvas, Change.delete(nodes: nodes, edges: edges)),
           do: {:ok, %{"nodes" => nodes, "edges" => edges}}
    end

    @impl Issho.Action
    def summary(deleted), do: %{"deleted" => deleted}

    @impl Issho.Action
    def event(_args, deleted), do: %{deleted: deleted}
  end
end
