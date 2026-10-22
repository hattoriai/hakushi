if Code.ensure_loaded?(Issho.Tool) do
  defmodule Hakushi.Issho.Tools.Canvas do
    @moduledoc false
    # A tool call on a shared canvas, as the caller's agent: the canvas's
    # room joined, its graph, its pointer, and its changes, which go the way
    # of everyone's (the rules, the app's on_change).

    alias Hakushi.{Change, Graph}
    alias Issho.Participant
    alias Issho.Tool.Context

    defstruct [:ctx, :participant, :canvas, :graph]

    # A canvas someone has open (or one the policy describes), by its
    # document: the first canvas to open it gives its graph, its rules and
    # its on_change. The room is the document's.
    def open(ctx, canvas) do
      with {:ok, participant} <- Context.join(ctx, Issho.Policy.room(canvas)),
           {:ok, %{"state" => %Graph{} = graph}} <- Participant.open(participant, canvas) do
        {:ok, %__MODULE__{ctx: ctx, participant: participant, canvas: canvas, graph: graph}}
      else
        {:ok, _other} ->
          {:error, "That is not a canvas."}

        {:error, :no_documents} ->
          {:error, "No one has this canvas open: open it in a browser first."}

        {:error, reason} ->
          Context.error(reason)
      end
    end

    def change(%__MODULE__{} = canvas, %Change{} = change) do
      identity = Issho.Identity.new(canvas.ctx.actor)
      who = %{id: identity.key, name: identity.name}

      case Participant.transact(canvas.participant, canvas.canvas, [%{change | by: who}]) do
        {:ok, _receipt} -> :ok
        {:error, reason} -> Context.error(reason)
      end
    end

    # The agent's pointer, selection and drags, as the canvas draws a
    # person's: the canvas's own keys, under its document.
    def aware(%__MODULE__{} = canvas, state),
      do: Participant.aware_block(canvas.participant, canvas.canvas, state)

    # Whether the agent goes to where it works, and drags, as a hand does
    # (`config :hakushi, Hakushi.Issho, travel: true`), or is there at once.
    def travel?, do: Keyword.get(Application.get_env(:hakushi, Hakushi.Issho, []), :travel, true)

    # Moves the pointer to a point of the canvas, with Issho's motion
    # (`Issho.Motion`): only where it goes is sent, with the canvas's own
    # state that changes with it (its cursor, selection, drag); each browser
    # draws the way there; it moves only for someone who sees the canvas.
    def glide(%__MODULE__{} = canvas, {x, y}, extra \\ %{}, gesture \\ :move) do
      Issho.Motion.go(canvas.participant, %{"doc" => canvas.canvas, "at" => %{"point" => [x, y]}},
        gesture: gesture,
        travel: travel?(),
        block: Map.put(extra, "cursor", [x, y])
      )
    end

    # A point on a node, to point at it.
    def on(%Hakushi.Node{x: x, y: y, width: w, height: h}),
      do: {x + (w || 80) / 2, y + min(h || 40, 40) / 2}

    def node(%__MODULE__{graph: graph}, id) do
      case Graph.node(graph, id) do
        nil -> {:error, "The canvas has no node #{inspect(id)}."}
        node -> {:ok, node}
      end
    end

    # JSON from an agent as a node's data: the keys the app's data has as
    # atoms become those atoms (an app reads `node.data.name`); others stay
    # strings. No atom is made from what an agent sends.
    # The data an agent gives a node, in the shape of the canvas's own: with
    # atom keys where its nodes of that type have them (an app's seeds), with
    # string keys where they do not (a graph saved as JSON), so a node's
    # template reads the agent's nodes as it reads the others.
    def data(%__MODULE__{graph: graph}, type, value) do
      if atom_keys?(graph, type), do: atomize(value), else: value
    end

    # Merged into a node's own data, in its shape.
    def data_like(%{} = existing, value) do
      if Enum.any?(Map.keys(existing), &is_atom/1), do: atomize(value), else: value
    end

    defp atom_keys?(graph, type) do
      nodes = Graph.nodes(graph)
      like = Enum.filter(nodes, &(&1.type == type))
      sample = Enum.find(if(like == [], do: nodes, else: like), &(map_size(&1.data) > 0))
      sample != nil and Enum.any?(Map.keys(sample.data), &is_atom/1)
    end

    defp atomize(value) when is_map(value),
      do: Map.new(value, fn {key, v} -> {key(key), atomize(v)} end)

    defp atomize(value) when is_list(value), do: Enum.map(value, &atomize/1)
    defp atomize(value), do: value

    defp key(key) when is_binary(key) do
      String.to_existing_atom(key)
    rescue
      ArgumentError -> key
    end

    defp key(key), do: key

    def error({:error, reason}), do: Context.error(reason)
  end

  defmodule Hakushi.Issho.Tools.Read do
    @moduledoc false
    use Issho.Tool,
      name: "read_canvas",
      description: """
      Reads a shared canvas: its nodes (id, type, place, size, data, the
      group they are in) and its edges (between nodes, from handle to
      handle). Places are in the canvas's coordinates. With `of`, a person
      in the room, also the nodes they have selected and where their
      pointer is: act on them with the other tools ("connect what Ada
      selected to the invoice").

      What a person sees, which the graph does not say (`seen_by`, the
      person of `of`, else the one you act for, else anyone with the
      canvas open): each node on their screen has its `box` there ([x, y,
      width, height]), and an edge that passes under other nodes on its
      way has `passes_under`, their ids. The node on top hides that part
      of the line, so to a person it seems to end at that node: it does
      not join it. Its ends are `source` and `target`, always.
      """,
      annotations: [read_only: true, idempotent: true]

    arg :canvas, :string, required: true, description: "The canvas's document: \"atelier:schema\""
    arg :of, :string, description: "A person in the room, by name: what they have selected"

    alias Hakushi.Graph
    alias Hakushi.Issho.Tools.Canvas

    @impl true
    def call(%{canvas: name} = args, ctx) do
      with {:ok, canvas} <- Canvas.open(ctx, name) do
        {seer, seen} = seen(canvas, args[:of], ctx)
        boxes = seen["nodes"] || %{}
        under = seen["edges"] || %{}

        %{
          "nodes" =>
            canvas.graph
            |> Graph.nodes()
            |> Enum.map(&(&1 |> Map.from_struct() |> put_some("box", boxes[&1.id]))),
          "edges" =>
            canvas.graph
            |> Graph.edges()
            |> Enum.map(
              &(&1
                |> Map.from_struct()
                |> put_some("passes_under", get_in(under, [&1.id, "under"])))
            )
        }
        |> put_some("seen_by", seer)
        |> selected(canvas, args[:of])
      end
    end

    defp put_some(map, _key, nil), do: map
    defp put_some(map, key, value), do: Map.put(map, key, value)

    # What a person sees of the canvas (its block's "seen", from their
    # browser): the person asked about, else the one the agent acts for,
    # else anyone with it open; their name and it, or {nil, %{}}.
    defp seen(canvas, of, ctx) do
      canvas.participant
      |> Issho.Participant.people()
      |> seers(of, ctx.opts[:on_behalf_of])
      |> Enum.find_value({nil, %{}}, fn {key, entry} ->
        case seen_of(entry, canvas.canvas) do
          nil -> nil
          seen -> {entry["person"]["name"] || key, seen}
        end
      end)
    end

    defp seers(people, of, _behalf) when is_binary(of) do
      of = of |> String.trim() |> String.downcase()

      Enum.filter(people, fn {key, %{"person" => person}} ->
        String.downcase(key) == of or String.downcase(person["name"] || "") == of
      end)
    end

    defp seers(people, nil, nil), do: Enum.to_list(people)

    defp seers(people, nil, behalf) do
      key = Issho.Actor.key(behalf)
      {first, rest} = Enum.split_with(people, &(elem(&1, 0) == key))
      first ++ rest
    end

    defp seen_of(entry, doc) do
      entry
      |> Map.get("states", [])
      |> Enum.find_value(&Issho.Awareness.block(&1, doc)["seen"])
    end

    defp selected(read, _canvas, nil), do: {:ok, read}

    # A person's selection and pointer, from the session of theirs that has
    # the canvas open (its keys under the canvas's document: "selected",
    # "cursor").
    defp selected(read, canvas, who) do
      with {:ok, %{name: name, states: states}} <- Issho.Tools.person_of(canvas.participant, who) do
        state =
          states
          |> Enum.map(&Issho.Awareness.block(&1, canvas.canvas))
          |> Enum.find(%{}, &Map.has_key?(&1, "selected"))

        ids = Enum.filter(state["selected"] || [], &Graph.node(canvas.graph, &1))

        {:ok,
         Map.put(read, "of", %{
           "name" => name,
           "selected" => ids,
           "pointer" => state["cursor"]
         })}
      end
    end
  end

  defmodule Hakushi.Issho.Tools.Point do
    @moduledoc false
    use Issho.Tool,
      name: "point_at",
      description: """
      Moves your pointer, which the others see with your name: to a node,
      or to a point of the canvas. `select` selects nodes as well.
      """,
      annotations: [idempotent: true]

    arg :canvas, :string, required: true
    arg :node, :string, description: "A node's id"
    arg :x, :number
    arg :y, :number
    arg :select, {:array, :string}, description: "Nodes to select, by id"

    alias Hakushi.Issho.Tools.Canvas

    @impl true
    def call(args, ctx) do
      with {:ok, canvas} <- Canvas.open(ctx, args.canvas),
           {:ok, point} <- point(canvas, args),
           :ok <- Canvas.glide(canvas, point, %{"selected" => args[:select] || []}) do
        {:ok, "Pointing there."}
      else
        error -> Canvas.error(error)
      end
    end

    defp point(canvas, %{node: id}) when is_binary(id),
      do: with({:ok, node} <- Canvas.node(canvas, id), do: {:ok, Canvas.on(node)})

    defp point(_canvas, %{x: x, y: y}) when is_number(x) and is_number(y), do: {:ok, {x, y}}
    defp point(_canvas, _args), do: {:error, "Say where: a node, or x and y."}
  end

  defmodule Hakushi.Issho.Tools.Add do
    @moduledoc false
    use Issho.Tool,
      name: "add_node",
      description: """
      Adds a node at a place of the canvas, as a person drops one: its type
      (one the canvas draws), and its data, in the shape the canvas's other
      nodes of that type have. Your pointer goes there first.
      """,
      annotations: []

    arg :canvas, :string, required: true
    arg :x, :number, required: true
    arg :y, :number, required: true
    arg :type, :string, description: "The node's type (\"default\" unless given)"
    arg :data, :any, description: "The node's data"
    arg :parent, :string, description: "The group it goes in"

    alias Hakushi.{Canvas, Change}
    alias Hakushi.Issho.Tools.Canvas, as: Shared

    @impl true
    def call(args, ctx) do
      id = Canvas.new_id()

      type = args[:type] || "default"

      with {:ok, canvas} <- Shared.open(ctx, args.canvas),
           node = %{
             id: id,
             type: type,
             x: args.x,
             y: args.y,
             data: Shared.data(canvas, type, args[:data] || %{}),
             parent: args[:parent]
           },
           :ok <- Shared.glide(canvas, {args.x + 20, args.y + 20}),
           :ok <- Shared.change(canvas, Change.add([node])),
           :ok <- Shared.aware(canvas, %{"selected" => [id]}) do
        {:ok, %{"id" => id}}
      else
        error -> Shared.error(error)
      end
    end
  end

  defmodule Hakushi.Issho.Tools.Move do
    @moduledoc false
    use Issho.Tool,
      name: "move_node",
      description: """
      Moves a node to a place, as a person drags it: the others see your
      pointer take it and the node go there, then it lands.
      """,
      annotations: [idempotent: true]

    arg :canvas, :string, required: true
    arg :node, :string, required: true
    arg :x, :number, required: true
    arg :y, :number, required: true

    alias Hakushi.Change
    alias Hakushi.Issho.Tools.Canvas

    @impl true
    def call(%{node: id, x: x, y: y} = args, ctx) do
      with {:ok, canvas} <- Canvas.open(ctx, args.canvas),
           {:ok, node} <- Canvas.node(canvas, id),
           :ok <- Canvas.glide(canvas, Canvas.on(node), %{"selected" => [id]}),
           :ok <- drag(canvas, node, x, y),
           :ok <- Canvas.change(canvas, Change.move([{id, x, y}])),
           :ok <- Canvas.aware(canvas, %{"dragging" => []}) do
        {:ok, %{"moved" => id, "x" => x, "y" => y}}
      else
        error -> Canvas.error(error)
      end
    end

    # The node goes with the pointer, as the canvas shows a drag: where it
    # lands is sent, and each browser draws it on its way there.
    defp drag(canvas, node, x, y) do
      {grab_x, grab_y} = Canvas.on(node)
      point = {x + grab_x - node.x, y + grab_y - node.y}
      Canvas.glide(canvas, point, %{"dragging" => [[node.id, x, y]]}, :drag)
    end
  end

  defmodule Hakushi.Issho.Tools.Connect do
    @moduledoc false
    use Issho.Tool,
      name: "connect_nodes",
      description: """
      Draws an edge from a node to another, from a handle to a handle when
      the nodes have them (a table's columns): the canvas's rules decide if
      they may be joined, and say why not.
      """,
      annotations: []

    arg :canvas, :string, required: true
    arg :source, :string, required: true
    arg :target, :string, required: true
    arg :source_handle, :string
    arg :target_handle, :string
    arg :label, :string

    alias Hakushi.{Canvas, Change}
    alias Hakushi.Issho.Tools.Canvas, as: Shared

    @impl true
    def call(args, ctx) do
      edge =
        %{id: Canvas.new_id(), source: args.source, target: args.target}
        |> Map.merge(Map.take(args, [:source_handle, :target_handle, :label]))

      with {:ok, canvas} <- Shared.open(ctx, args.canvas),
           {:ok, source} <- Shared.node(canvas, args.source),
           {:ok, target} <- Shared.node(canvas, args.target),
           :ok <- Shared.glide(canvas, Shared.on(source)),
           :ok <- Shared.glide(canvas, Shared.on(target)),
           :ok <- Shared.change(canvas, Change.connect(edge)) do
        {:ok, %{"id" => edge.id}}
      else
        error -> Shared.error(error)
      end
    end
  end

  defmodule Hakushi.Issho.Tools.Update do
    @moduledoc false
    use Issho.Tool,
      name: "update_node",
      description: """
      Changes a node's data (the keys you give, the others as they are), or
      its type, or locks it.
      """,
      annotations: [idempotent: true]

    arg :canvas, :string, required: true
    arg :node, :string, required: true
    arg :data, :any, description: "The keys of its data that change"
    arg :type, :string
    arg :locked, :boolean

    alias Hakushi.Change
    alias Hakushi.Issho.Tools.Canvas

    @impl true
    def call(%{node: id} = args, ctx) do
      with {:ok, canvas} <- Canvas.open(ctx, args.canvas),
           {:ok, node} <- Canvas.node(canvas, id),
           :ok <- Canvas.glide(canvas, Canvas.on(node), %{"selected" => [id]}),
           update = update(node, args),
           :ok <- Canvas.change(canvas, Change.update(nodes: [update])) do
        {:ok, %{"updated" => id}}
      else
        error -> Canvas.error(error)
      end
    end

    defp update(node, args) do
      %{id: node.id}
      |> then(
        &if(is_map(args[:data]),
          do: Map.put(&1, :data, Map.merge(node.data, Canvas.data_like(node.data, args.data))),
          else: &1
        )
      )
      |> then(&if(args[:type], do: Map.put(&1, :type, args.type), else: &1))
      |> then(&if(is_boolean(args[:locked]), do: Map.put(&1, :locked, args.locked), else: &1))
    end
  end

  defmodule Hakushi.Issho.Tools.Delete do
    @moduledoc false
    use Issho.Tool,
      name: "delete_items",
      description: "Deletes nodes (with the nodes in them, and their edges) and edges, by id.",
      annotations: [destructive: true]

    arg :canvas, :string, required: true
    arg :nodes, {:array, :string}
    arg :edges, {:array, :string}

    alias Hakushi.Change
    alias Hakushi.Issho.Tools.Canvas

    @impl true
    def call(args, ctx) do
      nodes = args[:nodes] || []
      edges = args[:edges] || []

      with true <- (nodes != [] or edges != []) || {:error, "Say which nodes or edges."},
           {:ok, canvas} <- Canvas.open(ctx, args.canvas),
           :ok <- Canvas.aware(canvas, %{"selected" => nodes}),
           :ok <- Canvas.change(canvas, Change.delete(nodes: nodes, edges: edges)) do
        {:ok, %{"deleted" => %{"nodes" => nodes, "edges" => edges}}}
      else
        error -> Canvas.error(error)
      end
    end
  end
end
