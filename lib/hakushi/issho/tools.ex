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

    # How the agent draws with ink (`config :hakushi, Hakushi.Issho, ink:
    # [...]`): `live`, `speed` (pixels of the canvas a second), `max` (the
    # most a drawing takes, in milliseconds).
    def ink(key, default),
      do:
        Application.get_env(:hakushi, Hakushi.Issho, [])
        |> Keyword.get(:ink, [])
        |> Keyword.get(key, default)

    # A node's box as the people see it ([x, y, width, height]): its size
    # is its content's, which only a browser knows (what a person sees of
    # the canvas, `seen`); else its own, or a guess.
    def box(%__MODULE__{} = canvas, %Hakushi.Node{} = node) do
      seen =
        canvas.participant
        |> Issho.Participant.people()
        |> Enum.flat_map(fn {_key, entry} -> Map.get(entry, "states", []) end)
        |> Enum.find_value(
          &get_in(Issho.Awareness.block(&1, canvas.canvas), ["seen", "nodes", node.id])
        )

      case seen do
        [_x, _y, w, h] -> {node.x, node.y, w, h}
        _none -> {node.x, node.y, node.width || 160, node.height || 60}
      end
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

  defmodule Hakushi.Issho.Tools.Draw do
    @moduledoc false
    use Issho.Tool,
      name: "draw_on_canvas",
      description: """
      Draws on a shared canvas with a pen (a canvas with ink, whose
      strokes are nodes of type "ink-stroke"): strokes through points of
      the canvas, or a ring `around` a node, to circle it. The people see
      your pen draw each stroke, as they see a person's, and each one
      lands as a node when the pen lifts, which they move, erase and undo
      as any. Give each stroke enough points for its shape (a curve, every
      few pixels; the pen goes from point to point in straight lines).
      With `live` false, the strokes land at once.
      """,
      annotations: []

    @stroke [
      {:points, {:array, {:array, :number}},
       required: true, description: "[x, y] points of the canvas, in order"},
      {:color, :string, []},
      {:size, :number, min: 1, max: 64},
      {:tool, {:enum, ["pen", "highlighter"]}, []}
    ]

    arg :canvas, :string, required: true
    arg :strokes, {:array, {:object, @stroke}}, description: "The strokes, drawn in turn"
    arg :around, :string, description: "A node's id: a ring drawn around it"
    arg :color, :string, description: "ink, red, orange, yellow, green, blue or violet"
    arg :size, :number, min: 1, max: 64, description: "The width of the line"
    arg :tool, {:enum, ["pen", "highlighter"]}, description: "pen, unless given"

    arg :live, :boolean,
      description: "Whether the people see each stroke as it is drawn (true, unless the app says)"

    alias Hakushi.Change
    alias Hakushi.Issho.Tools.Canvas
    alias Hakushi.Kits.Ink

    # A stroke's points: one every few pixels, so that the pen goes as a
    # hand does; no more than a stroke has.
    @spacing 3
    @max_points 1_500
    # A frame of a stroke being drawn.
    @frame 40

    @impl true
    def call(args, ctx) do
      with {:ok, canvas} <- Canvas.open(ctx, args.canvas),
           {:ok, lines} <- lines(canvas, args),
           {:ok, nodes} <- nodes(lines, args) do
        live = live?(canvas, args, hd(lines))
        budget = if live, do: Canvas.ink(:max, 8_000), else: 0
        draw(canvas, nodes, live, System.monotonic_time(:millisecond) + budget, [])
      else
        error -> Canvas.error(error)
      end
    end

    defp lines(canvas, %{around: id} = args) when is_binary(id) do
      with {:ok, node} <- Canvas.node(canvas, id),
           do: {:ok, [%{points: ring(Canvas.box(canvas, node))} | args[:strokes] || []]}
    end

    defp lines(_canvas, %{strokes: [_ | _] = strokes}), do: {:ok, strokes}
    defp lines(_canvas, _args), do: {:error, "Say what to draw: strokes, or a node to circle."}

    # Each line as a stroke's node, in the canvas's terms.
    defp nodes(lines, args) do
      Enum.reduce_while(lines, {:ok, []}, fn line, {:ok, acc} ->
        points = line.points |> Enum.filter(&match?([_, _ | _], &1)) |> resample() |> taper()

        case Ink.stroke(points, stroke_opts(line, args)) do
          {:ok, node} ->
            {:cont, {:ok, [{points, Map.put(node, :id, Hakushi.Canvas.new_id())} | acc]}}

          :error ->
            {:halt, {:error, "A stroke needs points: [[x, y], ...]."}}
        end
      end)
      |> case do
        {:ok, nodes} -> {:ok, Enum.reverse(nodes)}
        error -> error
      end
    end

    # A stroke's tool, colour and width: its own, else the drawing's (a ring
    # is red).
    defp stroke_opts(line, args) do
      [
        tool: line[:tool] || args[:tool],
        color: line[:color] || args[:color] || if(args[:around], do: "red"),
        size: line[:size] || args[:size]
      ]
    end

    # The people see the pen draw: unless the agent or the app says not,
    # agents do not travel, or no one sees the canvas.
    defp live?(canvas, args, %{points: [[x, y | _] | _]}) do
      args[:live] != false and Canvas.ink(:live, true) != false and Canvas.travel?() and
        Issho.Motion.travel?() and
        Issho.Motion.watched?(canvas.participant, %{
          "doc" => canvas.canvas,
          "at" => %{"point" => [x, y]}
        })
    end

    defp live?(_canvas, _args, _line), do: false

    defp draw(canvas, [], _live, _deadline, ids) do
      with :ok <- Canvas.aware(canvas, %{"ink" => nil}),
           do: {:ok, %{"strokes" => Enum.reverse(ids)}}
    end

    defp draw(canvas, [{points, node} | rest], live, deadline, ids) do
      [x, y | _] = hd(points)

      with :ok <- if(live, do: Canvas.glide(canvas, {x, y}), else: :ok),
           :ok <- if(live, do: stroke(canvas, points, node, deadline), else: :ok),
           :ok <- Canvas.change(canvas, Change.add([node])),
           :ok <- Canvas.aware(canvas, %{"ink" => nil}) do
        draw(canvas, rest, live, deadline, [node.id | ids])
      end
    end

    # The stroke as the pen draws it: more of it each frame, in the agent's
    # awareness (the canvas's own keys, as a person's line), with its
    # pointer at the pen's tip; as fast as the app says, and faster when
    # the drawing's time runs out.
    defp stroke(canvas, points, node, deadline) do
      length = length_of(points)
      left = max(0, deadline - System.monotonic_time(:millisecond))
      ms = min(round(length / max(Canvas.ink(:speed, 900), 1) * 1000), left)
      frames = max(1, div(ms, @frame))
      count = length(points)

      base = %{
        "tool" => "ink:" <> node.data["tool"],
        "color" => node.data["color"],
        "size" => node.data["size"]
      }

      Enum.reduce_while(1..frames, :ok, fn frame, :ok ->
        shown = Enum.take(points, max(1, div(count * frame, frames)))
        show(canvas, Map.put(base, "points", Enum.map(shown, &sent/1)), frame < frames)
      end)
    end

    # A frame of the stroke: as much of the line as is drawn, the pointer
    # at its tip.
    defp show(canvas, ink, more) do
      [tx, ty, _p] = List.last(ink["points"])

      case Canvas.aware(canvas, %{"cursor" => [tx, ty], "ink" => ink}) do
        :ok ->
          if more, do: Process.sleep(@frame)
          {:cont, :ok}

        error ->
          {:halt, error}
      end
    end

    defp sent([x, y, p]), do: [Float.round(x * 1.0, 1), Float.round(y * 1.0, 1), p]

    # A ring around a node, as a hand draws one: a little wider than the
    # node, not quite round, and past where it began.
    defp ring({x, y, w, h}) do
      {cx, cy} = {x + w / 2, y + h / 2}
      {rx, ry} = {w / 2 + 22, h / 2 + 18}
      steps = 72

      for i <- 0..steps do
        t = i / steps
        angle = -2.1 + t * :math.pi() * 2.12
        wobble = 1 + 0.035 * :math.sin(t * 9 + 0.6) + 0.05 * t
        [cx + :math.cos(angle) * rx * wobble, cy + :math.sin(angle) * ry * wobble]
      end
    end

    # A point every few pixels along the line, and no more than a stroke has.
    defp resample([]), do: []
    defp resample([only]), do: [only]

    defp resample(points) do
      spacing = max(@spacing, length_of(points) / (@max_points - 1))

      points
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.flat_map(fn [[ax, ay | _], [bx, by | _]] ->
        n = max(1, ceil(:math.sqrt((bx - ax) ** 2 + (by - ay) ** 2) / spacing))
        for i <- 0..(n - 1), do: [ax + (bx - ax) * i / n, ay + (by - ay) * i / n]
      end)
      |> Kernel.++([List.last(points)])
      |> Enum.take(@max_points)
    end

    # A pen's pressure, lighter where it lands and where it lifts.
    defp taper(points) do
      count = length(points)
      ends = max(1, min(12, div(count, 6)))

      points
      |> Enum.with_index()
      |> Enum.map(fn {[x, y | _], i} ->
        edge = min(i, count - 1 - i)
        [x, y, Float.round(0.3 + 0.25 * min(1, edge / ends), 2)]
      end)
    end

    defp length_of(points) do
      points
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.reduce(0, fn [[ax, ay | _], [bx, by | _]], sum ->
        sum + :math.sqrt((bx - ax) ** 2 + (by - ay) ** 2)
      end)
    end
  end

  defmodule Hakushi.Issho.Tools.Image do
    @moduledoc false
    use Issho.Tool,
      name: "add_image",
      description: """
      Adds an image to a shared canvas with images (nodes of type "image"),
      from an address (`url`, of a host the app allows) or a file of the
      app's (`file`, a name the app knows), at a point of the canvas, as
      wide as `width` (its own aspect ratio, and at most 480 unless given),
      with alt text that says what it shows and a caption. The others see
      its placeholder while it comes, then the image.
      """,
      annotations: []

    arg :canvas, :string, required: true
    arg :url, :string, description: "The image's address (https)"
    arg :file, :string, description: "A file of the app's, by the name the app gives it"
    arg :x, :number, required: true, description: "The image's left"
    arg :y, :number, required: true, description: "The image's top"
    arg :width, :number, description: "The image's width on the canvas"
    arg :alt, :string, description: "What the image shows, for those who do not see it"
    arg :caption, :string, description: "A caption under the image"

    alias Hakushi.{Change, Images}
    alias Hakushi.Issho.Tools.Canvas
    alias Hakushi.Kits.Images, as: Kit

    @impl true
    def call(args, ctx) do
      with {:ok, source} <- source(args),
           {:ok, canvas} <- Canvas.open(ctx, args.canvas) do
        add(canvas, source, args)
      end
    end

    defp source(%{url: url}) when is_binary(url) and url != "", do: {:ok, {:url, url}}
    defp source(%{file: file}) when is_binary(file) and file != "", do: {:ok, {:file, file}}
    defp source(_args), do: {:error, "Say which image: a url, or a file of the app's."}

    # The pointer goes there, and the image's placeholder shows while it
    # comes; then the image is there, selected.
    defp add(canvas, source, %{x: x, y: y} = args) do
      w = if is_number(args[:width]) and args[:width] >= 16, do: args.width, else: 320
      placeholder = %{"files" => [[x, y, w, round(w * 0.75), 0]]}

      with :ok <- Canvas.glide(canvas, {x, y}, placeholder),
           {:ok, image} <- fetch(source),
           node =
             image
             |> Kit.image_node([x, y, args[:width] || 0, 0],
               alt: args[:alt],
               caption: args[:caption]
             )
             |> Map.put(:id, Hakushi.Canvas.new_id()),
           :ok <- Canvas.change(canvas, Change.add([node])),
           :ok <- Canvas.aware(canvas, %{"files" => [], "selected" => [node.id]}) do
        {:ok, %{"id" => node.id, "width" => node.width, "height" => node.height}}
      else
        {:error, reason} = error ->
          _ = Canvas.aware(canvas, %{"files" => []})
          if is_binary(reason), do: error, else: {:error, message(reason)}
      end
    end

    defp fetch({:url, url}) do
      config = Kit.config()

      case config[:fetch] do
        [_ | _] = hosts -> Images.fetch(url, Kit.store_opts(config, hosts: hosts))
        _none -> {:error, :not_allowed}
      end
    end

    defp fetch({:file, name}) do
      config = Kit.config()

      with fun when is_function(fun, 1) <- config[:files] || {:error, :no_files},
           {:ok, path} when is_binary(path) <- fun.(name) do
        Images.store(path, Kit.store_opts(config, name: Path.basename(path)))
      else
        {:error, _reason} = error -> error
        _other -> {:error, :no_file}
      end
    end

    defp message(:not_allowed), do: "The app does not take images from that address."
    defp message(:no_files), do: "The app gives no files by name."
    defp message(:no_file), do: "The app has no file of that name."

    defp message(:not_an_image),
      do: "That is not an image the canvas takes (PNG, JPEG, GIF or WebP)."

    defp message(:too_large), do: "That image is too large."
    defp message(reason), do: "The image could not be added: #{inspect(reason)}."
  end

  defmodule Hakushi.Issho.Tools.Shape do
    @moduledoc false
    use Issho.Tool,
      name: "draw_shape",
      description: """
      Draws a shape on a shared canvas with shapes (nodes of type "shape"):
      a rectangle, an ellipse, a diamond, a triangle or text, in a box of
      the canvas, with its text and its style; or a line of its own from a
      point to a point (to join two nodes, use connect_nodes). With `node`,
      changes a shape that is there: its text, its style, its rotation.
      Your pointer goes there, and draws it, as a person does.

      A style has `fill` and `stroke` (ink, gray, blue, green, yellow, red,
      violet, or none), `width` (1, 2 or 4), `dash` (true or false),
      `radius` (0 or 8), `size` of the text (s, m or l), `align` (left,
      center or right), `rotation` (degrees) and, for a line, `arrow` (end,
      both or none).
      """,
      annotations: []

    arg :canvas, :string, required: true
    arg :kind, {:enum, ["rect", "ellipse", "diamond", "triangle", "text", "line"]}
    arg :x, :number, description: "The box's left, or a line's start"
    arg :y, :number, description: "The box's top, or a line's start"
    arg :width, :number, description: "The box's width (the kind's own unless given)"
    arg :height, :number, description: "The box's height"
    arg :to_x, :number, description: "A line's end"
    arg :to_y, :number, description: "A line's end"
    arg :text, :string, description: "The text in the shape"
    arg :style, :any, description: "The style (see above)"
    arg :node, :string, description: "A shape there, to change"

    alias Hakushi.Change
    alias Hakushi.Issho.Tools.Canvas
    alias Hakushi.Kits.Shapes

    @impl true
    def call(args, ctx) do
      with {:ok, canvas} <- Canvas.open(ctx, args.canvas) do
        if args[:node], do: change(canvas, args), else: add(canvas, args)
      end
    end

    defp add(canvas, %{kind: "line", x: x, y: y, to_x: to_x, to_y: to_y} = args)
         when is_number(x) and is_number(y) and is_number(to_x) and is_number(to_y) do
      {:ok, node} = Shapes.line({x, y}, {to_x, to_y}, style(args))
      draw(canvas, Map.put(node, :id, Hakushi.Canvas.new_id()), {x, y}, {to_x, to_y})
    end

    defp add(_canvas, %{kind: "line"}), do: {:error, "A line needs x, y, to_x and to_y."}

    defp add(canvas, %{x: x, y: y} = args) when is_number(x) and is_number(y) do
      kind = args[:kind] || "rect"
      style = Map.put(style(args), "text", args[:text] || "")
      node = kind |> Shapes.shape([x, y, args[:width] || 0, args[:height] || 0], style)
      node = Map.put(node, :id, Hakushi.Canvas.new_id())
      draw(canvas, node, {x, y}, {node.x + node.width, node.y + node.height})
    end

    defp add(_canvas, _args), do: {:error, "Say where: x and y (and to_x and to_y for a line)."}

    # The pointer goes to a corner, and drags to the other, as a person
    # draws a shape; then it is there.
    defp draw(canvas, node, from, to) do
      with :ok <- Canvas.glide(canvas, from),
           :ok <- Canvas.glide(canvas, to, %{}, :drag),
           :ok <- Canvas.change(canvas, Change.add([node])),
           :ok <- Canvas.aware(canvas, %{"selected" => [node.id]}) do
        {:ok, %{"id" => node.id}}
      else
        error -> Canvas.error(error)
      end
    end

    defp change(canvas, %{node: id} = args) do
      with {:ok, node} <- Canvas.node(canvas, id),
           true <- node.type in Shapes.types() || {:error, "#{inspect(id)} is not a shape."},
           :ok <- Canvas.glide(canvas, Canvas.on(node), %{"selected" => [id]}),
           {:ok, data} <- edited(node, args),
           :ok <- Canvas.change(canvas, Change.update(nodes: [%{id: id, data: data}])) do
        {:ok, %{"updated" => id}}
      else
        error -> Canvas.error(error)
      end
    end

    defp edited(node, args) do
      data = Hakushi.Kit.stringify(node.data)

      with {:ok, data} <- maybe(args[:text], data, &Shapes.edit("text", %{"value" => &1}, &2)),
           {:ok, data} <-
             maybe(non_empty(style(args)), data, &Shapes.edit("style", %{"style" => &1}, &2)),
           {:ok, data} <-
             maybe(style(args)["rotation"], data, &Shapes.edit("rotate", %{"value" => &1}, &2)) do
        {:ok, data}
      else
        :error -> {:error, "That style is not one the shape has."}
      end
    end

    defp maybe(nil, data, _fun), do: {:ok, data}
    defp maybe(value, data, fun), do: fun.(value, data)

    defp non_empty(map) when map_size(map) == 0, do: nil
    defp non_empty(map), do: map

    defp style(%{style: %{} = style}), do: Map.new(style, fn {k, v} -> {to_string(k), v} end)
    defp style(_args), do: %{}
  end
end
